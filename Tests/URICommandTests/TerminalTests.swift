import Testing

@testable
import URICommand

@Suite("Terminal Output")
struct TerminalTests {

    @Test
    func `auto colors each TTY stream independently`() {
        let capture = CommandOutputCapture()
        let terminal = capture.terminal(
            colorMode: .auto,
            environment: ["TERM": "xterm-256color"],
            standardOutputIsTTY: false,
            standardErrorIsTTY: true,
        )

        #expect(terminal.styled("success", as: .green, to: .standardOutput) == "success")
        #expect(
            terminal.styled("error", as: .red, to: .standardError)
                == "\u{001B}[31merror\u{001B}[0m",
        )
    }

    @Test
    func `auto disables color for NO_COLOR and dumb terminals`() {
        let noColor = CommandOutputCapture().terminal(
            colorMode: .auto,
            environment: ["NO_COLOR": "", "TERM": "xterm"],
            standardOutputIsTTY: true,
        )
        let dumb = CommandOutputCapture().terminal(
            colorMode: .auto,
            environment: ["TERM": "dumb"],
            standardOutputIsTTY: true,
        )

        #expect(noColor.styled("value", as: .cyan, to: .standardOutput) == "value")
        #expect(dumb.styled("value", as: .cyan, to: .standardOutput) == "value")
    }

    @Test
    func `explicit always and never override environment and TTY detection`() {
        let always = CommandOutputCapture().terminal(
            colorMode: .always,
            environment: ["NO_COLOR": "", "TERM": "dumb"],
        )
        let never = CommandOutputCapture().terminal(
            colorMode: .never,
            environment: ["TERM": "xterm"],
            standardOutputIsTTY: true,
        )

        #expect(
            always.styled("value", as: .bold, to: .standardOutput)
                == "\u{001B}[1mvalue\u{001B}[0m",
        )
        #expect(never.styled("value", as: .bold, to: .standardOutput) == "value")
    }

    @Test
    func `machine readable output strips ANSI escapes even with always`() {
        let capture = CommandOutputCapture()
        let terminal = capture.terminal(colorMode: .always)
        let styled = terminal.styled("value", as: .green, to: .standardOutput)

        terminal.output(styled, machineReadable: true)

        #expect(capture.standardOutput == "value\n")
    }

    @Test
    func `prompt uses colored standard error and injected input`() {
        let capture = CommandOutputCapture()
        capture.input = "yes"
        let terminal = capture.terminal(
            colorMode: .always,
            standardInputIsTTY: true,
        )

        let answer = terminal.prompt("Continue? ")

        #expect(answer == "yes")
        #expect(capture.standardOutput.isEmpty)
        #expect(capture.standardError == "\u{001B}[33mContinue? \u{001B}[0m")
    }
}
