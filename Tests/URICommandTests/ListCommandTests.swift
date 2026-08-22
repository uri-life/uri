import Foundation
import Testing
import URI

@testable
import URICommand

@Suite("List Command")
struct ListCommandTests {

    @Test
    func `empty ephemeral mode prints no table`() async throws {
        let capture = CommandOutputCapture()
        let command = List(mode: .ephemeral(source: nil), ephemeralListings: { [] })

        try await command.run(terminal: capture.terminal(colorMode: .never))

        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError.isEmpty)
    }

    @Test
    func `ephemeral mode prints the complete workspace table`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ListCommandTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RuntimePaths(homeURL: root.appending(path: "home"))
        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "peach")
        try FileManager.default.createDirectory(
            at: workspace.repositoryURL,
            withIntermediateDirectories: true,
        )
        let state = OperationState(
            mode: .expand,
            phase: .active,
            source: .init(
                kind: .local,
                original: "/patches",
                localRootURL: URL(filePath: "/patches"),
            ),
            snapshotPath: nil,
            upstreamVersion: "v1",
            patchsetVersion: "p1",
            feature: "feature-a",
            featureOrder: ["feature-a"],
            targetPath: workspace.repositoryURL.path,
            startCommit: String(repeating: "1", count: 40),
            startBranch: nil,
            baselineCommit: String(repeating: "1", count: 40),
            branchPrefix: "uri",
            committerName: "URI",
            committerEmail: "uri@uri.life",
            ephemeralID: "peach",
        )
        try OperationStateStore().save(state, to: workspace.stateURL)
        let capture = CommandOutputCapture()
        let command = List(
            mode: .ephemeral(source: nil),
            ephemeralListings: { try manager.list() },
        )

        try await command.run(terminal: capture.terminal(colorMode: .always))

        #expect(
            capture.standardOutput == """
                ID\tMODE\tVERSION\tPATCHSET\tFEATURE\tSOURCE\tPATH
                peach\texpand\tv1\tp1\tfeature-a\t/patches\t\(workspace.repositoryURL.path)
                """ + "\n",
        )
        #expect(!capture.standardOutput.contains("\u{001B}["))
    }

    @Test
    func `local SOURCE resolves dot and slash-bearing paths to one patchset root`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ListCommandLocalSourceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let selectedRoot = root.appending(path: "selected", directoryHint: .isDirectory)
        let selectedChild = selectedRoot.appending(path: "versions", directoryHint: .isDirectory)
        let otherRoot = root.appending(path: "other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: selectedChild,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: otherRoot,
            withIntermediateDirectories: true,
        )
        for patchsetRoot in [selectedRoot, otherRoot] {
            try Data("upstream: https://example.com/upstream.git\n".utf8).write(
                to: patchsetRoot.appending(path: "manifest.yaml"),
            )
        }
        let manager = EphemeralWorkspaceManager(
            paths: .init(homeURL: root.appending(path: "home")),
        )
        try saveWorkspace(
            source: .init(
                kind: .local,
                original: "./recorded-selected",
                localRootURL: selectedRoot,
            ),
            id: "peach",
            manager: manager,
        )
        try saveWorkspace(
            source: .init(
                kind: .local,
                original: otherRoot.path,
                localRootURL: otherRoot,
            ),
            id: "plum",
            manager: manager,
        )
        let sourceValues = [
            ".",
            "./versions",
            "../selected",
            selectedChild.path,
        ]
        for sourceValue in sourceValues {
            let capture = CommandOutputCapture()
            let command = List(
                mode: .ephemeral(source: sourceValue),
                currentDirectoryURL: selectedRoot,
                ephemeralListings: { try manager.list() },
            )

            try await command.run(terminal: capture.terminal(colorMode: .never))

            #expect(capture.standardOutput.contains("\npeach\t"))
            #expect(!capture.standardOutput.contains("\nplum\t"))
            #expect(capture.standardOutput.contains("\t./recorded-selected\t"))
        }
    }

    @Test
    func `remote SOURCE normalizes HTTP roots and matches Git spellings exactly`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ListCommandRemoteSourceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = EphemeralWorkspaceManager(
            paths: .init(homeURL: root.appending(path: "home")),
        )
        try saveWorkspace(
            source: .init(
                kind: .http,
                original: "https://example.com/patches",
            ),
            id: "peach",
            manager: manager,
        )
        try saveWorkspace(
            source: .init(
                kind: .git,
                original: "git+https://example.com/patches.git",
            ),
            id: "plum",
            manager: manager,
        )
        let httpCapture = CommandOutputCapture()
        let httpCommand = List(
            mode: .ephemeral(source: "https://example.com/patches/"),
            ephemeralListings: { try manager.list() },
        )
        let gitCapture = CommandOutputCapture()
        let gitCommand = List(
            mode: .ephemeral(source: "git+https://example.com/patches.git"),
            ephemeralListings: { try manager.list() },
        )
        let alternateGitCapture = CommandOutputCapture()
        let alternateGitCommand = List(
            mode: .ephemeral(source: "git+ssh://git@example.com/patches.git"),
            ephemeralListings: { try manager.list() },
        )

        try await httpCommand.run(terminal: httpCapture.terminal(colorMode: .never))
        try await gitCommand.run(terminal: gitCapture.terminal(colorMode: .never))
        try await alternateGitCommand.run(
            terminal: alternateGitCapture.terminal(colorMode: .never),
        )

        #expect(httpCapture.standardOutput.contains("\npeach\t"))
        #expect(!httpCapture.standardOutput.contains("\nplum\t"))
        #expect(gitCapture.standardOutput.contains("\nplum\t"))
        #expect(!gitCapture.standardOutput.contains("\npeach\t"))
        #expect(alternateGitCapture.standardOutput.isEmpty)
    }

    private func saveWorkspace(
        source: PatchsetSource,
        id: String,
        manager: EphemeralWorkspaceManager,
    ) throws {
        let workspace = try manager.create(requestedID: id)
        try FileManager.default.createDirectory(
            at: workspace.repositoryURL,
            withIntermediateDirectories: true,
        )
        try OperationStateStore().save(
            state(
                source: source,
                id: id,
                targetPath: workspace.repositoryURL.path,
            ),
            to: workspace.stateURL,
        )
    }

    private func state(
        source: PatchsetSource,
        id: String,
        targetPath: String,
    ) -> OperationState {
        .init(
            mode: .expand,
            phase: .active,
            source: source,
            snapshotPath: nil,
            upstreamVersion: "v1",
            patchsetVersion: "p1",
            feature: "feature-a",
            featureOrder: ["feature-a"],
            targetPath: targetPath,
            startCommit: String(repeating: "1", count: 40),
            startBranch: nil,
            baselineCommit: String(repeating: "1", count: 40),
            branchPrefix: "uri",
            committerName: "URI",
            committerEmail: "uri@uri.life",
            ephemeralID: id,
        )
    }
}
