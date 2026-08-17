enum CommandID: String, CaseIterable, Equatable {

    case initialize = "init"

    case add

    case remove

    case exclude

    case include

    case list

    case graph

    case expand

    case apply

    case collapse

    case vanish
}

enum OptionID: Equatable, Hashable {

    case upstream
    case branchPrefix
    case committerName
    case committerEmail
    case name
    case description
    case dependencies
    case developmentDependencies
    case inherits
    case inheritsUpstream
    case force
    case listEphemeral
    case includeDevelopment
    case format
    case continueOperation
    case abortOperation
    case noDevelopment
    case recursive
    case discard
    case color
    case help
    case version
    case completion

    var longName: String {
        switch self {
        case .upstream: "upstream"
        case .branchPrefix: "branch-prefix"
        case .committerName: "committer-name"
        case .committerEmail: "committer-email"
        case .name: "name"
        case .description: "description"
        case .dependencies: "dependencies"
        case .developmentDependencies: "dev-dependencies"
        case .inherits: "inherits"
        case .inheritsUpstream: "inherits-upstream"
        case .force: "force"
        case .listEphemeral: "ephemeral"
        case .includeDevelopment: "include-dev"
        case .format: "format"
        case .continueOperation: "continue"
        case .abortOperation: "abort"
        case .noDevelopment: "no-dev"
        case .recursive: "recursive"
        case .discard: "discard"
        case .color: "color"
        case .help: "help"
        case .version: "version"
        case .completion: "generate-completion-script"
        }
    }
}

enum ArgumentID: String, Equatable, Hashable {

    case source = "SOURCE"
    case version = "VERSION"
    case patchset = "PATCHSET"
    case feature = "FEATURE"
    case target = "TARGET"
    case id = "ID"
}

enum OptionValueKind: Equatable {

    case flag

    case value(name: String, allowedValues: [String] = [])
}

struct EphemeralTargetDefinition: Equatable {

    let longName: String

    let valueName: String

    let help: String

    var token: String {
        "--\(longName)"
    }

    var synopsis: String {
        "\(token) [\(valueName)]"
    }
}

struct TargetDefinition: Equatable {

    let ephemeral: EphemeralTargetDefinition?
}

struct OptionDefinition: Equatable {

    let id: OptionID

    let shortName: Character?

    let valueKind: OptionValueKind

    let help: String

    init(
        _ id: OptionID,
        shortName: Character? = nil,
        valueKind: OptionValueKind = .flag,
        help: String = "",
    ) {
        self.id = id
        self.shortName = shortName
        self.valueKind = valueKind
        self.help = help
    }

    var longName: String {
        id.longName
    }

    var synopsis: String {
        let names: String
        if let shortName {
            names = "-\(shortName), --\(longName)"
        }
        else {
            names = "--\(longName)"
        }
        switch valueKind {
        case .flag:
            return names
        case .value(let name, _):
            return "\(names) <\(name)>"
        }
    }
}

enum ArgumentValueKind: Equatable {

    case scalar

    case source

    case target(TargetDefinition)
}

struct ArgumentDefinition: Equatable {

    let id: ArgumentID

    let optional: Bool

    let valueKind: ArgumentValueKind

    let help: String

    var usage: String {
        optional ? "[\(id.rawValue)]" : id.rawValue
    }

    var ephemeralTarget: EphemeralTargetDefinition? {
        guard case .target(let target) = valueKind else {
            return nil
        }
        return target.ephemeral
    }
}

enum CommandFormID: Equatable {

    case primary

    case recovery

    case ephemeralList
}

enum CommandFormElement: Equatable {

    case argument(ArgumentDefinition)

    case requiredOption(OptionID)

    case oneOf([OptionID])
}

struct CommandForm: Equatable {

    let id: CommandFormID

    let elements: [CommandFormElement]

    let allowedOptions: Set<OptionID>

    var arguments: [ArgumentDefinition] {
        elements.compactMap({ element in
            guard case .argument(let argument) = element else {
                return nil
            }
            return argument
        })
    }

    var ephemeralTarget: EphemeralTargetDefinition? {
        arguments.compactMap(\.ephemeralTarget).first
    }
}

struct CommandDefinition: Equatable {

    let id: CommandID

    let abstract: String

    let forms: [CommandForm]

    let options: [OptionDefinition]

    var name: String {
        id.rawValue
    }

    var arguments: [ArgumentDefinition] {
        var seen = Set<ArgumentID>()
        return forms.flatMap(\.arguments).filter({ seen.insert($0.id).inserted })
    }

    var ephemeralTarget: EphemeralTargetDefinition? {
        forms.compactMap(\.ephemeralTarget).first
    }
}

enum RootFormElement: Equatable {

    case optionalOption(OptionID)

    case command
}

struct RootCommandDefinition: Equatable {

