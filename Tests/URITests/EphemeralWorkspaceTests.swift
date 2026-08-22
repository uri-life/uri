import Foundation
import Testing
import URIModel
import URIPatchset

@testable import URI

@Suite("Ephemeral Workspace")
struct EphemeralWorkspaceTests {

    @Test
    func `apply workspace uses the upstream repository name, lists, rejects collapse, and vanishes when clean`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        let workflow = URIWorkflow(paths: paths)

        let result = try await workflow.apply(
            source: source,
            reference: reference,
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeral: .named("peach"),
        )
        #expect(result.ephemeralID == "peach")
        let manager = EphemeralWorkspaceManager(paths: paths)
        let listings = try manager.list()
        #expect(listings.map(\.id) == ["peach"])
        #expect(listings[0].state.mode == .apply)
        #expect(
            listings[0].path
                == paths.repositoryURL(id: "peach", repositoryName: "upstream").path,
        )
        #expect(result.targetURL.lastPathComponent == "upstream")
        #expect(
            !FileManager.default.fileExists(
                atPath: paths.ephemeralInitializationURL(
                    for: paths.ephemeralURL(id: "peach"),
                ).path,
            ),
        )
        let operationListings = try await OperationIndex(paths: paths).list()
        #expect(operationListings.count == 1)
        #expect(operationListings[0].state.ephemeralID == "peach")
        #expect(operationListings[0].targetURL.path == result.targetURL.path)
        #expect(!FileManager.default.fileExists(atPath: paths.operationIndexURL.path))

        await #expect(throws: URIError.self) {
            _ = try await workflow.collapse(
                targetURL: nil,
                currentDirectoryURL: fixture.root,
                ephemeralID: "peach",
                recursive: false,
                discard: true,
            )
        }
        try await manager.vanish(id: "peach", force: false)
        #expect(!FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "peach").path))
        #expect(try await OperationIndex(paths: paths).list().isEmpty)
    }

    @Test
    func `expand discard removes the completed ephemeral workspace`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        let workflow = URIWorkflow(paths: paths)
        _ = try await workflow.expand(
            source: source,
            reference: reference,
            featureID: "empty",
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeral: .named("plum"),
            includeDevelopmentDependencies: true,
            force: false,
        )
        let operationListings = try await OperationIndex(paths: paths).list()
        #expect(operationListings.count == 1)
        #expect(operationListings[0].state.ephemeralID == "plum")
        #expect(operationListings[0].state.mode == .expand)
        #expect(operationListings[0].state.phase == .active)
        #expect(!FileManager.default.fileExists(atPath: paths.operationIndexURL.path))

        _ = try await workflow.collapse(
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeralID: "plum",
            recursive: false,
            discard: true,
        )
        #expect(!FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "plum").path))
        #expect(try await OperationIndex(paths: paths).list().isEmpty)
    }

    @Test
    func `forced vanish bypasses dirty worktree checks but still uses managed metadata`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        _ = try await URIWorkflow(paths: paths).apply(
            source: source,
            reference: reference,
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeral: .named("grape"),
        )
        let repositoryURL = try EphemeralWorkspaceManager(paths: paths)
            .workspace(id: "grape").repositoryURL
        try Data("dirty\n".utf8).write(to: repositoryURL.appending(path: "untracked.txt"))
        let manager = EphemeralWorkspaceManager(paths: paths)

        await #expect(throws: URIError.self) {
            try await manager.vanish(id: "grape", force: false)
        }
        try await manager.vanish(id: "grape", force: true)
        #expect(!FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "grape").path))
    }

    @Test
    func `automatic IDs are valid and explicit collisions are rejected atomically`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralIDTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)

        let automatic = try manager.create(requestedID: nil)
        try EphemeralWorkspaceManager.validateID(automatic.id)
        #expect(automatic.rootURL.deletingLastPathComponent().path
            == paths.ephemeralRootURL.path)

        let named = try manager.create(requestedID: "peach")
        #expect(throws: URIError.self) {
            _ = try manager.create(requestedID: "peach")
        }
        #expect(throws: URIError.self) {
            _ = try manager.create(
                requestedID: "cedar",
                repositoryName: "initialization.json",
            )
        }
        try manager.removeUninitialized(automatic)
        try manager.removeUninitialized(named)
    }

    @Test
    func `creation publishes locked versioned initialization metadata before repository work`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralInitializationTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)

        let workspace = try manager.create(requestedID: "peach", repositoryName: "upstream")
        let markerURL = paths.ephemeralInitializationURL(for: workspace.rootURL)
        let metadata = try JSONDecoder().decode(
            EphemeralWorkspaceInitialization.self,
            from: Data(contentsOf: markerURL),
        )

        #expect(metadata.schemaVersion == EphemeralWorkspaceInitialization.currentSchemaVersion)
        #expect(metadata.id == "peach")
        #expect(metadata.targetPath == workspace.repositoryURL.path)
        #expect(!metadata.createdAt.isEmpty)
        let inspection = try #require(
            manager.inspections().first(where: {$0.id == "peach"}),
        )
        guard case .initializing(let inspectedMetadata) = inspection.status else {
            Issue.record("Expected an initializing workspace.")
            return
        }
        #expect(inspectedMetadata == metadata)

        try manager.removeUninitialized(workspace)
    }

    @Test
    func `interrupted and legacy incomplete workspaces stay hidden and require forced vanish`() async throws {
        let root = try temporaryDirectory(prefix: "EphemeralIncompleteTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)
        let interrupted = try manager.create(requestedID: "peach")
        interrupted.initializationLease?.finish(removingMarker: false)

        #expect(try manager.list().isEmpty)
        let interruptedInspection = try #require(
            manager.inspections().first(where: {$0.id == "peach"}),
        )
        guard case .interruptedInitialization = interruptedInspection.status else {
            Issue.record("Expected an interrupted initialization.")
            return
        }
        do {
            try await manager.vanish(id: "peach", force: false)
            Issue.record("Expected interrupted initialization to require --force.")
        }
        catch let error as URIError {
            #expect(error == .incompleteEphemeral("peach"))
        }
        try await manager.vanish(id: "peach", force: true)

        let legacyURL = paths.ephemeralURL(id: "plum")
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: false)
        #expect(try manager.list().isEmpty)
        let legacyInspection = try #require(
            manager.inspections().first(where: {$0.id == "plum"}),
        )
        #expect(legacyInspection.status == .legacyIncomplete)
        do {
            try await manager.vanish(id: "plum", force: false)
            Issue.record("Expected legacy incomplete workspace to require --force.")
        }
        catch let error as URIError {
            #expect(error == .incompleteEphemeral("plum"))
        }
        try await manager.vanish(id: "plum", force: true)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test
    func `forced vanish rejects a workspace whose initialization lock is held`() async throws {
        let root = try temporaryDirectory(prefix: "EphemeralActiveInitializationTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "peach")

        do {
            try await manager.vanish(id: "peach", force: true)
            Issue.record("Expected active initialization to reject forced vanish.")
        }
        catch let error as URIError {
            #expect(error == .ephemeralInitializing("peach"))
        }
        #expect(FileManager.default.fileExists(atPath: workspace.rootURL.path))

        try manager.removeUninitialized(workspace)
    }

    @Test
    func `hidden allocations and removals remain available to package diagnostics`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralInternalInspectionTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let allocationRoot = paths.ephemeralAllocationsURL
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "peach", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: allocationRoot, withIntermediateDirectories: true)
        let markerURL = paths.ephemeralInitializationURL(for: allocationRoot)
        let metadata = EphemeralWorkspaceInitialization(
            id: "peach",
            targetPath: paths.repositoryURL(id: "peach").path,
            createdAt: "2026-08-22T00:00:00Z",
        )
        var data = try JSONEncoder().encode(metadata)
        data.append(0x0A)
        let lease = try EphemeralWorkspaceLockOperations.live.createLease(
            markerURL,
            markerURL,
            data,
        )
        let manager = EphemeralWorkspaceManager(paths: paths)

        var inspection = try #require(
            manager.inspections().first(where: {$0.location == .allocation}),
        )
        guard case .initializing = inspection.status else {
            Issue.record("Expected a locked hidden allocation.")
            return
        }
        lease.finish(removingMarker: false)
        inspection = try #require(
            manager.inspections().first(where: {$0.location == .allocation}),
        )
        guard case .interruptedInitialization = inspection.status else {
            Issue.record("Expected an interrupted hidden allocation.")
            return
        }

        let removalRoot = paths.ephemeralRemovalsURL
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "plum", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: removalRoot, withIntermediateDirectories: true)
        let removal = try #require(
            manager.inspections().first(where: {$0.location == .removal}),
        )
        #expect(removal.id == "plum")
        #expect(removal.status == .deferredRemoval)
    }

    @Test
    func `failed recursive removal is deferred after the active ID disappears`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralDeferredRemovalTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let operations = ControlledFileOperations()
        let registry = EphemeralWorkspaceCleanupRegistry()
        let manager = EphemeralWorkspaceManager(
            paths: paths,
            fileOperations: operations.operations,
            cleanupRegistry: registry,
        )
        let workspace = try manager.create(requestedID: "peach")
        operations.failNextRemovals(2)

        try manager.removeUninitialized(workspace)

        #expect(!FileManager.default.fileExists(atPath: workspace.rootURL.path))
        #expect(registry.pendingCount == 1)
        #expect(
            try manager.inspections().contains(where: {
                $0.id == "peach" && $0.status == .deferredRemoval
            }),
        )

        registry.retry()
        #expect(registry.pendingCount == 1)
        #expect(
            try manager.inspections().contains(where: {
                $0.id == "peach" && $0.status == .deferredRemoval
            }),
        )
        registry.retry()
        #expect(registry.pendingCount == 0)
        #expect(
            try manager.inspections().allSatisfy({$0.status != .deferredRemoval}),
        )
    }

    @Test
    func `snapshot cleanup failure preserves the quarantined workspace for retry`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralSnapshotCleanupTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let snapshotURL = paths.operationCacheURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        try Data("snapshot\n".utf8).write(to: snapshotURL.appending(path: "content"))
        let parentURL = root.appending(path: "removal", directoryHint: .isDirectory)
        let workspaceURL = parentURL.appending(path: "peach", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("workspace\n".utf8).write(to: workspaceURL.appending(path: "content"))
        let operations = ControlledFileOperations()
        let cleanup = EphemeralWorkspaceDeferredCleanup(
            rootURL: workspaceURL,
            parentURL: parentURL,
            snapshotURL: snapshotURL,
            paths: paths,
            fileOperations: operations.operations,
        )
        operations.failNextRemovals(1)

        #expect(!cleanup.perform())
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(FileManager.default.fileExists(atPath: workspaceURL.path))

        #expect(cleanup.perform())
        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: parentURL.path))
    }

    @Test
    func `preparation reports the original error and a failed workspace isolation`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        let operations = ControlledFileOperations()
        operations.failNextRetirementMoves(1)
        let manager = EphemeralWorkspaceManager(
            paths: paths,
            fileOperations: operations.operations,
            cleanupRegistry: .init(),
        )
        let workflow = URIWorkflow(
            paths: paths,
            ephemeralManager: manager,
        )

        do {
            _ = try await workflow.expand(
                source: source,
                reference: reference,
                featureID: "missing",
                targetURL: nil,
                currentDirectoryURL: fixture.root,
                ephemeral: .named("peach"),
                includeDevelopmentDependencies: true,
                force: false,
            )
            Issue.record("Expected expansion preparation to fail.")
        }
        catch {
            #expect(String(describing: error).contains("Additionally, ephemeral workspace cleanup failed"))
        }

        #expect(FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "peach").path))
        #expect(!FileManager.default.fileExists(atPath: paths.ephemeralStateURL(id: "peach").path))
    }

    @Test
    func `failed isolation keeps an initialized workspace and its state intact`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        _ = try await URIWorkflow(paths: paths).apply(
            source: source,
            reference: reference,
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeral: .named("peach"),
        )
        let operations = ControlledFileOperations()
        operations.failNextMoves(1)
        let manager = EphemeralWorkspaceManager(
            paths: paths,
            fileOperations: operations.operations,
            cleanupRegistry: .init(),
        )
        let stateURL = paths.ephemeralStateURL(id: "peach")

        await #expect(throws: URIError.self) {
            try await manager.vanish(id: "peach", force: true)
        }

        #expect(FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "peach").path))
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
        #expect(try manager.list().map(\.id) == ["peach"])
    }

    @Test
    func `clean workspace at a different HEAD requires forced vanish`() async throws {
        let fixture = try EphemeralFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        _ = try await URIWorkflow(paths: paths).apply(
            source: source,
            reference: reference,
            targetURL: nil,
            currentDirectoryURL: fixture.root,
            ephemeral: .named("cedar"),
        )
        let repositoryURL = try EphemeralWorkspaceManager(paths: paths)
            .workspace(id: "cedar").repositoryURL
        try Data("moved\n".utf8).write(to: repositoryURL.appending(path: "moved.txt"))
        _ = try fixture.git(["-C", repositoryURL.path, "add", "moved.txt"])
        _ = try fixture.git([
            "-C", repositoryURL.path, "-c", "user.name=Editor", "-c",
            "user.email=e@example.com", "commit", "-q", "-m", "Move HEAD",
        ])
        let manager = EphemeralWorkspaceManager(paths: paths)

        await #expect(throws: URIError.self) {
            try await manager.vanish(id: "cedar", force: false)
        }
        try await manager.vanish(id: "cedar", force: true)
        #expect(!FileManager.default.fileExists(atPath: paths.ephemeralURL(id: "cedar").path))
    }

    @Test
    func `symlink workspace is rejected even before force checks`() async throws {
        let root = try temporaryDirectory(prefix: "EphemeralSymlinkTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        try FileManager.default.createDirectory(
            at: paths.ephemeralRootURL,
            withIntermediateDirectories: true,
        )
        let outside = root.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: paths.ephemeralURL(id: "peach"),
            withDestinationURL: outside,
        )

        #expect(throws: URIError.self) {
            _ = try EphemeralWorkspaceManager(paths: paths).workspace(id: "peach")
        }
        await #expect(throws: URIError.self) {
            try await EphemeralWorkspaceManager(paths: paths).vanish(id: "peach", force: true)
        }

        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "plum")
        let outsideState = outside.appending(path: "state.json")
        try Data("{}\n".utf8).write(to: outsideState)
        try FileManager.default.createSymbolicLink(
            at: workspace.stateURL,
            withDestinationURL: outsideState,
        )
        #expect(throws: URIError.self) {
            _ = try manager.workspace(id: "plum")
        }
    }

    @Test
    func `metadata path mismatch is rejected before repository change checks`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralMetadataTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "peach")
        let state = OperationState(
            mode: .apply,
            phase: .active,
            source: .init(kind: .local, original: "/patches", localRootURL: URL(filePath: "/patches")),
            snapshotPath: nil,
            upstreamVersion: "v1",
            patchsetVersion: "p1",
            feature: nil,
            featureOrder: [],
            targetPath: "/outside/repository",
            startCommit: String(repeating: "1", count: 40),
            startBranch: nil,
            baselineCommit: String(repeating: "1", count: 40),
            branchPrefix: "uri",
            committerName: "URI",
            committerEmail: "uri@uri.life",
            ephemeralID: "peach",
        )
        try OperationStateStore().save(state, to: workspace.stateURL)

        #expect(throws: URIError.self) {
            _ = try manager.list()
        }
    }

    @Test
    func `corrupted metadata is rejected instead of being skipped`() throws {
        let root = try temporaryDirectory(prefix: "EphemeralCorruptStateTests")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "peach")
        try Data("not json\n".utf8).write(to: workspace.stateURL)

        #expect(throws: URIError.self) {
            _ = try manager.list()
        }
        #expect(FileManager.default.fileExists(atPath: workspace.rootURL.path))
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private final class ControlledFileOperations: @unchecked Sendable {

    private enum Failure: Error {

        case requested
    }

    private let lock = NSLock()

    private var moveFailures = 0

    private var retirementMoveFailures = 0

    private var removalFailures = 0

    var operations: EphemeralWorkspaceFileOperations {
        .init(
            moveItem: { [self] source, destination in
                if consumeRetirementMoveFailure(source: source) {
                    throw Failure.requested
                }
                if consumeMoveFailure() {
                    throw Failure.requested
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { [self] url in
                if consumeRemovalFailure() {
                    throw Failure.requested
                }
                try FileManager.default.removeItem(at: url)
            },
        )
    }

    func failNextMoves(_ count: Int) {
        lock.lock()
        moveFailures = count
        lock.unlock()
    }

    func failNextRetirementMoves(_ count: Int) {
        lock.lock()
        retirementMoveFailures = count
        lock.unlock()
    }

    func failNextRemovals(_ count: Int) {
        lock.lock()
        removalFailures = count
        lock.unlock()
    }

    private func consumeMoveFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard moveFailures > 0 else {
            return false
        }
        moveFailures -= 1
        return true
    }

    private func consumeRetirementMoveFailure(source: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard retirementMoveFailures > 0,
            !source.path.contains("/.internal/allocations/")
        else {
            return false
        }
        retirementMoveFailures -= 1
        return true
    }

    private func consumeRemovalFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard removalFailures > 0 else {
            return false
        }
        removalFailures -= 1
        return true
    }
}

