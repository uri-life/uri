import Foundation
import Testing
import URIModel
@testable import URIPatchset

@Suite("Root Manifest Repository")
struct RootManifestRepositoryTests {

    @Test
    func `legacy root manifest keeps nil policy fields for workflow defaults`() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("upstream: https://example.com/project.git\n".utf8).write(
            to: root.appending(path: "manifest.yaml"),
        )

        let manifest = try PatchsetRepository(rootURL: root).rootManifest()
        #expect(manifest.upstream == "https://example.com/project.git")
        #expect(manifest.branchPrefix == nil)
        #expect(manifest.committer == nil)
    }

    @Test
    func `root initialization writes the branch-prefix wire key and explicit committer`() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try PatchsetRepository(rootURL: root)
        try repository.initializeRoot(
            with: .init(
                upstream: "https://example.com/project.git",
                branchPrefix: "custom",
                committer: .explicit(.init(name: "Patch Bot", email: "patch@example.com")),
            ),
        )

        let yaml = try String(contentsOf: root.appending(path: "manifest.yaml"), encoding: .utf8)
        #expect(yaml.contains("branch-prefix: \"custom\""))
        #expect(!yaml.contains("branchPrefix"))
        #expect(try repository.rootManifest().committer
            == .explicit(.init(name: "Patch Bot", email: "patch@example.com")))
    }

    @Test
    func `root schema rejects unknown keys and incomplete committers`() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifestURL = root.appending(path: "manifest.yaml")
        try Data("upstream: x\nunknown: true\n".utf8).write(to: manifestURL)
        #expect(throws: PatchsetError.self) {
            _ = try PatchsetRepository(rootURL: root).rootManifest()
        }
        try Data("upstream: x\ncommitter:\n  mode: explicit\n  name: Bot\n".utf8).write(
            to: manifestURL,
        )
        #expect(throws: PatchsetError.self) {
            _ = try PatchsetRepository(rootURL: root).rootManifest()
        }
    }

    @Test
    func `upstream and patchset removal delete only the selected hierarchy`() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try PatchsetRepository(rootURL: root)
        try repository.initializeRoot(with: .init(upstream: "https://example.com/project.git"))
        try repository.createUpstreamVersion("v1")
        try repository.createUpstreamVersion("v2")
        let p1 = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let p2 = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p2")
        try repository.createPatchset(p1)
        try repository.createPatchset(p2)

        try repository.removePatchset(p1)
        #expect(try repository.patchsets(in: "v1") == [p2])
        try repository.removeUpstreamVersion("v2")
        #expect(try repository.upstreamVersions() == ["v1"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "RootManifestRepositoryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
