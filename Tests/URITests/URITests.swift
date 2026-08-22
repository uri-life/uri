import Foundation
import Testing

@testable import URI

@Suite("URI Source And State")
struct URITests {

    @Test
    func `source syntax distinguishes static HTTP explicit Git and local paths`() throws {
        #expect(PatchsetSourceLocator.recognizesExplicitSource("https://example.com/patches"))
        #expect(PatchsetSourceLocator.recognizesExplicitSource("git+https://example.com/patches.git"))
        #expect(PatchsetSourceLocator.recognizesExplicitSource("git@example.com:patches.git"))
        for value in [".", "~", "/", "nested/path", "path/", "../patches"] {
            #expect(PatchsetSourceLocator.recognizesExplicitSource(value))
        }
        #expect(!PatchsetSourceLocator.recognizesExplicitSource("v4.5.0"))

        let http = try PatchsetSourceLocator.locate(
            "https://example.com/patches/",
            currentDirectoryURL: URL(filePath: "/tmp"),
        )
        let git = try PatchsetSourceLocator.locate(
            "git+https://example.com/patches.git",
            currentDirectoryURL: URL(filePath: "/tmp"),
        )
        #expect(http.kind == .http)
        #expect(http.original == "https://example.com/patches")
        #expect(git.kind == .git)
        #expect(try PatchsetSourceLocator.gitRemote(from: git) == "https://example.com/patches.git")
    }

    @Test
    func `local discovery skips a patchset manifest and finds the root manifest`() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("upstream: https://example.com/project.git\n".utf8).write(
            to: root.appending(path: "manifest.yaml"),
        )
        let nested = root.appending(path: "versions/v1/patches/p1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("features: {}\n".utf8).write(to: nested.appending(path: "manifest.yaml"))

        for (source, currentDirectoryURL) in [
            (".", nested),
            ("versions/v1/patches/p1", root),
            ("versions/", root),
        ] {
            let located = try PatchsetSourceLocator.locate(
                source,
                currentDirectoryURL: currentDirectoryURL,
            )
            #expect(located.localRootURL == root)
        }
        #expect(try PatchsetSourceLocator.discoverLocalRoot(from: nested) == root)
    }

    @Test
    func `operation state round trips every recovery field with a versioned schema`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "state.json")
        let state = OperationState(
            mode: .expand,
            phase: .post,
            source: .init(kind: .git, original: "git+https://example.com/p.git"),
            snapshotPath: "/tmp/snapshot",
            upstreamVersion: "v1",
            patchsetVersion: "p1",
            feature: "feature",
            featureOrder: ["base", "feature"],
            currentIndex: 1,
            targetPath: "/tmp/target",
            startCommit: String(repeating: "1", count: 40),
            startBranch: "main",
            baselineCommit: String(repeating: "2", count: 40),
            expectedCommit: String(repeating: "3", count: 40),
            branchPrefix: "uri",
            committerName: "URI",
            committerEmail: "uri@uri.life",
            ephemeralID: "peach",
        )

        let store = OperationStateStore()
        try store.save(state, to: url)
        #expect(try store.load(from: url) == state)
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self).hasSuffix("\n"))
    }

    @Test
    func `ephemeral IDs enforce the portable identifier grammar`() {
        for valid in ["a", "_private", "peach-2", "A_B"] {
            #expect(throws: Never.self) {
                try EphemeralWorkspaceManager.validateID(valid)
            }
        }
        for invalid in ["", "2peach", "-peach", "peach/apple", "peach apple", "é"] {
            #expect(throws: URIError.self) {
                try EphemeralWorkspaceManager.validateID(invalid)
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "URITests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