    let elements: [RootFormElement]
}

struct UsageRenderer {

    func render(_ command: CommandDefinition) -> [String] {
        command.forms.map({ form in
            (["uri", command.name] + form.elements.map(render)).joined(separator: " ")
        })
    }

    func renderRoot(_ root: RootCommandDefinition) -> String {
        (["uri"] + root.elements.map(render)).joined(separator: " ")
    }

    private func render(_ element: CommandFormElement) -> String {
        switch element {
        case .argument(let argument):
            return argument.usage
        case .requiredOption(let option):
            return "--\(option.longName)"
        case .oneOf(let options):
            return "(" + options.map({ "--\($0.longName)" }).joined(separator: "|") + ")"
        }
    }

    private func render(_ element: RootFormElement) -> String {
        switch element {
        case .optionalOption(let option):
            guard let definition = CommandCatalog.rootOptions.first(where: { $0.id == option })
            else {
                fatalError("Every root form option must have a definition.")
            }
            switch definition.valueKind {
            case .flag:
                return "[--\(option.longName)]"
            case .value(let name, _):
                return "[--\(option.longName) <\(name)>]"
            }
        case .command:
            return "<command>"
        }
    }
}

enum CommandCatalog {

    static let abstract = "Reconstruct, apply, and author portable Git patchsets."

    static let rootForm = RootCommandDefinition(
        elements: [.optionalOption(.color), .command],
    )

    static let colorOption =
        OptionDefinition(
            .color,
            valueKind: .value(
                name: "when",
                allowedValues: ColorMode.allCases.map(\.rawValue),
            ),
            help: "Colorize human-facing output: auto, always, or never. (default: auto)",
        )

    static let helpOption =
        OptionDefinition(
            .help,
            shortName: "h",
            help: "Show help information.",
        )

    static let versionOption =
        OptionDefinition(
            .version,
            help: "Show the version.",
        )

    static let completionOption =
        OptionDefinition(
            .completion,
            valueKind: .value(
                name: "shell",
                allowedValues: CompletionShell.allCases.map(\.rawValue),
            ),
            help: "Generate a completion script for bash, zsh, or fish.",
        )

    static let commands = [
        CommandDefinition(
            id: .initialize,
            abstract: "Initialize a patchset root or add an upstream version.",
            forms: [
                form(
                    [source(), argument(.version, optional: true)],
                    options: [.upstream, .branchPrefix, .committerName, .committerEmail],
                )
            ],
            options: [
                .init(
                    .upstream,
                    valueKind: .value(name: "url"),
                    help: "Upstream Git URL for a new root.",
                ),
                .init(
                    .branchPrefix,
                    valueKind: .value(name: "prefix"),
                    help: "Generated branch prefix. (default: uri)",
                ),
                .init(
                    .committerName,
                    valueKind: .value(name: "name"),
                    help: "Explicit committer name; requires --committer-email.",
                ),
                .init(
                    .committerEmail,
                    valueKind: .value(name: "email"),
                    help: "Explicit committer email; requires --committer-name.",
                ),
            ],
        ),
        CommandDefinition(
            id: .add,
            abstract: "Add a patchset or feature.",
            forms: [
                form(
                    [
                        source(),
                        argument(.version),
                        argument(.patchset),
                        argument(.feature, optional: true),
                    ],
                    options: [
                        .name, .description, .dependencies, .developmentDependencies,
                        .inherits, .inheritsUpstream,
                    ],
                )
            ],
            options: [
                .init(.name, valueKind: .value(name: "name")),
                .init(.description, valueKind: .value(name: "description")),
                .init(.dependencies, valueKind: .value(name: "ids")),
                .init(.developmentDependencies, valueKind: .value(name: "ids")),
                .init(.inherits, valueKind: .value(name: "patchset")),
                .init(.inheritsUpstream, valueKind: .value(name: "version")),
            ],
        ),
        CommandDefinition(
            id: .remove,
            abstract: "Remove a version, patchset, or feature.",
            forms: [
                form(
                    [
                        source(),
                        argument(.version),
                        argument(.patchset, optional: true),
                        argument(.feature, optional: true),
                    ],
                    options: [.force],
                )
            ],
            options: [
                .init(.force, shortName: "f", help: "Skip the confirmation prompt.")
            ],
        ),
        CommandDefinition(
            id: .exclude,
            abstract: "Exclude an inherited feature.",
            forms: [
                form([
                    source(), argument(.version), argument(.patchset), argument(.feature),
                ])
            ],
            options: [],
        ),
        CommandDefinition(
            id: .include,
            abstract: "Re-include an excluded feature.",
            forms: [
                form([
                    source(), argument(.version), argument(.patchset), argument(.feature),
                ])
            ],
            options: [],
        ),
        CommandDefinition(
            id: .list,
            abstract: "List patchset versions, patchsets, features, or ephemeral workspaces.",
            forms: [
                form([
                    source(),
                    argument(.version, optional: true),
                    argument(.patchset, optional: true),
                ]),
                .init(
                    id: .ephemeralList,
                    elements: [.requiredOption(.listEphemeral)],
                    allowedOptions: [.listEphemeral],
                ),
            ],
            options: [
                .init(.listEphemeral, help: "List all ephemeral workspaces.")
            ],
        ),
        CommandDefinition(
            id: .graph,
            abstract: "Print a feature dependency graph.",
            forms: [
                form(
                    [source(), argument(.version), argument(.patchset)],
                    options: [.includeDevelopment, .format],
                )
            ],
            options: [
                .init(.includeDevelopment, help: "Include development dependencies."),
                .init(
                    .format,
                    valueKind: .value(name: "format", allowedValues: ["tree", "dot"]),
                    help: "Output format: tree or dot. (default: tree)",
                ),
            ],
        ),
        CommandDefinition(
            id: .expand,
            abstract: "Expand one feature and its dependencies into editable branches.",
            forms: [
                form(
                    [
                        source(), argument(.version), argument(.patchset), argument(.feature),
                        target(),
                    ],
                    options: [.force, .noDevelopment],
                ),
                recoveryForm(),
            ],
            options: workflowOptions + [
                .init(.force, help: "Replace colliding generated branches."),
                .init(.noDevelopment, help: "Exclude development dependencies."),
            ],
        ),
        CommandDefinition(
            id: .apply,
            abstract: "Apply the complete regular dependency graph.",
            forms: [
                form([source(), argument(.version), argument(.patchset), target()]),
                recoveryForm(),
            ],
            options: workflowOptions,
        ),
        CommandDefinition(
            id: .collapse,
            abstract: "Reconstruct patches from a completed expansion.",
            forms: [
                form([target()], options: [.recursive, .discard])
            ],
            options: [
                .init(.recursive, help: "Collapse dependency features recursively."),
                .init(.discard, help: "Discard expansion state without writing patches."),
            ],
        ),
        CommandDefinition(
            id: .vanish,
            abstract: "Safely remove an ephemeral workspace.",
            forms: [
                form([argument(.id, optional: true)], options: [.force])
            ],
            options: [
                .init(.force, help: "Ignore dirty worktree and changed-HEAD checks.")
            ],
        ),
    ]

