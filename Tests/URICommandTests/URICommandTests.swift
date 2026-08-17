import Testing

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
        #expect(completion.standardOutput.contains("complete -F _uri uri"))
        #expect(!completion.standardOutput.contains("\u{001B}["))
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
        #expect(capture.standardOutput.contains("--continue"))
        #expect(capture.standardError.isEmpty)
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
