import Foundation

struct HelpRenderer {

    let terminal: Terminal

    func renderRoot() {
        terminal.output(terminal.styled("OVERVIEW", as: .bold, to: .standardOutput))
        terminal.output("  \(CommandCatalog.abstract)")
        terminal.output("")
        terminal.output(terminal.styled("USAGE", as: .bold, to: .standardOutput))
        terminal.output(
            "  \(terminal.styled(UsageRenderer().renderRoot(CommandCatalog.rootForm), as: .cyan, to: .standardOutput))",
        )
        renderOptions(CommandCatalog.rootOptions)
        terminal.output("")
        terminal.output(terminal.styled("COMMANDS", as: .bold, to: .standardOutput))
        renderRows(
            CommandCatalog.commands.map({ ($0.name, $0.abstract) })
                + [("help", "Show help information for a command.")],
        )
        terminal.output("")
        terminal.output("  Run 'uri help <command>' for detailed help.")
    }

    func render(_ command: CommandDefinition) {
        terminal.output(terminal.styled("OVERVIEW", as: .bold, to: .standardOutput))
        terminal.output("  \(command.abstract)")
        terminal.output("")
        terminal.output(terminal.styled("USAGE", as: .bold, to: .standardOutput))
        for usage in UsageRenderer().render(command) {
            terminal.output(
                "  \(terminal.styled(usage, as: .cyan, to: .standardOutput))",
            )
        }
        if !command.arguments.isEmpty {
            terminal.output("")
            terminal.output(terminal.styled("ARGUMENTS", as: .bold, to: .standardOutput))
            renderRows(command.arguments.map({ ($0.id.rawValue, $0.help) }))
        }
        renderOptions(command.options + CommandCatalog.globalCommandOptions)
    }

    private func renderOptions(_ options: [OptionDefinition]) {
        terminal.output("")
        terminal.output(terminal.styled("OPTIONS", as: .bold, to: .standardOutput))
        let rows = options.map({ option in
            (
                terminal.styled(option.synopsis, as: .cyan, to: .standardOutput),
                option.help
            )
        })
        renderRows(rows)
    }

    private func renderRows(_ rows: [(String, String)]) {
        let width = rows.map({ plainLength($0.0) }).max() ?? 0
        for (name, help) in rows {
            let visibleName = plainLength(name)
            let padding = String(repeating: " ", count: max(2, width - visibleName + 2))
            terminal.output("  \(name)\(padding)\(help)")
        }
    }

    private func plainLength(_ value: String) -> Int {
        var result = value
        for style in [TerminalStyle.bold, .cyan, .green, .yellow, .red] {
            result = result.replacingOccurrences(of: "\u{001B}[\(style.rawValue)m", with: "")
        }
        result = result.replacingOccurrences(of: "\u{001B}[0m", with: "")
        return result.count
    }
}