    static let rootOptions = [colorOption, completionOption, versionOption, helpOption]

    static let globalCommandOptions = [colorOption, versionOption, helpOption]

    static func command(named name: String) -> CommandDefinition? {
        guard let id = CommandID(rawValue: name) else {
            return nil
        }
        return commands.first(where: { $0.id == id })
    }

    private static let workflowOptions = [
        OptionDefinition(.continueOperation, help: "Continue after resolving a conflict."),
        OptionDefinition(
            .abortOperation,
            help: "Abort the operation and restore its starting state.",
        ),
    ]

    private static let workflowEphemeralTarget = EphemeralTargetDefinition(
        longName: "ephemeral",
        valueName: "ID",
        help: "Use an ephemeral TARGET, optionally with ID.",
    )

    private static func form(
        _ arguments: [ArgumentDefinition],
        options: Set<OptionID> = [],
    ) -> CommandForm {
        .init(
            id: .primary,
            elements: arguments.map(CommandFormElement.argument),
            allowedOptions: options,
        )
    }

    private static func recoveryForm() -> CommandForm {
        .init(
            id: .recovery,
            elements: [
                .argument(target()),
                .oneOf([.continueOperation, .abortOperation]),
            ],
            allowedOptions: [.continueOperation, .abortOperation],
        )
    }

    private static func source() -> ArgumentDefinition {
        .init(
            id: .source,
            optional: true,
            valueKind: .source,
            help: "An explicit local path or supported source URL; omit to discover it.",
        )
    }

    private static func target() -> ArgumentDefinition {
        .init(
            id: .target,
            optional: true,
            valueKind: .target(.init(ephemeral: workflowEphemeralTarget)),
            help: "A path or \(workflowEphemeralTarget.synopsis); omit to discover the current worktree.",
        )
    }

    private static func argument(
        _ id: ArgumentID,
        optional: Bool = false,
    ) -> ArgumentDefinition {
        let help: String
        switch id {
        case .version:
            help = "The upstream version."
        case .patchset:
            help = "The patchset version."
        case .feature:
            help = "The feature ID."
        case .id:
            help = "An ephemeral workspace ID; omit to auto-select or prompt on a TTY."
        case .source, .target:
            fatalError("SOURCE and TARGET use their specialized definitions.")
        }
        return .init(id: id, optional: optional, valueKind: .scalar, help: help)
    }
}
