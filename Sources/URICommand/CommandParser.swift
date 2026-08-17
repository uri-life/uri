import URI

struct CommandUsageError: Error, Equatable, CustomStringConvertible {

    let message: String

    let commandName: String?

    var description: String {
        message
    }
}

enum ParsedOption: Equatable {

    case flag

    case value(String?)
}

struct ParsedArguments: Equatable {

    let positionals: [String]

    let options: [String: ParsedOption]

    func contains(_ name: String) -> Bool {
        options[name] != nil
    }

    func value(_ name: String) -> String? {
        guard case .value(let value) = options[name] else {
            return nil
        }
        return value
    }

    func optionalValue(_ name: String) -> (present: Bool, value: String?) {
        guard case .value(let value) = options[name] else {
            return (false, nil)
        }
        return (true, value)
    }
}

enum ParsedCommand {

    case initialize(Init)

    case add(Add)

    case remove(Remove)

    case exclude(Exclude)

    case include(Include)

    case list(List)

    case graph(Graph)

    case expand(Expand)

    case apply(Apply)

    case collapse(Collapse)

    case vanish(Vanish)

    func run(terminal: Terminal) async throws {
        switch self {
        case .initialize(let command):
            try await command.run(terminal: terminal)
        case .add(let command):
            try await command.run(terminal: terminal)
        case .remove(let command):
            try await command.run(terminal: terminal)
        case .exclude(let command):
            try await command.run(terminal: terminal)
        case .include(let command):
            try await command.run(terminal: terminal)
        case .list(let command):
            try await command.run(terminal: terminal)
        case .graph(let command):
            try await command.run(terminal: terminal)
        case .expand(let command):
            try await command.run(terminal: terminal)
        case .apply(let command):
            try await command.run(terminal: terminal)
        case .collapse(let command):
            try await command.run(terminal: terminal)
        case .vanish(let command):
            try await command.run(terminal: terminal)
        }
    }
}

enum CLIAction {

    case help(CommandDefinition?)

    case version

    case completion(CompletionShell)

    case run(ParsedCommand)
}

struct CLIInvocation {

    let action: CLIAction

    let colorMode: ColorMode
}

struct CommandParser {

    func preferredColorMode(in arguments: [String]) -> ColorMode {
        for (index, token) in arguments.enumerated() {
            if token.hasPrefix("--color=") {
                return ColorMode(rawValue: String(token.dropFirst("--color=".count))) ?? .auto
            }
            if token == "--color", arguments.indices.contains(index + 1) {
                return ColorMode(rawValue: arguments[index + 1]) ?? .auto
            }
        }
        return .auto
    }

    func commandName(in arguments: [String]) -> String? {
        var skipsNext = false
        for token in arguments {
            if skipsNext {
                skipsNext = false
                continue
            }
            if token == "--color" || token == "--generate-completion-script" {
                skipsNext = true
                continue
            }
            if token.hasPrefix("-") {
                continue
            }
            if CommandCatalog.command(named: token) != nil {
                return token
            }
            if token == "help" {
                continue
            }
        }
        return nil
    }

    func parse(_ arguments: [String]) throws -> CLIInvocation {
        var colorMode = ColorMode.auto
        var colorWasSpecified = false
        var specialAction: (name: String, action: CLIAction)?
        var parsesOptions = true
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            if parsesOptions, token == "--" {
                parsesOptions = false
                index += 1
                continue
            }
            if parsesOptions, token == "--color" || token.hasPrefix("--color=") {
                colorMode = try parseRootColor(
                    token: token,
                    arguments: arguments,
                    index: &index,
                    wasSpecified: &colorWasSpecified,
                )
                continue
            }
            if parsesOptions, token == "--version" {
                try setSpecialAction(
                    name: "--version",
                    action: .version,
                    current: &specialAction,
                )
                index += 1
                continue
            }
            if parsesOptions, token == "--help" || token == "-h" {
                try setSpecialAction(
                    name: "--help",
                    action: .help(nil),
                    current: &specialAction,
                )
                index += 1
                continue
            }
            if parsesOptions,
                token == "--generate-completion-script"
                    || token.hasPrefix("--generate-completion-script=")
            {
                let shell = try parseCompletionShell(
                    token: token,
                    arguments: arguments,
                    index: &index,
                )
                try setSpecialAction(
                    name: "--generate-completion-script",
                    action: .completion(shell),
                    current: &specialAction,
                )
                continue
            }
            if token == "help" {
                guard specialAction == nil else {
                    throw usage("Unexpected command 'help' after '\(specialAction!.name)'.")
                }
                return try parseHelp(
                    Array(arguments[arguments.index(after: index)...]),
                    colorMode: colorMode,
                    colorWasSpecified: colorWasSpecified,
                )
            }
            guard !parsesOptions || !token.hasPrefix("-") else {
                throw usage("Unknown option '\(token)'.")
            }
            guard let definition = CommandCatalog.command(named: token) else {
                throw usage("Unknown command '\(token)'.")
            }
            guard specialAction == nil else {
                throw usage("Unexpected command '\(token)' after '\(specialAction!.name)'.")
            }
            return try parse(
                definition,
                arguments: Array(arguments[arguments.index(after: index)...]),
                colorMode: colorMode,
                colorWasSpecified: colorWasSpecified,
            )
        }

