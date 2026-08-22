import Foundation
import Testing
import URI

@testable
import URICommand

@Suite("URI Command")
struct URICommandTests {

    @Test
    func `help version and completion succeed without coloring machine output`() async {
        let help = CommandOutputCapture()
        let helpCode = await URICommand.run(
            arguments: ["--help"],
            terminalFactory: { help.terminal(colorMode: $0) },
        )
        let version = CommandOutputCapture()
        let versionCode = await URICommand.run(
            arguments: ["--color", "always", "--version"],
            terminalFactory: { version.terminal(colorMode: $0) },
        )
        let completion = CommandOutputCapture()
        let completionCode = await URICommand.run(
            arguments: [
                "--color", "always", "--generate-completion-script", "bash",
            ],
            terminalFactory: { completion.terminal(colorMode: $0) },
        )

        #expect(helpCode == 0)
        #expect(help.standardOutput.contains("COMMANDS"))
        #expect(versionCode == 0)
        #expect(!version.standardOutput.contains("\u{001B}["))
        #expect(completionCode == 0)
        #expect(completion.standardOutput.contains("uri --_complete --"))
        #expect(!completion.standardOutput.contains("\u{001B}["))
    }

    @Test
    func `hidden completion action is plain fail soft and absent from help`() async {
        let success = CommandOutputCapture()
        let successCode = await URICommand.run(
            arguments: ["--_complete", "--", "ap"],
            terminalFactory: { _ in success.terminal(colorMode: .always) },
        )
        let malformed = CommandOutputCapture()
        let malformedCode = await URICommand.run(
            arguments: ["--_complete"],
            terminalFactory: { _ in malformed.terminal(colorMode: .always) },
        )
        let help = CommandOutputCapture()
        _ = await URICommand.run(
            arguments: ["--help"],
            terminalFactory: { help.terminal(colorMode: $0) },
        )

        #expect(successCode == 0)
        #expect(success.standardOutput.contains("candidate\tapply\t"))
        #expect(!success.standardOutput.contains("\u{001B}["))
        #expect(success.standardError.isEmpty)
        #expect(malformedCode == 0)
        #expect(malformed.standardOutput.isEmpty)
        #expect(malformed.standardError.isEmpty)
        #expect(!help.standardOutput.contains("--_complete"))
    }

    @Test
    func `unsupported completion shell is a usage error`() async {
        let capture = CommandOutputCapture()
        let code = await URICommand.run(
            arguments: ["--generate-completion-script", "powershell"],
            terminalFactory: { capture.terminal(colorMode: $0) },
        )

        #expect(code == 64)
        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError.contains("Invalid completion shell 'powershell'"))
        #expect(capture.standardError.contains("usage: uri"))
    }

    @Test
    func `help command prints command usage to standard output`() async {
        let capture = CommandOutputCapture()
        let code = await URICommand.run(
            arguments: ["help", "apply"],
            terminalFactory: { capture.terminal(colorMode: $0) },
        )

        #expect(code == 0)
        #expect(capture.standardOutput.contains("uri apply [SOURCE] VERSION PATCHSET"))
        #expect(capture.standardOutput.contains("--dev"))
        #expect(capture.standardOutput.contains("--continue"))
        #expect(capture.standardError.isEmpty)
    }

    @Test
    func `every command help and usage error render the same generated forms`() async {
        for command in CommandCatalog.commands {
            let expected = UsageRenderer().render(command)
            let help = CommandOutputCapture()
            let helpCode = await URICommand.run(
                arguments: ["help", command.name],
                terminalFactory: { help.terminal(colorMode: $0) },
            )
            let helpUsages = help.standardOutput.split(separator: "\n").compactMap({ line in
                line.hasPrefix("  uri \(command.name)")
                    ? String(line.dropFirst(2))
                    : nil
            })
            let failure = CommandOutputCapture()
            let failureCode = await URICommand.run(
                arguments: [command.name, "--unknown"],
                terminalFactory: { failure.terminal(colorMode: $0) },
            )
            let failureUsages = failure.standardError.split(separator: "\n").compactMap({ line in
                line.hasPrefix("usage: ")
                    ? String(line.dropFirst("usage: ".count))
                    : nil
            })

            #expect(helpCode == 0)
            #expect(helpUsages == expected)
            #expect(failureCode == 64)
            #expect(failureUsages == expected)
        }
    }

    @Test
    func `usage errors exit 64 with command usage on standard error`() async {
        let capture = CommandOutputCapture()
        let code = await URICommand.run(
            arguments: ["apply", "v1", "p1", "--ephemeral", "peach", "trailing"],
            terminalFactory: { capture.terminal(colorMode: $0) },
        )

        #expect(code == 64)
        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError.contains("error:"))
        #expect(capture.standardError.contains("usage: uri apply"))
    }

    @Test
    func `operational errors exit 1 without usage text`() async {
        let capture = CommandOutputCapture()
        let code = await URICommand.run(
            arguments: [
                "init",
                "/__uri_command_tests_missing__/patches",
                "--upstream",
                "https://example.com/project.git",
            ],
            terminalFactory: { capture.terminal(colorMode: $0) },
        )

        #expect(code == 1)
        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError.contains("error:"))
        #expect(!capture.standardError.contains("usage:"))
    }

    @Test
    func `command completion retries deferred ephemeral cleanup without output`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "URICommandDeferredCleanupTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let parentURL = root.appending(path: "removal", directoryHint: .isDirectory)
        let workspaceURL = parentURL.appending(path: "peach", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("remaining\n".utf8).write(to: workspaceURL.appending(path: "content"))
        let cleanupRegistry = EphemeralWorkspaceCleanupRegistry()
        cleanupRegistry.schedule(
            .init(
                rootURL: workspaceURL,
                parentURL: parentURL,
                snapshotURL: nil,
                paths: .init(homeURL: root.appending(path: "home")),
                fileOperations: .live,
            ),
        )
        let capture = CommandOutputCapture()

        let code = await URICommand.run(
            arguments: ["--version"],
            terminalFactory: { capture.terminal(colorMode: $0) },
            cleanupRegistry: cleanupRegistry,
        )

        #expect(code == 0)
        #expect(!capture.standardOutput.isEmpty)
        #expect(capture.standardError.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: parentURL.path))
        #expect(cleanupRegistry.pendingCount == 0)
    }

    @Test
    func `always colors diagnostics emitted for invalid commands`() async {
        let capture = CommandOutputCapture()
        let code = await URICommand.run(
            arguments: ["--color", "always", "unknown"],
            terminalFactory: { capture.terminal(colorMode: $0) },
        )

        #expect(code == 64)
        #expect(capture.standardError.contains("\u{001B}[31merror:\u{001B}[0m"))
    }
}
