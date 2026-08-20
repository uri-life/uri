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

    case value(String)
}

enum PositionalToken: Equatable {

    case value(String)

    case ephemeralTarget(id: String?)
}

struct ParsedArguments: Equatable {

    let positionals: [PositionalToken]

    let options: [OptionID: ParsedOption]

    func contains(_ id: OptionID) -> Bool {
        options[id] != nil
    }

    func value(_ id: OptionID) -> String? {
        guard case .value(let value) = options[id] else {
            return nil
        }
        return value
    }
}

struct MatchedCommandForm: Equatable {

    let form: CommandForm

    let values: [String]

    let target: TargetArgumentValue

    let options: [OptionID: ParsedOption]

    func contains(_ id: OptionID) -> Bool {
        options[id] != nil
    }

    func value(_ id: OptionID) -> String? {
        guard case .value(let value) = options[id] else {
            return nil
        }
        return value
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
                try setSpecialAction(name: "--version", action: .version, current: &specialAction)
                index += 1
                continue
            }
            if parsesOptions, token == "--help" || token == "-h" {
                try setSpecialAction(name: "--help", action: .help(nil), current: &specialAction)
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
        if scan.arguments.contains(.help) {
            return .init(action: .help(definition), colorMode: scan.colorMode)
        }
        if scan.arguments.contains(.version) {
            return .init(action: .version, colorMode: scan.colorMode)
        }
        let matched = try match(definition, arguments: scan.arguments)
        return .init(
            action: .run(try makeCommand(definition, arguments: matched)),
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
        var seen = Set<OptionID>()
        if initiallySpecified {
            seen.insert(.color)
        }
        var options = [OptionID: ParsedOption]()
        var positionals = [PositionalToken]()
        var parsesOptions = true
        var sawEphemeralTarget = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            if parsesOptions, token == "--" {
                guard !sawEphemeralTarget else {
                    throw usage(
                        "'--' cannot follow an ephemeral TARGET.",
                        commandName: definition.name,
                    )
                }
                parsesOptions = false
                index += 1
                continue
            }
            if parsesOptions,
                let ephemeralTarget = definition.ephemeralTarget,
                token == ephemeralTarget.token || token.hasPrefix("\(ephemeralTarget.token)=")
            {
                guard !sawEphemeralTarget else {
                    throw usage(
                        "TARGET may only be specified once.",
                        commandName: definition.name,
                    )
                }
                let id: String?
                if token.hasPrefix("\(ephemeralTarget.token)=") {
                    let prefix = "\(ephemeralTarget.token)="
                    let value = String(token.dropFirst(prefix.count))
                    guard !value.isEmpty else {
                        throw usage(
                            "Ephemeral TARGET requires a nonempty ID after '='.",
                            commandName: definition.name,
                        )
                    }
                    id = value
                    index += 1
                }
                else {
                    let valueIndex = arguments.index(after: index)
                    if valueIndex < arguments.endIndex,
                        arguments[valueIndex] != "--",
                        !arguments[valueIndex].hasPrefix("-")
                    {
                        id = arguments[valueIndex]
                        index = arguments.index(after: valueIndex)
                    }
                    else {
                        id = nil
                        index += 1
                    }
                }
                if let id {
                    do {
                        try EphemeralWorkspaceManager.validateID(id)
                    }
                    catch {
                        throw usage(
                            String(describing: error),
                            commandName: definition.name,
                        )
                    }
                }
                positionals.append(.ephemeralTarget(id: id))
                sawEphemeralTarget = true
                continue
            }
            guard parsesOptions, token.hasPrefix("-"), token != "-" else {
                positionals.append(.value(token))
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
            guard seen.insert(option.id).inserted else {
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
                options[option.id] = .flag
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
                if option.id == .color {
                    colorMode = ColorMode(rawValue: value)!
                }
                else {
                    options[option.id] = .value(value)
                }
            }
        }

        return (.init(positionals: positionals, options: options), colorMode)
    }

    private func match(
        _ definition: CommandDefinition,
        arguments: ParsedArguments,
    ) throws -> MatchedCommandForm {
        for form in definition.forms {
            guard Set(arguments.options.keys).isSubset(of: form.allowedOptions) else {
                continue
            }
            guard
                form.elements.allSatisfy({ element in
                    switch element {
                    case .argument:
                        return true
                    case .requiredOption(let option):
                        return arguments.contains(option)
                    case .oneOf(let options):
                        return options.filter(arguments.contains).count == 1
                    }
                })
            else {
                continue
            }
            if let positionalMatch = match(
                arguments.positionals,
                to: form.arguments,
            ) {
                return .init(
                    form: form,
                    values: positionalMatch.values,
                    target: positionalMatch.target,
                    options: arguments.options,
                )
            }
        }
        throw usage(
            "Arguments do not match any accepted form of 'uri \(definition.name)'.",
            commandName: definition.name,
        )
    }

    private func match(
        _ tokens: [PositionalToken],
        to definitions: [ArgumentDefinition],
    ) -> (values: [String], target: TargetArgumentValue)? {
        var index = 0
        var values = [String]()
        var target = TargetArgumentValue.omitted

        for definition in definitions {
            let token = tokens.indices.contains(index) ? tokens[index] : nil
            switch definition.valueKind {
            case .source:
                if case .value(let value) = token,
                    PatchsetSourceLocator.recognizesExplicitSource(value)
                {
                    values.append(value)
                    index += 1
                }
                else if !definition.optional {
                    return nil
                }
            case .scalar:
                if case .value(let value) = token {
                    values.append(value)
                    index += 1
                }
                else if !definition.optional {
                    return nil
                }
            case .target(let targetDefinition):
                switch token {
                case .value(let value):
                    target = .path(value)
                    index += 1
                case .ephemeralTarget(let id) where targetDefinition.ephemeral != nil:
                    target = .ephemeral(id: id)
                    index += 1
                case nil where definition.optional:
                    break
                default:
                    return nil
                }
            }
        }
        guard index == tokens.count else {
            return nil
        }
        return (values, target)
    }

    private func makeCommand(
        _ definition: CommandDefinition,
        arguments: MatchedCommandForm,
    ) throws -> ParsedCommand {
        let values = arguments.values
        let split = CLI.splitSource(values)

        switch definition.id {
        case .initialize:
            guard arguments.contains(.committerName) == arguments.contains(.committerEmail) else {
                throw usage(
                    "--committer-name and --committer-email must be specified together.",
                    commandName: definition.name,
                )
            }
            return .initialize(
                .init(
                    values: values,
                    upstream: arguments.value(.upstream),
                    branchPrefix: arguments.value(.branchPrefix),
                    committerName: arguments.value(.committerName),
                    committerEmail: arguments.value(.committerEmail),
                ),
            )
        case .add:
            if split.rest.count == 2 {
                guard !arguments.contains(.name),
                    !arguments.contains(.description),
                    !arguments.contains(.dependencies),
                    !arguments.contains(.developmentDependencies)
                else {
                    throw usage("Feature options require FEATURE.", commandName: definition.name)
                }
                guard !arguments.contains(.inheritsUpstream) || arguments.contains(.inherits) else {
                    throw usage(
                        "--inherits-upstream requires --inherits.",
                        commandName: definition.name,
                    )
                }
            }
            else {
                guard !arguments.contains(.inherits), !arguments.contains(.inheritsUpstream) else {
                    throw usage(
                        "Inheritance options cannot be used with FEATURE.",
                        commandName: definition.name,
                    )
                }
            }
            return .add(
                .init(
                    values: values,
                    name: arguments.value(.name),
                    featureDescription: arguments.value(.description),
                    dependencies: arguments.value(.dependencies),
                    devDependencies: arguments.value(.developmentDependencies),
                    inherits: arguments.value(.inherits),
                    inheritsUpstream: arguments.value(.inheritsUpstream),
                ),
            )
        case .remove:
            return .remove(.init(values: values, force: arguments.contains(.force)))
        case .exclude:
            return .exclude(.init(values: values))
        case .include:
            return .include(.init(values: values))
        case .list:
            let mode: List.Mode =
                arguments.form.id == .ephemeralList
                ? .ephemeral
                : .hierarchy(values)
            return .list(.init(mode: mode))
        case .graph:
            return .graph(
                .init(
                    values: values,
                    includeDevelopment: arguments.contains(.includeDevelopment),
                    format: Graph.Format(rawValue: arguments.value(.format) ?? "tree")!,
                ),
            )
        case .expand:
            return .expand(
                .init(
                    values: values,
                    continueOperation: arguments.contains(.continueOperation),
                    abortOperation: arguments.contains(.abortOperation),
                    force: arguments.contains(.force),
                    noDevelopmentDependencies: arguments.contains(.noDevelopment),
                    target: arguments.target,
                ),
            )
        case .apply:
            return .apply(
                .init(
                    values: values,
                    continueOperation: arguments.contains(.continueOperation),
                    abortOperation: arguments.contains(.abortOperation),
                    includeDevelopmentDependencies: arguments.contains(.development),
                    target: arguments.target,
                ),
            )
        case .collapse:
            guard !(arguments.contains(.recursive) && arguments.contains(.discard)) else {
                throw usage(
                    "--recursive and --discard cannot be used together.",
                    commandName: definition.name,
                )
            }
            return .collapse(
                .init(
                    target: arguments.target,
                    recursive: arguments.contains(.recursive),
                    discard: arguments.contains(.discard),
                ),
            )
        case .vanish:
            return .vanish(.init(id: values.first, force: arguments.contains(.force)))
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
            return (definition, pieces.count == 2 ? String(pieces[1]) : nil)
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
            throw usage("Invalid value '\(value)' for '--color'; expected auto, always, never.")
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
            throw usage("Invalid completion shell '\(value)'; expected bash, zsh, fish.")
        }
        return shell
    }

    private func usage(
        _ message: String,
        commandName: String? = nil,
    ) -> CommandUsageError {
        .init(message: message, commandName: commandName)
    }
}