        return .init(action: specialAction?.action ?? .help(nil), colorMode: colorMode)
    }

    private func setSpecialAction(
        name: String,
        action: CLIAction,
        current: inout (name: String, action: CLIAction)?,
    ) throws {
        guard current == nil else {
            if current?.name == name {
                throw usage("Option '\(name)' may only be specified once.")
            }
            throw usage("Options '\(current!.name)' and '\(name)' cannot be used together.")
        }
        current = (name, action)
    }

    private func parse(
        _ definition: CommandDefinition,
        arguments: [String],
        colorMode initialColorMode: ColorMode,
        colorWasSpecified initiallySpecified: Bool,
    ) throws -> CLIInvocation {
        let scan = try scan(
            definition,
            arguments: arguments,
            colorMode: initialColorMode,
            colorWasSpecified: initiallySpecified,
        )
        if scan.arguments.contains("help") {
            return .init(action: .help(definition), colorMode: scan.colorMode)
        }
        if scan.arguments.contains("version") {
            return .init(action: .version, colorMode: scan.colorMode)
        }
        return .init(
            action: .run(try makeCommand(definition, arguments: scan.arguments)),
            colorMode: scan.colorMode,
        )
    }

    private func parseHelp(
        _ arguments: [String],
        colorMode initialColorMode: ColorMode,
        colorWasSpecified initiallySpecified: Bool,
    ) throws -> CLIInvocation {
        var colorMode = initialColorMode
        var colorWasSpecified = initiallySpecified
        var commandName: String?
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--color" || token.hasPrefix("--color=") {
                colorMode = try parseRootColor(
                    token: token,
                    arguments: arguments,
                    index: &index,
                    wasSpecified: &colorWasSpecified,
                )
                continue
            }
            if token == "--help" || token == "-h" {
                index += 1
                continue
            }
            guard !token.hasPrefix("-") else {
                throw usage("Unknown option '\(token)' for 'uri help'.")
            }
            guard commandName == nil else {
                throw usage("The help command accepts at most one command name.")
            }
            commandName = token
            index += 1
        }
        guard let commandName else {
            return .init(action: .help(nil), colorMode: colorMode)
        }
        guard let definition = CommandCatalog.command(named: commandName) else {
            throw usage("Unknown command '\(commandName)'.")
        }
        return .init(action: .help(definition), colorMode: colorMode)
    }

    private func scan(
        _ definition: CommandDefinition,
        arguments: [String],
        colorMode initialColorMode: ColorMode,
        colorWasSpecified initiallySpecified: Bool,
    ) throws -> (arguments: ParsedArguments, colorMode: ColorMode) {
        let definitions = definition.options + CommandCatalog.globalCommandOptions
        let longOptions = Dictionary(
            definitions.map({ ($0.longName, $0) }),
            uniquingKeysWith: { first, _ in first },
        )
        let shortOptions = Dictionary(
            definitions.compactMap({ option in
                option.shortName.map({ ($0, option) })
            }),
            uniquingKeysWith: { first, _ in first },
        )
        var colorMode = initialColorMode
        var seen = Set<String>()
        if initiallySpecified {
            seen.insert("color")
        }
        var options = [String: ParsedOption]()
        var positionals = [String]()
        var parsesOptions = true
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            if parsesOptions, token == "--" {
                parsesOptions = false
                index += 1
                continue
            }
            guard parsesOptions, token.hasPrefix("-"), token != "-" else {
                positionals.append(token)
                index += 1
                continue
            }

            let match = try matchOption(
                token,
                longOptions: longOptions,
                shortOptions: shortOptions,
                commandName: definition.name,
            )
            let option = match.definition
            guard seen.insert(option.longName).inserted else {
                throw usage(
                    "Option '--\(option.longName)' may only be specified once.",
                    commandName: definition.name,
                )
            }
            switch option.valueKind {
            case .flag:
                guard match.attachedValue == nil else {
                    throw usage(
                        "Option '--\(option.longName)' does not accept a value.",
                        commandName: definition.name,
                    )
                }
                options[option.longName] = .flag
                index += 1
            case .value(_, let allowedValues):
                let value: String
                if let attachedValue = match.attachedValue {
                    value = attachedValue
                    index += 1
                }
                else {
                    let valueIndex = arguments.index(after: index)
                    guard valueIndex < arguments.endIndex,
                        arguments[valueIndex] != "--",
                        !arguments[valueIndex].hasPrefix("-")
                    else {
                        throw usage(
                            "Missing value for '--\(option.longName)'.",
                            commandName: definition.name,
                        )
                    }
                    value = arguments[valueIndex]
                    index = arguments.index(after: valueIndex)
                }
                guard !value.isEmpty else {
                    throw usage(
                        "Option '--\(option.longName)' requires a nonempty value.",
                        commandName: definition.name,
                    )
                }
                if !allowedValues.isEmpty, !allowedValues.contains(value) {
                    throw usage(
                        "Invalid value '\(value)' for '--\(option.longName)'; expected \(allowedValues.joined(separator: ", ")).",
                        commandName: definition.name,
                    )
                }
                if option.longName == "color" {
                    colorMode = ColorMode(rawValue: value)!
                }
                else {
                    options[option.longName] = .value(value)
                }
            case .optionalValue:
                var value = match.attachedValue
                if value?.isEmpty == true {
                    throw usage(
                        "Option '--\(option.longName)' requires a nonempty value after '='.",
                        commandName: definition.name,
                    )
                }
                if value == nil {
                    let valueIndex = arguments.index(after: index)
                    if valueIndex < arguments.endIndex,
                        !arguments[valueIndex].hasPrefix("-")
                    {
                        value = arguments[valueIndex]
                        index = arguments.index(after: valueIndex)
                    }
                    else {
                        index += 1
                    }
                }
                else {
                    index += 1
                }
                if option.longName == "ephemeral",
                    definition.supportsFinalEphemeralSelector,
                    index != arguments.endIndex
                {
                    throw usage(
                        "--ephemeral [ID] must be the final TARGET selector in the command.",
                        commandName: definition.name,
                    )
                }
                options[option.longName] = .value(value)
            }
        }

        return (
            .init(positionals: positionals, options: options),
            colorMode
        )
    }

    private func makeCommand(
        _ definition: CommandDefinition,
        arguments: ParsedArguments,
    ) throws -> ParsedCommand {
        let positionals = arguments.positionals
        let split = CLI.splitSource(positionals)
        let ephemeral = ephemeralValue(arguments)

        switch definition.name {
        case "init":
            guard split.rest.count <= 1 else {
                throw usage("init accepts at most SOURCE and VERSION.", commandName: definition.name)
            }
            guard arguments.contains("committer-name") == arguments.contains("committer-email") else {
                throw usage(
                    "--committer-name and --committer-email must be specified together.",
                    commandName: definition.name,
                )
            }
            return .initialize(
                .init(
                    values: positionals,
                    upstream: arguments.value("upstream"),
                    branchPrefix: arguments.value("branch-prefix"),
                    committerName: arguments.value("committer-name"),
                    committerEmail: arguments.value("committer-email"),
                ),
            )
        case "add":
            guard split.rest.count == 2 || split.rest.count == 3 else {
                throw usage(
                    "add requires VERSION PATCHSET [FEATURE].",
                    commandName: definition.name,
                )
            }
            if split.rest.count == 2 {
                guard !arguments.contains("name"),
                    !arguments.contains("description"),
                    !arguments.contains("dependencies"),
                    !arguments.contains("dev-dependencies")
                else {
                    throw usage("Feature options require FEATURE.", commandName: definition.name)
                }
                guard !arguments.contains("inherits-upstream") || arguments.contains("inherits") else {
                    throw usage(
                        "--inherits-upstream requires --inherits.",
                        commandName: definition.name,
                    )
                }
            }
            else {
                guard !arguments.contains("inherits"), !arguments.contains("inherits-upstream") else {
                    throw usage(
                        "Inheritance options cannot be used with FEATURE.",
                        commandName: definition.name,
                    )
                }
            }
            return .add(
                .init(
                    values: positionals,
                    name: arguments.value("name"),
                    featureDescription: arguments.value("description"),
                    dependencies: arguments.value("dependencies"),
                    devDependencies: arguments.value("dev-dependencies"),
                    inherits: arguments.value("inherits"),
                    inheritsUpstream: arguments.value("inherits-upstream"),
                ),
            )
        case "remove":
            guard (1...3).contains(split.rest.count) else {
                throw usage(
                    "remove requires VERSION [PATCHSET] [FEATURE].",
                    commandName: definition.name,
                )
            }
            return .remove(.init(values: positionals, force: arguments.contains("force")))
        case "exclude":
            guard split.rest.count == 3 else {
                throw usage(
                    "exclude requires VERSION PATCHSET FEATURE.",
                    commandName: definition.name,
                )
            }
            return .exclude(.init(values: positionals))
        case "include":
            guard split.rest.count == 3 else {
                throw usage(
                    "include requires VERSION PATCHSET FEATURE.",
                    commandName: definition.name,
                )
            }
            return .include(.init(values: positionals))
        case "list":
            let ephemeralOption = arguments.optionalValue("ephemeral")
            if ephemeralOption.present {
                guard positionals.isEmpty else {
                    throw usage(
                        "Patchset SOURCE arguments cannot be combined with --ephemeral.",
                        commandName: definition.name,
                    )
                }
                if arguments.contains("path"), ephemeralOption.value == nil {
                    throw usage(
                        "--path requires an explicit --ephemeral ID.",
                        commandName: definition.name,
                    )
                }
            }
            else {
                guard !arguments.contains("path") else {
                    throw usage("--path requires --ephemeral ID.", commandName: definition.name)
                }
                guard split.rest.count <= 2 else {
                    throw usage(
                        "list accepts [VERSION] [PATCHSET].",
                        commandName: definition.name,
                    )
                }
            }
            return .list(
                .init(
                    values: positionals,
                    ephemeral: ephemeral,
                    path: arguments.contains("path"),
                ),
            )
        case "graph":
            guard split.rest.count == 2 else {
                throw usage("graph requires VERSION PATCHSET.", commandName: definition.name)
            }
            return .graph(
                .init(
                    values: positionals,
                    includeDevelopment: arguments.contains("include-dev"),
                    format: Graph.Format(rawValue: arguments.value("format") ?? "tree")!,
                ),
            )
        case "expand":
            let recovery = try recoveryMode(arguments, commandName: definition.name)
            if recovery != nil {
                guard positionals.count <= 1 else {
                    throw usage("Recovery accepts at most TARGET.", commandName: definition.name)
                }
                guard !arguments.contains("force"), !arguments.contains("no-dev") else {
                    throw usage(
                        "Start-only options cannot be used for recovery.",
                        commandName: definition.name,
                    )
                }
            }
            else {
                guard split.rest.count == 3 || split.rest.count == 4 else {
                    throw usage(
                        "expand requires [SOURCE] VERSION PATCHSET FEATURE [TARGET].",
                        commandName: definition.name,
                    )
                }
                if ephemeral != nil, split.rest.count == 4 {
                    throw usage(
                        "TARGET and --ephemeral cannot be used together.",
                        commandName: definition.name,
                    )
                }
            }
            return .expand(
                .init(
                    values: positionals,
                    continueOperation: recovery == .continueOperation,
                    abortOperation: recovery == .abortOperation,
                    force: arguments.contains("force"),
                    noDevelopmentDependencies: arguments.contains("no-dev"),
                    ephemeral: ephemeral,
                ),
            )
        case "apply":
            let recovery = try recoveryMode(arguments, commandName: definition.name)
            if recovery != nil {
                guard positionals.count <= 1 else {
                    throw usage("Recovery accepts at most TARGET.", commandName: definition.name)
                }
            }
            else {
                guard split.rest.count == 2 || split.rest.count == 3 else {
                    throw usage(
                        "apply requires [SOURCE] VERSION PATCHSET [TARGET].",
                        commandName: definition.name,
                    )
                }
                if ephemeral != nil, split.rest.count == 3 {
                    throw usage(
                        "TARGET and --ephemeral cannot be used together.",
                        commandName: definition.name,
                    )
                }
            }
            return .apply(
                .init(
                    values: positionals,
                    continueOperation: recovery == .continueOperation,
                    abortOperation: recovery == .abortOperation,
                    ephemeral: ephemeral,
                ),
            )
        case "collapse":
            guard positionals.count <= 1 else {
                throw usage("collapse accepts at most TARGET.", commandName: definition.name)
            }
            guard !(arguments.contains("recursive") && arguments.contains("discard")) else {
                throw usage(
                    "--recursive and --discard cannot be used together.",
                    commandName: definition.name,
                )
            }
            guard ephemeral == nil || positionals.isEmpty else {
                throw usage(
                    "TARGET and --ephemeral cannot be used together.",
                    commandName: definition.name,
                )
            }
            return .collapse(
                .init(
                    target: positionals.first,
                    recursive: arguments.contains("recursive"),
                    discard: arguments.contains("discard"),
                    ephemeral: ephemeral,
                ),
            )
        case "vanish":
            guard positionals.count <= 1 else {
                throw usage("vanish accepts at most ID.", commandName: definition.name)
            }
            return .vanish(
                .init(
                    id: positionals.first,
                    force: arguments.contains("force"),
                ),
            )
        default:
            fatalError("Every command definition must have a parser.")
        }
    }

    private func matchOption(
        _ token: String,
        longOptions: [String: OptionDefinition],
        shortOptions: [Character: OptionDefinition],
        commandName: String,
    ) throws -> (definition: OptionDefinition, attachedValue: String?) {
        if token.hasPrefix("--") {
            let value = token.dropFirst(2)
            let pieces = value.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false,
            )
            let name = String(pieces[0])
            guard !name.isEmpty, let definition = longOptions[name] else {
                throw usage("Unknown option '\(token)'.", commandName: commandName)
            }
            return (
                definition,
                pieces.count == 2 ? String(pieces[1]) : nil
            )
        }
        guard token.count == 2,
            let name = token.last,
            let definition = shortOptions[name]
        else {
            throw usage("Unknown option '\(token)'.", commandName: commandName)
        }
        return (definition, nil)
    }

    private func parseRootColor(
        token: String,
        arguments: [String],
        index: inout Int,
        wasSpecified: inout Bool,
    ) throws -> ColorMode {
        guard !wasSpecified else {
            throw usage("Option '--color' may only be specified once.")
        }
        wasSpecified = true
        let value: String
        if token.hasPrefix("--color=") {
            value = String(token.dropFirst("--color=".count))
            index += 1
        }
        else {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex,
                !arguments[valueIndex].hasPrefix("-")
            else {
                throw usage("Missing value for '--color'.")
            }
            value = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        }
        guard let colorMode = ColorMode(rawValue: value) else {
            throw usage(
                "Invalid value '\(value)' for '--color'; expected auto, always, never.",
            )
        }
        return colorMode
    }

    private func parseCompletionShell(
        token: String,
        arguments: [String],
        index: inout Int,
    ) throws -> CompletionShell {
        let value: String
        if token.hasPrefix("--generate-completion-script=") {
            value = String(token.dropFirst("--generate-completion-script=".count))
            index += 1
        }
        else {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex,
                !arguments[valueIndex].hasPrefix("-")
            else {
                throw usage("Missing shell for '--generate-completion-script'.")
            }
            value = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        }
        guard let shell = CompletionShell(rawValue: value) else {
            throw usage(
                "Invalid completion shell '\(value)'; expected bash, zsh, fish.",
            )
        }
        return shell
    }

    private func ephemeralValue(_ arguments: ParsedArguments) -> String? {
        let option = arguments.optionalValue("ephemeral")
        guard option.present else {
            return nil
        }
        return option.value ?? CLI.automaticEphemeralID
    }

    private func recoveryMode(
        _ arguments: ParsedArguments,
        commandName: String,
    ) throws -> RecoveryMode? {
        let continueOperation = arguments.contains("continue")
        let abortOperation = arguments.contains("abort")
        guard !(continueOperation && abortOperation) else {
            throw usage(
                "--continue and --abort cannot be used together.",
                commandName: commandName,
            )
        }
        if continueOperation {
            return .continueOperation
        }
        if abortOperation {
            return .abortOperation
        }
        return nil
    }

    private func usage(
        _ message: String,
        commandName: String? = nil,
    ) -> CommandUsageError {
        .init(message: message, commandName: commandName)
    }

    private enum RecoveryMode {

        case continueOperation

        case abortOperation
    }
}
