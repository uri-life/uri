import Foundation
import Testing

@testable
import URIGit

@Suite("Git Diff")
struct GitDiffTests {

    @Test
    func `repository diff preserves executable mode and binary patch data`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()
        let base = try await repository.currentCommit()
        try fixture.write(Data([0, 1, 2, 0, 255]), to: "asset.bin")
        try fixture.write("#!/bin/sh\nexit 0\n", to: "script.sh")
        try fixture.git(["add", "asset.bin", "script.sh"])
        try fixture.git(["update-index", "--chmod=+x", "script.sh"])
        try fixture.git(["commit", "-m", "add binary and executable"])
        let head = try await repository.currentCommit()

        let data = try await repository.diff(
            from: .init(base),
            to: .init(head),
        )
        let output = String(decoding: data, as: UTF8.self)

        #expect(output.contains("GIT binary patch"))
        #expect(output.contains("new file mode 100755"))
        #expect(output.contains("@@ -0,0 +1,2 @@"))
    }

    @Test
    func `file diff returns empty data for equality and unified output for a change`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "GitDiffTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.patch")
        let second = directory.appending(path: "second.patch")
        try Data("same\n".utf8).write(to: first)
        try Data("same\n".utf8).write(to: second)
        let git = Git()

        #expect(try await git.diffFiles(first, second).isEmpty)

        try Data("changed\n".utf8).write(to: second)
        let output = String(decoding: try await git.diffFiles(first, second), as: UTF8.self)
        #expect(output.contains("--- a/"))
        #expect(output.contains("+++ b/"))
        #expect(output.contains("-same"))
        #expect(output.contains("+changed"))
    }
}
