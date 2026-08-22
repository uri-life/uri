import Foundation
import Testing
import URI
import URIModel
import URIPatchset

@testable
import URICommand

@Suite("Diff Command")
struct DiffCommandTests {

    @Test
    func `changed effects render unified labels hunks additions and deletions with terminal colors`() async throws {
        let fixture = try DiffCommandFixture()
        defer { fixture.remove() }
        let capture = CommandOutputCapture()
        let command = Diff(
            values: [fixture.root.path],
            from: ["v1", "p1", "first"],
            to: ["v2", "p2", "second"],
            compare: { _, from, to in
                #expect(from.label == "v1 p1 first")
                #expect(to.label == "v2 p2 second")
                return """
                    --- v1 p1 first
                    +++ v2 p2 second
                    @@ -1 +1 @@
                    -old
                    +new
                     context

                    """
            },
        )

        try await command.run(terminal: capture.terminal(colorMode: .always))

        #expect(capture.standardError.isEmpty)
        #expect(capture.standardOutput.contains("\u{001B}[31m--- v1 p1 first\u{001B}[0m"))
        #expect(capture.standardOutput.contains("\u{001B}[32m+++ v2 p2 second\u{001B}[0m"))
        #expect(capture.standardOutput.contains("\u{001B}[36m@@ -1 +1 @@\u{001B}[0m"))
        #expect(capture.standardOutput.contains("\u{001B}[31m-old\u{001B}[0m"))
        #expect(capture.standardOutput.contains("\u{001B}[32m+new\u{001B}[0m"))
        #expect(capture.standardOutput.contains(" context\n"))
    }

    @Test
    func `identical effects produce no output`() async throws {
        let fixture = try DiffCommandFixture()
        defer { fixture.remove() }
        let capture = CommandOutputCapture()
        let command = Diff(
            values: [fixture.root.path],
            from: ["v1", "p1", "feature"],
            to: ["v2", "p2", "feature"],
            compare: { _, _, _ in "" },
        )

        try await command.run(terminal: capture.terminal(colorMode: .always))

        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError.isEmpty)
    }
}

private struct DiffCommandFixture {

    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "DiffCommandTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try PatchsetRepository(rootURL: root).initializeRoot(
            with: .init(upstream: "https://example.com/upstream.git"),
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
