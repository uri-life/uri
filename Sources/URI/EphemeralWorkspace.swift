public import Foundation
public import URIGit

public struct EphemeralWorkspace: Hashable, Sendable {

    public let id: String

    public let rootURL: URL

    public let repositoryURL: URL

    public let stateURL: URL
}

public struct EphemeralListing: Hashable, Sendable {

    public let id: String

    public let state: OperationState

    public let path: String
}

public struct EphemeralWorkspaceManager: Sendable {

    private let paths: RuntimePaths

    private let git: Git

    private let stateStore: OperationStateStore

    public init(
        paths: RuntimePaths = .init(),
        git: Git = .init(),
        stateStore: OperationStateStore = .init(),
    ) {
        self.paths = paths
        self.git = git
        self.stateStore = stateStore
    }

    public func create(
        requestedID: String?,
        repositoryName: String = "repository",
    ) throws -> EphemeralWorkspace {
        try Self.validateRepositoryName(repositoryName)
        do {
            try FileManager.default.createDirectory(
                at: paths.ephemeralRootURL,
                withIntermediateDirectories: true,
            )
        }
        catch {
            throw URIError.fileSystem("Could not create ephemeral root: \(error)")
        }

        if let requestedID {
            try Self.validateID(requestedID)
            return try createDirectory(
                id: requestedID,
                repositoryName: repositoryName,
                collisionIsError: true,
            )
        }

        let words = candidateWords()
        for _ in 0..<256 {
            let first = words.randomElement() ?? "uri"
            let second = words.randomElement() ?? "workspace"
            let id = "\(first)-\(second)"
            if let workspace = try? createDirectory(
                id: id,
                repositoryName: repositoryName,
                collisionIsError: false,
            ) {
                return workspace
            }
        }
        for _ in 0..<256 {
            let id = "uri-\(UUID().uuidString.prefix(8).lowercased())"
            if let workspace = try? createDirectory(
                id: id,
                repositoryName: repositoryName,
                collisionIsError: false,
            ) {
                return workspace
            }
        }
        throw URIError.fileSystem("Could not allocate a unique ephemeral ID.")
    }

    public func workspace(id: String) throws -> EphemeralWorkspace {
        try Self.validateID(id)
        let workspace = makeWorkspace(id: id)
        guard isDirectory(workspace.rootURL) else {
            throw URIError.ephemeralNotFound(id)
        }
        try validateManagedPath(workspace)
        guard FileManager.default.fileExists(atPath: workspace.stateURL.path) else {
            return workspace
        }
        let state = try stateStore.load(from: workspace.stateURL)
        let persistedWorkspace = makeWorkspace(
            id: id,
            repositoryURL: URL(filePath: state.targetPath, directoryHint: .isDirectory),
        )
        try validateManagedPath(persistedWorkspace)
        try validateMetadata(state, workspace: persistedWorkspace)
        return persistedWorkspace
    }

    public func removeUninitialized(_ workspace: EphemeralWorkspace) throws {
        try validateManagedPath(workspace)
        guard !FileManager.default.fileExists(atPath: workspace.stateURL.path) else {
            throw URIError.unsafeEphemeral(
                "Refusing to remove initialized workspace as an incomplete allocation: \(workspace.id)",
            )
        }
        do {
            try FileManager.default.removeItem(at: workspace.rootURL)
        }
        catch {
            throw URIError.fileSystem("Could not remove incomplete workspace \(workspace.id): \(error)")
        }
    }

    public func list() throws -> [EphemeralListing] {
        guard isDirectory(paths.ephemeralRootURL) else {
            return []
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: paths.ephemeralRootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
            )
        }
        catch {
            throw URIError.fileSystem("Could not list ephemeral workspaces: \(error)")
        }