private final class EphemeralFixture {

    let root: URL
    let home: URL
    let upstream: URL
    let patchset: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "EphemeralWorkspaceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        home = root.appending(path: "home", directoryHint: .isDirectory)
        upstream = root.appending(path: "upstream", directoryHint: .isDirectory)
        patchset = root.appending(path: "patchset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: patchset, withIntermediateDirectories: true)
    }

    func prepare() throws {
        _ = try git(["-C", upstream.path, "init", "-q"])
        try Data("base\n".utf8).write(to: upstream.appending(path: "content.txt"))
        _ = try git(["-C", upstream.path, "add", "content.txt"])
        _ = try git([
            "-C", upstream.path, "-c", "user.name=Upstream", "-c", "user.email=u@example.com",
            "commit", "-q", "-m", "Base",
        ])
        _ = try git(["-C", upstream.path, "-c", "tag.gpgSign=false", "tag", "v1"])

        let repository = try PatchsetRepository(rootURL: patchset)
        try repository.initializeRoot(
            with: .init(
                upstream: upstream.path,
                branchPrefix: "uri",
                committer: .explicit(.init(name: "URI", email: "uri@example.com")),
            ),
        )
        try repository.createUpstreamVersion("v1")
        let reference = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "empty"), to: reference)
    }

    func git(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
            ],
            uniquingKeysWith: { _, override in override },
        )
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw URIError.fileSystem(
                "test git command failed: \(String(decoding: errorData, as: UTF8.self))",
            )
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
