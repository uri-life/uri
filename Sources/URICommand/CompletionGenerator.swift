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
        """
        _uri() {
            local cur output kind value description wants_directories
            local -a request candidates
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            request=("${COMP_WORDS[@]:1:$COMP_CWORD}")
            output=$(command uri --_complete -- "${request[@]}" 2>/dev/null) || return 0
            wants_directories=0

            while IFS=$'\t' read -r kind value description; do
                case "$kind" in
                    candidate)
                        candidates[${#candidates[@]}]="$value"
                        ;;
                    directive)
                        [[ "$value" == directories ]] && wants_directories=1
                        ;;
                esac
            done <<< "$output"

            if [[ "$wants_directories" == 1 ]]; then
                while IFS= read -r value; do
                    candidates[${#candidates[@]}]="$value"
                done < <(compgen -d -- "$cur")
            fi
            COMPREPLY=("${candidates[@]}")
        }

        complete -o filenames -F _uri uri
        """ + "\n"
    }

    private func zshScript() -> String {
        """
        #compdef uri

        _uri() {
            local output kind value description
            local -a request candidates descriptions
            local -i wants_directories=0

            request=("${(@)words[2,$CURRENT]}")
            output=$(command uri --_complete -- "${request[@]}" 2>/dev/null) || return 0

            while IFS=$'\t' read -r kind value description; do
                case "$kind" in
                    candidate)
                        candidates+=("$value")
                        descriptions+=("$description")
                        ;;
                    directive)
                        [[ "$value" == directories ]] && wants_directories=1
                        ;;
                esac
            done <<< "$output"

            if (( ${#candidates} )); then
                compadd -S ' ' -d descriptions -- "${candidates[@]}"
            fi
            (( wants_directories )) && _path_files -/
        }

        compdef _uri uri
        """ + "\n"
    }

    private func fishScript() -> String {
        let registrations = fishValueOptionRegistrations().joined(separator: "\n")
        return """
        function __uri_complete
            set -l words (commandline -opc)
            set -e words[1]
            set -l current (commandline -ct)

            command uri --_complete -- $words "$current" 2>/dev/null | while read -l line
                set -l fields (string split (printf '\\t') -- "$line")
                switch $fields[1]
                    case candidate
                        printf '%s\\t%s\\n' "$fields[2]" "$fields[3]"
                    case directive
                        if test "$fields[2]" = directories
                            __fish_complete_directories "$current"
                        end
                end
            end
        end

        complete -c uri -f -a '(__uri_complete)'
        \(registrations)
        """ + "\n"
    }

    private func fishValueOptionRegistrations() -> [String] {
        var registrations = [String]()
        for option in CommandCatalog.rootOptions where option.acceptsValue {
            let condition = option.id == .color ? nil : "__fish_use_subcommand"
            registrations.append(fishValueOptionRegistration(option, condition: condition))
        }
        for command in CommandCatalog.commands {
            for option in command.options where option.acceptsValue {
                registrations.append(
                    fishValueOptionRegistration(
                        option,
                        condition: "__fish_seen_subcommand_from \(command.name)",
                    ),
                )
            }
        }
        return registrations
    }

    private func fishValueOptionRegistration(
        _ option: OptionDefinition,
        condition: String?,
    ) -> String {
        var components = ["complete", "-c", "uri", "-f"]
        if let condition {
            components += ["-n", fishQuote(condition)]
        }
        components += [
            "-l", option.longName,
            "-r",
            "-a", "'(__uri_complete)'",
        ]
        if !option.help.isEmpty {
            components += ["-d", fishQuote(option.help)]
        }
        return components.joined(separator: " ")
    }

    private func fishQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "\\'"))'"
    }
}

private extension OptionDefinition {

    var acceptsValue: Bool {
        guard case .value = valueKind else {
            return false
        }
        return true
    }
}
