import Foundation
import Testing

@testable import URI

@Suite("Operation Index")
struct OperationIndexTests {

    @Test
    func `registration writes one versioned atomic record and removal deletes it`() throws {
        let fixture = try OperationIndexFixture()
        defer { fixture.remove() }
        let target = try fixture.directory(named: "target")
        let store = OperationIndexStore(paths: fixture.paths)

        try store.register(targetURL: target)
        try store.register(targetURL: target)

        let entries = try store.entries()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.record.schemaVersion == OperationIndexRecord.currentSchemaVersion)
        #expect(entry.record.targetPath == target.path)
        #expect(entry.url.pathExtension == "json")
        #expect(String(decoding: try Data(contentsOf: entry.url), as: UTF8.self).hasSuffix("\n"))

        try store.remove(targetURL: target)
        #expect(try store.entries().isEmpty)
    }

    @Test
    func `list merges regular and ephemeral targets in path order without duplicates`() async throws {
        let fixture = try OperationIndexFixture()
        defer { fixture.remove() }
        let regularTarget = try fixture.repository(named: "z-target")
        let regularState = fixture.state(
            targetURL: regularTarget,
            mode: .expand,
            phase: .active,
            feature: "feature",
            featureOrder: ["base", "feature"],
        )
        try fixture.saveRegular(regularState, targetURL: regularTarget)
        let store = OperationIndexStore(paths: fixture.paths)
        try store.register(targetURL: regularTarget)
        try fixture.writeIndexRecord(
            OperationIndexRecord(targetPath: regularTarget.path),
            named: "duplicate.json",
        )

        let workspace = try EphemeralWorkspaceManager(paths: fixture.paths)
            .create(requestedID: "peach", repositoryName: "a-target")
        try fixture.initializeRepository(at: workspace.repositoryURL)
        let ephemeralState = fixture.state(
            targetURL: workspace.repositoryURL,
            mode: .apply,
            phase: .active,
            feature: nil,
            featureOrder: ["base", "feature"],
            ephemeralID: "peach",
        )
        try OperationStateStore().save(ephemeralState, to: workspace.stateURL)

        let listings = try await OperationIndex(paths: fixture.paths).list()

        #expect(listings.count == 2)
        #expect(listings.map(\.targetURL.path) == listings.map(\.targetURL.path).sorted())
        #expect(listings.contains(where: { $0.state.ephemeralID == "peach" }))
        #expect(listings.contains(where: {
            $0.targetURL.path == regularTarget.path && $0.state.feature == "feature"
        }))
    }

    @Test
    func `list hides stale malformed mismatched and symlink records without deleting them`() async throws {
        let fixture = try OperationIndexFixture()
        defer { fixture.remove() }
        let store = OperationIndexStore(paths: fixture.paths)
        let missingTarget = fixture.root.appending(path: "missing", directoryHint: .isDirectory)
        try store.register(targetURL: missingTarget)

        let mismatchedTarget = try fixture.repository(named: "mismatched")
        let mismatchedState = fixture.state(
            targetURL: fixture.root.appending(path: "other", directoryHint: .isDirectory),
            mode: .expand,
            phase: .active,
            feature: "feature",
            featureOrder: ["feature"],
        )
        try fixture.saveRegular(mismatchedState, targetURL: mismatchedTarget)
        try store.register(targetURL: mismatchedTarget)

        let malformedURL = fixture.paths.operationIndexURL.appending(path: "malformed.json")
        try Data("not json\n".utf8).write(to: malformedURL)
        let unsupportedURL = fixture.paths.operationIndexURL.appending(path: "unsupported.json")
        try Data(
            "{\"schemaVersion\":2,\"targetPath\":\"/unsupported\"}\n".utf8,
        ).write(to: unsupportedURL)
        let outsideURL = fixture.root.appending(path: "outside.json")
        try fixture.write(
            OperationIndexRecord(targetPath: missingTarget.path),
            to: outsideURL,
        )
        let symlinkURL = fixture.paths.operationIndexURL.appending(path: "symlink.json")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: outsideURL,
        )
        let corruptWorkspace = try EphemeralWorkspaceManager(paths: fixture.paths)
            .create(requestedID: "peach")
        try Data("not json\n".utf8).write(to: corruptWorkspace.stateURL)
        let indexedURLs = try FileManager.default.contentsOfDirectory(
            at: fixture.paths.operationIndexURL,
            includingPropertiesForKeys: nil,
        )

        #expect(try await OperationIndex(paths: fixture.paths).list().isEmpty)
        for url in indexedURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: outsideURL.path))
        #expect(FileManager.default.fileExists(atPath: corruptWorkspace.stateURL.path))
    }

    @Test
    func `list silently omits initializing and legacy incomplete ephemeral workspaces`() async throws {
        let fixture = try OperationIndexFixture()
        defer { fixture.remove() }
        let manager = EphemeralWorkspaceManager(paths: fixture.paths)
        let initializing = try manager.create(requestedID: "peach")
        try FileManager.default.createDirectory(
            at: fixture.paths.ephemeralURL(id: "plum"),
            withIntermediateDirectories: false,
        )

        #expect(try await OperationIndex(paths: fixture.paths).list().isEmpty)
        withExtendedLifetime(initializing) {}
    }

    @Test
    func `registration rejects an index root that is not a managed directory`() throws {
        let fixture = try OperationIndexFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.paths.rootURL,
            withIntermediateDirectories: true,
        )
        try Data().write(to: fixture.paths.operationIndexURL)

        #expect(throws: URIError.self) {
            try OperationIndexStore(paths: fixture.paths).register(
                targetURL: fixture.root.appending(path: "target", directoryHint: .isDirectory),
            )
        }
    }
}

private final class OperationIndexFixture {

    let root: URL

    let paths: RuntimePaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "OperationIndexTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        paths = RuntimePaths(homeURL: root.appending(path: "home", directoryHint: .isDirectory))
    }

    func directory(named name: String) throws -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func repository(named name: String) throws -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try initializeRepository(at: url)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    func initializeRepository(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try git(["-C", url.path, "init", "-q"])
    }

    func saveRegular(_ state: OperationState, targetURL: URL) throws {
        let stateURL = targetURL.appending(path: ".git/uri/state.json")
        try OperationStateStore().save(state, to: stateURL)
    }

    func state(
        targetURL: URL,
        mode: OperationState.Mode,
        phase: OperationState.Phase,
        feature: String?,
        featureOrder: [String],
        ephemeralID: String? = nil,
    ) -> OperationState {
        OperationState(
            mode: mode,
            phase: phase,
            source: .init(
                kind: .local,
                original: "/patches",
                localRootURL: URL(filePath: "/patches", directoryHint: .isDirectory),
            ),
            snapshotPath: nil,
            upstreamVersion: "v1",
            patchsetVersion: "p1",
            feature: feature,
            featureOrder: featureOrder,
            targetPath: targetURL.standardizedFileURL.resolvingSymlinksInPath().path,
            startCommit: String(repeating: "1", count: 40),
            startBranch: "main",
            baselineCommit: String(repeating: "2", count: 40),
            expectedCommit: String(repeating: "3", count: 40),
            branchPrefix: "uri",
            committerName: "URI",
            committerEmail: "uri@example.com",
            ephemeralID: ephemeralID,
        )
    }

    func writeIndexRecord(_ record: OperationIndexRecord, named name: String) throws {
        try write(record, to: paths.operationIndexURL.appending(path: name))
    }

    func write(_ record: OperationIndexRecord, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        try data.write(to: url)
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
