struct HelpRenderer {

    let terminal: Terminal

    func renderRoot() {
        terminal.output(terminal.styled("OVERVIEW", as: .bold, to: .standardOutput))
        terminal.output("  \(CommandCatalog.abstract)")
        terminal.output("")
        terminal.output(terminal.styled("USAGE", as: .bold, to: .standardOutput))
        terminal.output(
            "  \(syntaxRenderer.render(UsageRenderer().renderRoot(CommandCatalog.rootForm)))",
        )
        renderOptions(CommandCatalog.rootOptions)
        terminal.output("")
        terminal.output(terminal.styled("COMMANDS", as: .bold, to: .standardOutput))
        renderRows(
            CommandCatalog.commands.map({ ($0.name, $0.abstract) })
                + [("help", "Show help information for a command.")],
        )
        terminal.output("")
        terminal.output(
            "  Run '\(syntaxRenderer.render("uri help <command>"))' for detailed help.",
        )
    }

    func render(_ command: CommandDefinition) {
        terminal.output(terminal.styled("OVERVIEW", as: .bold, to: .standardOutput))
        terminal.output("  \(command.abstract)")
        terminal.output("")
        terminal.output(terminal.styled("USAGE", as: .bold, to: .standardOutput))
        for usage in UsageRenderer().render(command) {
            terminal.output("  \(syntaxRenderer.render(usage))")
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
        let rows = options.map({ ($0.synopsis, $0.help) })
        renderRows(rows)
    }

    private func renderRows(_ rows: [(String, String)]) {
        let width = rows.map({ $0.0.count }).max() ?? 0
        for (name, help) in rows {
            let padding = String(repeating: " ", count: max(2, width - name.count + 2))
            terminal.output("  \(syntaxRenderer.render(name))\(padding)\(help)")
        }
    }

    private var syntaxRenderer: CommandSyntaxRenderer {
        .init(terminal: terminal, stream: .standardOutput)
    }
}
