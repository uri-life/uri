import Foundation

enum CompletionShell: String, CaseIterable, Sendable {

    case bash

    case zsh

    case fish
}

struct CompletionGenerator {

    func script(for shell: CompletionShell) -> String {
        switch shell {
        case .bash:
            return bashScript()
        case .zsh:
            return zshScript()
        case .fish:
            return fishScript()
        }
    }

    private func bashScript() -> String {
        let commands = (CommandCatalog.commands.map(\.name) + ["help"]).joined(separator: " ")
        let cases = CommandCatalog.commands.map({ command in
            let options = optionTokens(command.options + CommandCatalog.globalCommandOptions)
            return "        \(command.name)) candidates=\(shellQuote(options)) ;;"
        }).joined(separator: "\n")
        return """
        _uri() {
            local cur prev command word candidates
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"

            case "$prev" in
                --color) COMPREPLY=($(compgen -W 'auto always never' -- "$cur")); return ;;
                --format) COMPREPLY=($(compgen -W 'tree dot' -- "$cur")); return ;;
                --generate-completion-script) COMPREPLY=($(compgen -W 'bash zsh fish' -- "$cur")); return ;;
            esac

            command=""
            for word in "${COMP_WORDS[@]:1}"; do
                case "$word" in
                    \(commands.replacingOccurrences(of: " ", with: "|"))) command="$word"; break ;;
                esac
            done

            if [[ -z "$command" ]]; then
                candidates=\(shellQuote(commands + " " + optionTokens(CommandCatalog.rootOptions)))
            else
                case "$command" in
        \(cases)
                    help) candidates=\(shellQuote(commands + " --color --help -h --version")) ;;
                esac
            fi
            COMPREPLY=($(compgen -W "$candidates" -- "$cur"))
        }

        complete -F _uri uri
        """ + "\n"
    }

    private func zshScript() -> String {
        let commands = (CommandCatalog.commands + [
            .init(
                name: "help",
                abstract: "Show help information for a command.",
                usages: [],
                arguments: [],
                options: [],
            ),
        ]).map({ command in
            "\(zshEscape(command.name)):\(zshEscape(command.abstract))"
        }).joined(separator: " ")
        let cases = CommandCatalog.commands.map({ command in
            let options = (command.options + CommandCatalog.globalCommandOptions)
                .map(zshArgument)
                .joined(separator: " \\" + "\n                ")
            return """
                \(command.name))
                    _arguments -s \\
                        \(options) \\
                        '*:argument:_files'
                    ;;
            """
        }).joined(separator: "\n")
        return """
        #compdef uri

        _uri() {
            local command context state line word
            typeset -A opt_args

            command=""
            for word in $words[2,-1]; do
                case "$word" in
                    \(CommandCatalog.commands.map(\.name).joined(separator: "|"))|help) command="$word"; break ;;
                esac
            done

            if [[ -z "$command" ]]; then
                _arguments -C -s \\
                    \(CommandCatalog.rootOptions.map(zshArgument).joined(separator: " \\" + "\n                    ")) \\
                    '1:command:->command'
                if [[ "$state" == command ]]; then
                    _values 'command' \(commands)
                fi
                return
            fi

            case "$command" in
        \(cases)
                help)
                    _values 'command' \(CommandCatalog.commands.map(\.name).joined(separator: " "))
                    ;;
            esac
        }

        compdef _uri uri
        """ + "\n"
    }

    private func fishScript() -> String {
        var lines = [
            "complete -c uri -f",
        ]
        for option in CommandCatalog.rootOptions {
            lines.append(fishCompletion(option))
        }
        for command in CommandCatalog.commands {
            lines.append(
                "complete -c uri -n '__fish_use_subcommand' -a \(shellQuote(command.name)) -d \(shellQuote(command.abstract))",
            )
            for option in command.options + CommandCatalog.globalCommandOptions {
                lines.append(
                    fishCompletion(
                        option,
                        condition: "__fish_seen_subcommand_from \(command.name)",
                    ),
                )
            }
        }
        lines.append(
            "complete -c uri -n '__fish_use_subcommand' -a help -d 'Show help information for a command.'",
        )
        lines.append(
            "complete -c uri -n '__fish_seen_subcommand_from help' -a \(shellQuote(CommandCatalog.commands.map(\.name).joined(separator: " ")))",
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private func optionTokens(_ options: [OptionDefinition]) -> String {
        options.flatMap({ option in
            var values = ["--\(option.longName)"]
            if let shortName = option.shortName {
                values.append("-\(shortName)")
            }
            return values
        }).joined(separator: " ")
    }

    private func zshArgument(_ option: OptionDefinition) -> String {
        let description = zshEscape(option.help)
        let names: String
        if let shortName = option.shortName {
            names = "'{-\(shortName),--\(option.longName)}[\(description)]"
        }
        else {
            names = "'--\(option.longName)[\(description)]"
        }
        switch option.valueKind {
        case .flag:
            return names + "'"
        case .value(let name, let values):
            let completion = values.isEmpty ? "" : ":(\(values.joined(separator: " ")))"
            return names + ":\(zshEscape(name))\(completion)'"
        case .optionalValue(let name):
            return names + "::\(zshEscape(name)):'"
        }
    }

    private func fishCompletion(
        _ option: OptionDefinition,
        condition: String? = nil,
    ) -> String {
        var components = ["complete", "-c", "uri"]
        if let condition {
            components += ["-n", shellQuote(condition)]
        }
        components += ["-l", option.longName]
        if let shortName = option.shortName {
            components += ["-s", String(shortName)]
        }
        if !option.help.isEmpty {
            components += ["-d", shellQuote(option.help)]
        }
        switch option.valueKind {
        case .flag:
            break
        case .value(_, let values):
            components.append("-r")
            if !values.isEmpty {
                components += ["-a", shellQuote(values.joined(separator: " "))]
            }
        case .optionalValue:
            break
        }
        return components.joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func zshEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "'", with: "'\\''")
    }
}
