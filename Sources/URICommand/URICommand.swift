import URI

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct URICommand {

    static func main() async {
        let result = await run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            terminalFactory: Terminal.standard(colorMode:),
        )
        if result != 0 {
            exit(result)
        }
    }

    static func run(
        arguments: [String],
        terminalFactory: (ColorMode) -> Terminal,
    ) async -> Int32 {
        if arguments.first == "--_complete" {
            let terminal = terminalFactory(.never)
            guard arguments.dropFirst().first == "--" else {
                return 0
            }
            for record in CompletionEngine().complete(Array(arguments.dropFirst(2))) {
                terminal.output(record.encoded, machineReadable: true)
            }
            return 0
        }

        let parser = CommandParser()
        let fallbackColorMode = parser.preferredColorMode(in: arguments)
        do {
            let invocation = try parser.parse(arguments)
            let terminal = terminalFactory(invocation.colorMode)
            switch invocation.action {
            case .help(let command):
                let renderer = HelpRenderer(terminal: terminal)
                if let command {
                    renderer.render(command)
                }
                else {
                    renderer.renderRoot()
                }
            case .version:
                terminal.output(Versions.current, machineReadable: true)
            case .completion(let shell):
                terminal.output(
                    CompletionGenerator().script(for: shell),
                    terminator: "",
                    machineReadable: true,
                )
            case .run(let command):
                try await command.run(terminal: terminal)
            }
            return 0
        }
        catch let error as CommandUsageError {
            let terminal = terminalFactory(fallbackColorMode)
            terminal.diagnostic(error.description)
            renderUsage(
                commandName: error.commandName ?? parser.commandName(in: arguments),
                terminal: terminal,
            )
            return 64
        }
        catch URIError.invalidArguments(let message) {
            let terminal = terminalFactory(fallbackColorMode)
            terminal.diagnostic(message)
            renderUsage(
                commandName: parser.commandName(in: arguments),
                terminal: terminal,
            )
            return 64
        }
        catch {
            let terminal = terminalFactory(fallbackColorMode)
            terminal.diagnostic(String(describing: error))
            return 1
        }
    }

    private static func renderUsage(
        commandName: String?,
        terminal: Terminal,
    ) {
        let label = terminal.styled("usage:", as: .bold, to: .standardError)
        if let commandName, let command = CommandCatalog.command(named: commandName) {
            for usage in UsageRenderer().render(command) {
                terminal.errorOutput(
                    "\(label) \(terminal.styled(usage, as: .cyan, to: .standardError))",
                )
            }
            terminal.errorOutput("Run 'uri help \(commandName)' for more information.")
        }
        else {
            terminal.errorOutput(
                "\(label) \(terminal.styled(UsageRenderer().renderRoot(CommandCatalog.rootForm), as: .cyan, to: .standardError))",
            )
            terminal.errorOutput("Run 'uri --help' for more information.")
        }
    }
}
