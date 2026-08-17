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
        let command = List(mode: .ephemeral, ephemeralListings: { [] })

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
            mode: .ephemeral,
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
}
