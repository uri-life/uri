public import Foundation
public import URIGit

public struct RuntimePaths: Sendable {

    public let homeURL: URL

    public init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeURL = homeURL.standardizedFileURL
    }

    public var rootURL: URL {
        homeURL.appending(path: ".uri", directoryHint: .isDirectory)
    }

    public var ephemeralRootURL: URL {
        rootURL.appending(path: "ephemeral", directoryHint: .isDirectory)
    }

    public var operationIndexURL: URL {
        rootURL.appending(path: "operations", directoryHint: .isDirectory)
    }

    public var operationCacheURL: URL {
        rootURL
            .appending(path: "cache", directoryHint: .isDirectory)
            .appending(path: "operations", directoryHint: .isDirectory)
    }

    package var ephemeralInternalURL: URL {
        ephemeralRootURL.appending(path: ".internal", directoryHint: .isDirectory)
    }

    package var ephemeralAllocationsURL: URL {
        ephemeralInternalURL.appending(path: "allocations", directoryHint: .isDirectory)
    }

    package var ephemeralRemovalsURL: URL {
        ephemeralInternalURL.appending(path: "removals", directoryHint: .isDirectory)
    }

    public func ephemeralURL(id: String) -> URL {
        ephemeralRootURL.appending(path: id, directoryHint: .isDirectory)
    }

    public func repositoryURL(id: String, repositoryName: String = "repository") -> URL {
        ephemeralURL(id: id).appending(path: repositoryName, directoryHint: .isDirectory)
    }

    public func ephemeralStateURL(id: String) -> URL {
        ephemeralURL(id: id).appending(path: "state.json", directoryHint: .notDirectory)
    }

    public func createOperationSnapshotDirectory() throws -> URL {
        do {
            try FileManager.default.createDirectory(
                at: operationCacheURL,
                withIntermediateDirectories: true,
            )
            let url = operationCacheURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
        catch {
            throw URIError.fileSystem("Could not create operation snapshot: \(error)")
        }
    }

    package func ephemeralInitializationURL(for rootURL: URL) -> URL {
        rootURL.appending(path: "initialization.json", directoryHint: .notDirectory)
    }
}

public struct OperationState: Codable, Hashable, Sendable {

    public enum Mode: String, Codable, Hashable, Sendable {
        case expand
        case apply
    }

    public enum Phase: String, Codable, Hashable, Sendable {
        case ante
        case main
        case post
        case active
    }

    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var mode: Mode
    public var phase: Phase
    public var source: PatchsetSource
    public var snapshotPath: String?
    public var upstreamVersion: String
    public var patchsetVersion: String
    public var feature: String?
    public var featureOrder: [String]
    public var currentIndex: Int
    public var targetPath: String
    public var startCommit: String
    public var startBranch: String?
    public var baselineCommit: String
    public var expectedCommit: String?
    public var branchPrefix: String
    public var committerName: String
    public var committerEmail: String
    public var ephemeralID: String?

    public init(
        mode: Mode,
        phase: Phase = .ante,
        source: PatchsetSource,
        snapshotPath: String?,
        upstreamVersion: String,
        patchsetVersion: String,
        feature: String?,
        featureOrder: [String],
        currentIndex: Int = 0,
        targetPath: String,
        startCommit: String,
        startBranch: String?,
        baselineCommit: String,
        expectedCommit: String? = nil,
        branchPrefix: String,
        committerName: String,
        committerEmail: String,
        ephemeralID: String?,
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.mode = mode
        self.phase = phase
        self.source = source
        self.snapshotPath = snapshotPath
        self.upstreamVersion = upstreamVersion
        self.patchsetVersion = patchsetVersion
        self.feature = feature
        self.featureOrder = featureOrder
        self.currentIndex = currentIndex
        self.targetPath = targetPath
        self.startCommit = startCommit
        self.startBranch = startBranch
        self.baselineCommit = baselineCommit
        self.expectedCommit = expectedCommit
        self.branchPrefix = branchPrefix
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.ephemeralID = ephemeralID
    }
}

public struct OperationStateStore: Sendable {

    public init() {}

    public func stateURL(
        for repository: GitRepository,
        ephemeralID: String?,
        paths: RuntimePaths,
    ) async throws -> URL {
        if let ephemeralID {
            return paths.ephemeralStateURL(id: ephemeralID)
        }
        return try await repository.gitPath("uri/state.json")
    }

    public func load(
        from url: URL,
    ) throws -> OperationState {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw URIError.operationNotFound("No URI operation state exists at \(url.path).")
        }
        do {
            let state = try JSONDecoder().decode(OperationState.self, from: Data(contentsOf: url))
            guard state.schemaVersion == OperationState.currentSchemaVersion else {
                throw URIError.invalidState(
                    "Unsupported URI state schema \(state.schemaVersion) at \(url.path).",
                )
            }
            return state
        }
        catch let error as URIError {
            throw error
        }
        catch {
            throw URIError.invalidState("Could not decode URI state at \(url.path): \(error)")
        }
    }

    public func loadIfPresent(from url: URL) throws -> OperationState? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try load(from: url)
    }

    public func save(_ state: OperationState, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(state)
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
        }
        catch {
            throw URIError.fileSystem("Could not save URI state at \(url.path): \(error)")
        }
    }

    public func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        }
        catch {
            throw URIError.fileSystem("Could not remove URI state at \(url.path): \(error)")
        }
    }
}
