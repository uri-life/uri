import Foundation
import Testing

@testable
import URICommand

@Suite("Help Rendering")
struct HelpRenderingTests {

    @Test
    func `always colors commands options and placeholders in root and command help`() async {
        let root = CommandOutputCapture()
        let rootCode = await URICommand.run(
            arguments: ["--color", "always", "--help"],
            terminalFactory: { root.terminal(colorMode: $0) },
        )
        let apply = CommandOutputCapture()
        let applyCode = await URICommand.run(
            arguments: ["--color", "always", "help", "apply"],
            terminalFactory: { apply.terminal(colorMode: $0) },
        )

        #expect(rootCode == 0)
        #expect(
            root.standardOutput.contains(
                "\u{001B}[1muri\u{001B}[0m [\u{001B}[36m--color\u{001B}[0m <\u{001B}[33mwhen\u{001B}[0m>] <\u{001B}[33mcommand\u{001B}[0m>",
            ),
        )
        #expect(
            root.standardOutput.contains(
                "\u{001B}[32minit\u{001B}[0m      Initialize a patchset root",
            ),
        )
        #expect(
            root.standardOutput.contains(
                "\u{001B}[36m-h\u{001B}[0m, \u{001B}[36m--help\u{001B}[0m",
            ),
        )
        #expect(root.standardOutput.contains("for detailed help."))
        #expect(applyCode == 0)
        #expect(
            apply.standardOutput.contains(
                "\u{001B}[1muri\u{001B}[0m \u{001B}[32mapply\u{001B}[0m [\u{001B}[33mSOURCE\u{001B}[0m] \u{001B}[33mVERSION\u{001B}[0m \u{001B}[33mPATCHSET\u{001B}[0m [\u{001B}[33mTARGET\u{001B}[0m]",
            ),
        )
        #expect(
            apply.standardOutput.contains(
                "\u{001B}[33mSOURCE\u{001B}[0m    An explicit local path",
            ),
        )
    }

    @Test
    func `always colors root and command usage syntax on standard error`() async {
        let command = CommandOutputCapture()
        let commandCode = await URICommand.run(
            arguments: ["--color", "always", "apply", "v1", "p1", "--unknown"],
            terminalFactory: { command.terminal(colorMode: $0) },
        )
        let root = CommandOutputCapture()
        let rootCode = await URICommand.run(
            arguments: ["--color", "always", "unknown"],
            terminalFactory: { root.terminal(colorMode: $0) },
        )

        #expect(commandCode == 64)
        #expect(command.standardOutput.isEmpty)
        #expect(command.standardError.contains("\u{001B}[31merror:\u{001B}[0m"))
        #expect(
            command.standardError.contains(
                "\u{001B}[1musage:\u{001B}[0m \u{001B}[1muri\u{001B}[0m \u{001B}[32mapply\u{001B}[0m [\u{001B}[33mSOURCE\u{001B}[0m]",
            ),
        )
        #expect(
            command.standardError.contains(
                "Run '\u{001B}[1muri\u{001B}[0m \u{001B}[32mhelp\u{001B}[0m \u{001B}[32mapply\u{001B}[0m' for more information.",
            ),
        )
        #expect(rootCode == 64)
        #expect(root.standardOutput.isEmpty)
        #expect(
            root.standardError.contains(
                "\u{001B}[1musage:\u{001B}[0m \u{001B}[1muri\u{001B}[0m [\u{001B}[36m--color\u{001B}[0m <\u{001B}[33mwhen\u{001B}[0m>] <\u{001B}[33mcommand\u{001B}[0m>",
            ),
        )
        #expect(
            root.standardError.contains(
                "Run '\u{001B}[1muri\u{001B}[0m \u{001B}[36m--help\u{001B}[0m' for more information.",
            ),
        )
    }

    @Test
    func `never preserves help text and column alignment`() async {
        let colored = CommandOutputCapture()
        let coloredCode = await URICommand.run(
            arguments: ["--color", "always", "--help"],
            terminalFactory: { colored.terminal(colorMode: $0) },
        )
        let plain = CommandOutputCapture()
        let plainCode = await URICommand.run(
            arguments: ["--color", "never", "--help"],
            terminalFactory: { plain.terminal(colorMode: $0) },
        )

        #expect(coloredCode == 0)
        #expect(plainCode == 0)
        #expect(strippingANSI(from: colored.standardOutput) == plain.standardOutput)
        #expect(
            plain.standardOutput.contains(
                "  --color <when>                        Colorize human-facing output",
            ),
        )
        #expect(
            plain.standardOutput.contains(
                "  init      Initialize a patchset root or add an upstream version.",
            ),
        )
    }

    private func strippingANSI(from value: String) -> String {
        var result = value
        for style in [TerminalStyle.bold, .cyan, .green, .yellow, .red] {
            result = result.replacingOccurrences(
                of: "\u{001B}[\(style.rawValue)m",
                with: "",
            )
        }
        return result.replacingOccurrences(of: "\u{001B}[0m", with: "")
    }
}
