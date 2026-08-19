public import Foundation
public import URIGit

public struct OperationListing: Hashable, Sendable {

    public let state: OperationState

    public let targetURL: URL

    public init(state: OperationState, targetURL: URL) {
        self.state = state
        self.targetURL = targetURL
    }
}

public struct OperationIndex: Sendable {

    private let git: Git

    private let paths: RuntimePaths

    private let stateStore: OperationStateStore

    private let ephemeralManager: EphemeralWorkspaceManager

    private let indexStore: OperationIndexStore

    public init(
        paths: RuntimePaths = .init(),
        git: Git = .init(),
    ) {
        self.git = git
        self.paths = paths
        self.stateStore = .init()
        self.ephemeralManager = .init(paths: paths, git: git)
        self.indexStore = .init(paths: paths)
    }

    public func list() async throws -> [OperationListing] {
        var listings = [String: OperationListing]()
        for entry in try indexStore.entries() {
            guard let listing = await regularListing(for: entry) else {
                continue
            }
            listings[listing.targetURL.path] = listing
        }
        for listing in try ephemeralManager.validListings() {
            let targetURL = URL(filePath: listing.path, directoryHint: .isDirectory)
                .standardizedFileURL.resolvingSymlinksInPath()
            listings[targetURL.path] = .init(state: listing.state, targetURL: targetURL)
        }
        return listings.values.sorted(by: { first, second in
            first.targetURL.path < second.targetURL.path
        })
    }

    func register(
        _ state: OperationState,
        for repository: GitRepository,
    ) throws {
        guard state.ephemeralID == nil else {
            return
        }
        let targetURL = repository.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let recordedTargetURL = URL(filePath: state.targetPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard targetURL.path == recordedTargetURL.path else {
            throw URIError.invalidState(
                "Operation index TARGET does not match the saved operation state.",
            )
        }
        try register(for: repository)
    }

    func register(for repository: GitRepository) throws {
        try indexStore.register(targetURL: repository.rootURL)
    }

    func remove(for repository: GitRepository) throws {
        try indexStore.remove(targetURL: repository.rootURL)
    }

    private func regularListing(
        for entry: OperationIndexEntry,
    ) async -> OperationListing? {
        let targetURL = URL(filePath: entry.record.targetPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard let repository = try? await git.openRepository(at: targetURL),
            repository.rootURL.path == targetURL.path,
            let stateURL = try? await stateStore.stateURL(
                for: repository,
                ephemeralID: nil,
                paths: paths,
            ),
            let state = try? stateStore.load(from: stateURL),
            state.ephemeralID == nil
        else {
            return nil
        }
        let recordedTargetURL = URL(filePath: state.targetPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard recordedTargetURL.path == repository.rootURL.path else {
            return nil
        }
        return .init(state: state, targetURL: repository.rootURL)
    }
}

struct OperationIndexRecord: Codable, Equatable, Sendable {

    static let currentSchemaVersion = 1

    var schemaVersion: Int

    var targetPath: String

    init(targetPath: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.targetPath = targetPath
    }
}

struct OperationIndexEntry: Equatable, Sendable {

    let url: URL

    let record: OperationIndexRecord
}

struct OperationIndexStore: Sendable {

    private let paths: RuntimePaths

    init(paths: RuntimePaths = .init()) {
        self.paths = paths
    }

    func register(targetURL: URL) throws {
        let canonical = targetURL.standardizedFileURL.resolvingSymlinksInPath()
        try validateOrCreateIndexDirectory()
        if try entries().contains(where: { entry in
            canonicalTargetURL(for: entry.record)?.path == canonical.path
        }) {
            return
        }
        do {
            let url = paths.operationIndexURL.appending(
                path: "\(UUID().uuidString).json",
                directoryHint: .notDirectory,
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(OperationIndexRecord(targetPath: canonical.path))
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
        }
        catch let error as URIError {
            throw error
        }
        catch {
            throw URIError.fileSystem(
                "Could not register URI operation TARGET \(canonical.path): \(error)",
            )
        }
    }

    func remove(targetURL: URL) throws {
        let canonical = targetURL.standardizedFileURL.resolvingSymlinksInPath()
        for entry in try entries()
        where canonicalTargetURL(for: entry.record)?.path == canonical.path {
            do {
                try FileManager.default.removeItem(at: entry.url)
            }
            catch {
                throw URIError.fileSystem(
                    "Could not remove URI operation index at \(entry.url.path): \(error)",
                )
            }
        }
    }

    func entries() throws -> [OperationIndexEntry] {
        guard FileManager.default.fileExists(atPath: paths.operationIndexURL.path) else {
            return []
        }
        try validateIndexDirectory()
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: paths.operationIndexURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
            )
        }
        catch {
            throw URIError.fileSystem(
                "Could not list URI operation index at \(paths.operationIndexURL.path): \(error)",
            )
        }

        var entries = [OperationIndexEntry]()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "json" {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            ),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(OperationIndexRecord.self, from: data),
                record.schemaVersion == OperationIndexRecord.currentSchemaVersion,
                canonicalTargetURL(for: record) != nil
            else {
                continue
            }
            entries.append(.init(url: url, record: record))
        }
        return entries
    }

    private func validateOrCreateIndexDirectory() throws {
        do {
            if FileManager.default.fileExists(atPath: paths.operationIndexURL.path) {
                try validateIndexDirectory()
                return
            }
            try FileManager.default.createDirectory(
                at: paths.operationIndexURL,
                withIntermediateDirectories: true,
            )
        }
        catch let error as URIError {
            throw error
        }
        catch {
            throw URIError.fileSystem(
                "Could not create URI operation index at \(paths.operationIndexURL.path): \(error)",
            )
        }
    }

    private func validateIndexDirectory() throws {
        do {
            let values = try paths.operationIndexURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            )
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw URIError.fileSystem(
                    "URI operation index is not a managed directory: \(paths.operationIndexURL.path)",
                )
            }
        }
        catch let error as URIError {
            throw error
        }
        catch {
            throw URIError.fileSystem(
                "Could not inspect URI operation index at \(paths.operationIndexURL.path): \(error)",
            )
        }
    }

    private func canonicalTargetURL(for record: OperationIndexRecord) -> URL? {
        guard record.targetPath.hasPrefix("/") else {
            return nil
        }
        return URL(filePath: record.targetPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
    }
}