        return try urls.compactMap { url in
            let id = url.lastPathComponent
            guard (try? Self.validateID(id)) != nil else {
                return nil
            }
            let workspace = try workspace(id: id)
            let state = try stateStore.load(from: workspace.stateURL)
            try validateMetadata(state, workspace: workspace)
            return .init(id: id, state: state, path: workspace.repositoryURL.path)
        }.sorted(by: { $0.id < $1.id })
    }

    public func vanish(id: String, force: Bool) async throws {
        let workspace = try workspace(id: id)
        let state = try stateStore.load(from: workspace.stateURL)
        try validateMetadata(state, workspace: workspace)
        let repository = try await git.openRepository(at: workspace.repositoryURL)
        guard repository.rootURL.path == workspace.repositoryURL.resolvingSymlinksInPath().path else {
            throw URIError.unsafeEphemeral("Ephemeral repository root does not match its metadata: \(id)")
        }

        if !force {
            let status = try await repository.status()
            guard status.isCompletelyClean else {
                throw URIError.dirtyTarget(
                    "Ephemeral workspace \(id) has tracked or untracked changes; use --force to discard them.",
                )
            }
            guard try await repository.currentCommit().rawValue == (state.expectedCommit ?? state.baselineCommit) else {
                throw URIError.dirtyTarget(
                    "Ephemeral workspace \(id) moved from its recorded HEAD; use --force to discard it.",
                )
            }
        }

        do {
            try FileManager.default.removeItem(at: workspace.rootURL)
        }
        catch {
            throw URIError.fileSystem("Could not remove ephemeral workspace \(id): \(error)")
        }
        if let snapshotPath = state.snapshotPath {
            let resolver = PatchsetSourceResolver(paths: paths)
            try resolver.removeSnapshot(at: URL(filePath: snapshotPath))
        }
    }

    public static func validateID(_ id: String) throws {
        guard let first = id.utf8.first, isASCIIAlpha(first) || first == 95 else {
            throw URIError.invalidEphemeralID(id)
        }
        guard id.utf8.dropFirst().allSatisfy({ byte in
            isASCIIAlpha(byte) || (48...57).contains(byte) || byte == 95 || byte == 45
        }) else {
            throw URIError.invalidEphemeralID(id)
        }
    }

    private func createDirectory(
        id: String,
        repositoryName: String,
        collisionIsError: Bool,
    ) throws -> EphemeralWorkspace {
        let workspace = makeWorkspace(id: id, repositoryName: repositoryName)
        do {
            try FileManager.default.createDirectory(
                at: workspace.rootURL,
                withIntermediateDirectories: false,
            )
            return workspace
        }
        catch let error as CocoaError where error.code == .fileWriteFileExists {
            if collisionIsError {
                throw URIError.ephemeralExists(id)
            }
            throw error
        }
        catch {
            if FileManager.default.fileExists(atPath: workspace.rootURL.path) {
                if collisionIsError {
                    throw URIError.ephemeralExists(id)
                }
                throw error
            }
            throw URIError.fileSystem("Could not create ephemeral workspace \(id): \(error)")
        }
    }

    private func makeWorkspace(
        id: String,
        repositoryName: String = "repository",
    ) -> EphemeralWorkspace {
        makeWorkspace(
            id: id,
            repositoryURL: paths.repositoryURL(id: id, repositoryName: repositoryName),
        )
    }

    private func makeWorkspace(id: String, repositoryURL: URL) -> EphemeralWorkspace {
        .init(
            id: id,
            rootURL: paths.ephemeralURL(id: id),
            repositoryURL: repositoryURL,
            stateURL: paths.ephemeralStateURL(id: id),
        )
    }

    private func validateManagedPath(_ workspace: EphemeralWorkspace) throws {
        let rootValues = try workspace.rootURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true else {
            throw URIError.unsafeEphemeral("Ephemeral workspace is a symbolic link: \(workspace.id)")
        }
        if FileManager.default.fileExists(atPath: workspace.repositoryURL.path) {
            let repositoryValues = try workspace.repositoryURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard repositoryValues.isSymbolicLink != true else {
                throw URIError.unsafeEphemeral("Ephemeral repository is a symbolic link: \(workspace.id)")
            }
        }
        if FileManager.default.fileExists(atPath: workspace.stateURL.path) {
            let stateValues = try workspace.stateURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard stateValues.isSymbolicLink != true else {
                throw URIError.unsafeEphemeral("Ephemeral state is a symbolic link: \(workspace.id)")
            }
        }
        let expectedParent = paths.ephemeralRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let canonical = workspace.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.deletingLastPathComponent().path == expectedParent.path,
            canonical.lastPathComponent == workspace.id
        else {
            throw URIError.unsafeEphemeral("Ephemeral workspace escapes the managed root: \(workspace.id)")
        }
        let repository = workspace.repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard repository.deletingLastPathComponent().path == canonical.path else {
            throw URIError.unsafeEphemeral("Ephemeral repository escapes the managed workspace: \(workspace.id)")
        }
    }

    private func validateMetadata(
        _ state: OperationState,
        workspace: EphemeralWorkspace,
    ) throws {
        guard state.ephemeralID == workspace.id else {
            throw URIError.unsafeEphemeral("Ephemeral metadata ID does not match \(workspace.id).")
        }
        let target = URL(filePath: state.targetPath).standardizedFileURL.resolvingSymlinksInPath()
        let repository = workspace.repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard target.path == repository.path else {
            throw URIError.unsafeEphemeral("Ephemeral metadata path does not match \(workspace.id).")
        }
    }

    private func candidateWords() -> [String] {
        let fallback = [
            "apricot", "birch", "cedar", "cloud", "coral", "dawn", "fern", "fig",
            "ginger", "harbor", "indigo", "juniper", "kiwi", "lotus", "maple", "mint",
            "olive", "peach", "pebble", "plum", "quartz", "river", "saffron", "spruce",
            "tangerine", "violet", "willow", "yuzu",
        ]
        for path in ["/usr/share/dict/words", "/usr/dict/words"] {
            guard let data = FileManager.default.contents(atPath: path),
                let contents = String(data: data, encoding: .utf8)
            else {
                continue
            }
            let words = contents
                .split(whereSeparator: \.isNewline)
                .map({ $0.lowercased() })
                .filter({ word in
                    (4...10).contains(word.utf8.count)
                        && word.utf8.allSatisfy(Self.isASCIIAlpha)
                })
            if !words.isEmpty {
                return words
            }
        }
        return fallback
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func validateRepositoryName(_ name: String) throws {
        guard !name.isEmpty,
            name != ".",
            name != "..",
            !name.contains("/"),
            !name.contains(where: { $0.isNewline || $0 == "\0" }),
            name.caseInsensitiveCompare("state.json") != .orderedSame
        else {
            throw URIError.invalidArguments(
                "Upstream repository name cannot be used as an ephemeral directory: \(name)",
            )
        }
    }
}
