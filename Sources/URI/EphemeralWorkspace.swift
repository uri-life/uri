public import Foundation
public import URIGit

public struct EphemeralWorkspace: Hashable, Sendable {

    public let id: String

    public let rootURL: URL

    public let repositoryURL: URL

    public let stateURL: URL

    package let initializationLease: EphemeralWorkspaceInitializationLease?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.rootURL == rhs.rootURL
            && lhs.repositoryURL == rhs.repositoryURL
            && lhs.stateURL == rhs.stateURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(rootURL)
        hasher.combine(repositoryURL)
        hasher.combine(stateURL)
    }
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

    private let fileOperations: EphemeralWorkspaceFileOperations

    private let lockOperations: EphemeralWorkspaceLockOperations

    private let cleanupRegistry: EphemeralWorkspaceCleanupRegistry

    public init(
        paths: RuntimePaths = .init(),
        git: Git = .init(),
        stateStore: OperationStateStore = .init(),
    ) {
        self.paths = paths
        self.git = git
        self.stateStore = stateStore
        self.fileOperations = .live
        self.lockOperations = .live
        self.cleanupRegistry = .shared
    }

    package init(
        paths: RuntimePaths,
        git: Git = .init(),
        stateStore: OperationStateStore = .init(),
        fileOperations: EphemeralWorkspaceFileOperations,
        lockOperations: EphemeralWorkspaceLockOperations = .live,
        cleanupRegistry: EphemeralWorkspaceCleanupRegistry,
    ) {
        self.paths = paths
        self.git = git
        self.stateStore = stateStore
        self.fileOperations = fileOperations
        self.lockOperations = lockOperations
        self.cleanupRegistry = cleanupRegistry
    }

    public func create(
        requestedID: String?,
        repositoryName: String = "repository",
    ) throws -> EphemeralWorkspace {
        try Self.validateRepositoryName(repositoryName)
        try ensureManagedDirectory(paths.ephemeralRootURL, includingIntermediates: true)
        try ensureManagedDirectory(paths.ephemeralInternalURL)
        try ensureManagedDirectory(paths.ephemeralAllocationsURL)

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
        let rootURL = paths.ephemeralURL(id: id)
        guard let inspection = try inspectActiveWorkspace(at: rootURL) else {
            throw URIError.ephemeralNotFound(id)
        }
        switch inspection.status {
        case .valid(let listing):
            return try initializedWorkspace(id: id, state: listing.state)
        case .initializing:
            throw URIError.ephemeralInitializing(id)
        case .interruptedInitialization, .legacyIncomplete:
            throw URIError.incompleteEphemeral(id)
        case .deferredRemoval:
            throw URIError.ephemeralNotFound(id)
        }
    }

    public func removeUninitialized(_ workspace: EphemeralWorkspace) throws {
        try validateManagedPath(workspace)
        guard !FileManager.default.fileExists(atPath: workspace.stateURL.path) else {
            throw URIError.unsafeEphemeral(
                "Refusing to remove initialized workspace as an incomplete allocation: \(workspace.id)",
            )
        }
        try retire(workspace: workspace, snapshotURL: nil)
    }

    package func completeInitialization(_ workspace: EphemeralWorkspace) {
        workspace.initializationLease?.finish(removingMarker: true)
    }

    public func list() throws -> [EphemeralListing] {
        try activeWorkspaceInspections().compactMap({ inspection in
            guard case .valid(let listing) = inspection.status else {
                return nil
            }
            return listing
        }).sorted(by: { $0.id < $1.id })
    }

    /// Returns active workspaces and hidden lifecycle artifacts without removing them.
    package func inspections() throws -> [EphemeralWorkspaceInspection] {
        try (activeWorkspaceInspections() + internalInspections()).sorted(by: { first, second in
            first.rootURL.path < second.rootURL.path
        })
    }

    package func activeWorkspaceInspections() throws -> [EphemeralWorkspaceInspection] {
        try activeWorkspaceURLs().compactMap({ url in
            try inspectActiveWorkspace(at: url)
        }).sorted(by: { $0.id < $1.id })
    }

    func validListings() throws -> [EphemeralListing] {
        var listings = [EphemeralListing]()
        for url in try activeWorkspaceURLs() {
            if let inspection = try? inspectActiveWorkspace(at: url),
                case .valid(let listing) = inspection.status
            {
                listings.append(listing)
            }
        }
        return listings.sorted(by: { $0.id < $1.id })
    }

    private func activeWorkspaceURLs() throws -> [URL] {
        guard isDirectory(paths.ephemeralRootURL) else {
            return []
        }
        do {
            return try FileManager.default.contentsOfDirectory(
                at: paths.ephemeralRootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
            )
        }
        catch {
            throw URIError.fileSystem("Could not list ephemeral workspaces: \(error)")
        }
    }

    public func vanish(id: String, force: Bool) async throws {
        try Self.validateID(id)
        guard let inspection = try inspectActiveWorkspace(at: paths.ephemeralURL(id: id)) else {
            throw URIError.ephemeralNotFound(id)
        }
        switch inspection.status {
        case .valid(let listing):
            let workspace = try initializedWorkspace(id: id, state: listing.state)
            let repository = try await git.openRepository(at: workspace.repositoryURL)
            guard repository.rootURL.path == workspace.repositoryURL.resolvingSymlinksInPath().path else {
                throw URIError.unsafeEphemeral(
                    "Ephemeral repository root does not match its metadata: \(id)",
                )
            }

            if !force {
                let status = try await repository.status()
                guard status.isCompletelyClean else {
                    throw URIError.dirtyTarget(
                        "Ephemeral workspace \(id) has tracked or untracked changes; use --force to discard them.",
                    )
                }
                guard try await repository.currentCommit().rawValue
                    == (listing.state.expectedCommit ?? listing.state.baselineCommit)
                else {
                    throw URIError.dirtyTarget(
                        "Ephemeral workspace \(id) moved from its recorded HEAD; use --force to discard it.",
                    )
                }
            }

            try retire(
                workspace: workspace,
                snapshotURL: listing.state.snapshotPath.map({URL(filePath: $0)}),
            )
        case .initializing:
            throw URIError.ephemeralInitializing(id)
        case .interruptedInitialization:
            guard force else {
                throw URIError.incompleteEphemeral(id)
            }
            let workspace = makeWorkspace(id: id)
            let markerURL = paths.ephemeralInitializationURL(for: workspace.rootURL)
            guard let lease = try lockOperations.tryAcquireLease(markerURL) else {
                throw URIError.ephemeralInitializing(id)
            }
            try retire(
                workspace: makeWorkspace(id: id, initializationLease: lease),
                snapshotURL: nil,
            )
        case .legacyIncomplete:
            guard force else {
                throw URIError.incompleteEphemeral(id)
            }
            try retire(workspace: makeWorkspace(id: id), snapshotURL: nil)
        case .deferredRemoval:
            throw URIError.ephemeralNotFound(id)
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
        let token = UUID().uuidString
        let stagingParent = paths.ephemeralAllocationsURL.appending(
            path: token,
            directoryHint: .isDirectory,
        )
        let stagingRoot = stagingParent.appending(path: id, directoryHint: .isDirectory)
        let workspace = makeWorkspace(id: id, repositoryName: repositoryName)
        let stagingMarker = paths.ephemeralInitializationURL(for: stagingRoot)
        let activeMarker = paths.ephemeralInitializationURL(for: workspace.rootURL)

        do {
            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: true,
            )
        }
        catch {
            throw URIError.fileSystem(
                "Could not stage ephemeral workspace \(id): \(error)",
            )
        }

        let metadata = EphemeralWorkspaceInitialization(
            id: id,
            targetPath: workspace.repositoryURL.path,
            createdAt: initializationTimestamp(),
        )
        let lease: EphemeralWorkspaceInitializationLease
        do {
            lease = try lockOperations.createLease(
                stagingMarker,
                activeMarker,
                initializationData(metadata),
            )
        }
        catch {
            try? fileOperations.removeItem(stagingParent)
            throw error
        }

        do {
            try fileOperations.moveItem(stagingRoot, workspace.rootURL)
            try? fileOperations.removeItem(stagingParent)
            return makeWorkspace(
                id: id,
                repositoryURL: workspace.repositoryURL,
                initializationLease: lease,
            )
        }
        catch {
            lease.finish(removingMarker: false)
            try? fileOperations.removeItem(stagingParent)
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
        initializationLease: EphemeralWorkspaceInitializationLease? = nil,
    ) -> EphemeralWorkspace {
        makeWorkspace(
            id: id,
            repositoryURL: paths.repositoryURL(id: id, repositoryName: repositoryName),
            initializationLease: initializationLease,
        )
    }

    private func makeWorkspace(
        id: String,
        repositoryURL: URL,
        initializationLease: EphemeralWorkspaceInitializationLease? = nil,
    ) -> EphemeralWorkspace {
        .init(
            id: id,
            rootURL: paths.ephemeralURL(id: id),
            repositoryURL: repositoryURL,
            stateURL: paths.ephemeralStateURL(id: id),
            initializationLease: initializationLease,
        )
    }

    private func inspectActiveWorkspace(
        at rootURL: URL,
    ) throws -> EphemeralWorkspaceInspection? {
        let id = rootURL.lastPathComponent
        guard (try? Self.validateID(id)) != nil else {
            return nil
        }
        let workspace = makeWorkspace(id: id)
        guard isDirectory(workspace.rootURL) else {
            throw URIError.ephemeralNotFound(id)
        }
        try validateManagedPath(workspace)

        if FileManager.default.fileExists(atPath: workspace.stateURL.path) {
            let state = try stateStore.load(from: workspace.stateURL)
            let initialized = try initializedWorkspace(id: id, state: state)
            return .init(
                id: id,
                rootURL: rootURL,
                location: .active,
                status: .valid(
                    .init(id: id, state: state, path: initialized.repositoryURL.path),
                ),
            )
        }

        let markerURL = paths.ephemeralInitializationURL(for: rootURL)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return .init(
                id: id,
                rootURL: rootURL,
                location: .active,
                status: .legacyIncomplete,
            )
        }
        try validateInitializationMarker(markerURL, id: id)
        let metadata = initializationMetadata(at: markerURL, id: id)
        guard let lease = try lockOperations.tryAcquireLease(markerURL) else {
            return .init(
                id: id,
                rootURL: rootURL,
                location: .active,
                status: .initializing(metadata),
            )
        }
        lease.finish(removingMarker: false)
        return .init(
            id: id,
            rootURL: rootURL,
            location: .active,
            status: .interruptedInitialization(metadata),
        )
    }

    private func internalInspections() throws -> [EphemeralWorkspaceInspection] {
        var inspections = [EphemeralWorkspaceInspection]()
        inspections.append(
            contentsOf: try internalInspections(
                under: paths.ephemeralAllocationsURL,
                deferredRemoval: false,
            ),
        )
        inspections.append(
            contentsOf: try internalInspections(
                under: paths.ephemeralRemovalsURL,
                deferredRemoval: true,
            ),
        )
        return inspections
    }

    private func internalInspections(
        under rootURL: URL,
        deferredRemoval: Bool,
    ) throws -> [EphemeralWorkspaceInspection] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }
        guard try isManagedDirectory(rootURL) else {
            throw URIError.fileSystem(
                "Ephemeral internal path is not a managed directory: \(rootURL.path)",
            )
        }
        let parents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        )
        var inspections = [EphemeralWorkspaceInspection]()
        for parent in parents where UUID(uuidString: parent.lastPathComponent) != nil {
            guard try isManagedDirectory(parent) else {
                continue
            }
            let children = try FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            )
            for child in children {
                let id = child.lastPathComponent
                guard (try? Self.validateID(id)) != nil,
                    try isManagedDirectory(child)
                else {
                    continue
                }
                if deferredRemoval {
                    inspections.append(
                        .init(
                            id: id,
                            rootURL: child,
                            location: .removal,
                            status: .deferredRemoval,
                        ),
                    )
                    continue
                }
                let markerURL = paths.ephemeralInitializationURL(for: child)
                guard FileManager.default.fileExists(atPath: markerURL.path) else {
                    inspections.append(
                        .init(
                            id: id,
                            rootURL: child,
                            location: .allocation,
                            status: .legacyIncomplete,
                        ),
                    )
                    continue
                }
                try validateInitializationMarker(markerURL, id: id)
                let metadata = initializationMetadata(at: markerURL, id: id)
                if let lease = try lockOperations.tryAcquireLease(markerURL) {
                    lease.finish(removingMarker: false)
                    inspections.append(
                        .init(
                            id: id,
                            rootURL: child,
                            location: .allocation,
                            status: .interruptedInitialization(metadata),
                        ),
                    )
                }
                else {
                    inspections.append(
                        .init(
                            id: id,
                            rootURL: child,
                            location: .allocation,
                            status: .initializing(metadata),
                        ),
                    )
                }
            }
        }
        return inspections
    }

    private func initializedWorkspace(
        id: String,
        state: OperationState,
    ) throws -> EphemeralWorkspace {
        let workspace = makeWorkspace(
            id: id,
            repositoryURL: URL(filePath: state.targetPath, directoryHint: .isDirectory),
        )
        try validateManagedPath(workspace)
        try validateMetadata(state, workspace: workspace)
        return workspace
    }

    private func retire(
        workspace: EphemeralWorkspace,
        snapshotURL: URL?,
    ) throws {
        try validateManagedPath(workspace)
        try ensureManagedDirectory(paths.ephemeralInternalURL)
        try ensureManagedDirectory(paths.ephemeralRemovalsURL)

        let parentURL = paths.ephemeralRemovalsURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory,
        )
        let rootURL = parentURL.appending(path: workspace.id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: false)
        do {
            try fileOperations.moveItem(workspace.rootURL, rootURL)
        }
        catch {
            try? fileOperations.removeItem(parentURL)
            throw URIError.fileSystem(
                "Could not isolate ephemeral workspace \(workspace.id) for removal: \(error)",
            )
        }

        workspace.initializationLease?.finish(removingMarker: false)
        let cleanup = EphemeralWorkspaceDeferredCleanup(
            rootURL: rootURL,
            parentURL: parentURL,
            snapshotURL: snapshotURL,
            paths: paths,
            fileOperations: fileOperations,
        )
        if !cleanup.perform() {
            cleanupRegistry.schedule(cleanup)
        }
    }

    private func ensureManagedDirectory(
        _ url: URL,
        includingIntermediates: Bool = false,
    ) throws {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                )
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw URIError.fileSystem(
                        "URI runtime path is not a managed directory: \(url.path)",
                    )
                }
                return
            }
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: includingIntermediates,
            )
        }
        catch let error as URIError {
            throw error
        }
        catch {
            throw URIError.fileSystem(
                "Could not create URI runtime directory at \(url.path): \(error)",
            )
        }
    }

    private func initializationData(
        _ metadata: EphemeralWorkspaceInitialization,
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(metadata)
        data.append(0x0A)
        return data
    }

    private func initializationMetadata(
        at url: URL,
        id: String,
    ) -> EphemeralWorkspaceInitialization? {
        guard let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(EphemeralWorkspaceInitialization.self, from: data),
            metadata.schemaVersion == EphemeralWorkspaceInitialization.currentSchemaVersion,
            metadata.id == id
        else {
            return nil
        }
        let target = URL(filePath: metadata.targetPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        let root = paths.ephemeralURL(id: id).standardizedFileURL.resolvingSymlinksInPath()
        guard target.deletingLastPathComponent().path == root.path else {
            return nil
        }
        return metadata
    }

    private func initializationTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private func validateInitializationMarker(
        _ url: URL,
        id: String,
    ) throws {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw URIError.unsafeEphemeral(
                "Ephemeral initialization marker is unsafe: \(id)",
            )
        }
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

    private func isManagedDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        )
        return values.isDirectory == true && values.isSymbolicLink != true
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
            name.caseInsensitiveCompare("state.json") != .orderedSame,
            name.caseInsensitiveCompare("initialization.json") != .orderedSame
        else {
            throw URIError.invalidArguments(
                "Upstream repository name cannot be used as an ephemeral directory: \(name)",
            )
        }
    }
}
