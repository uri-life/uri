enum OptionValueKind: Equatable {

    case flag

    case value(name: String, allowedValues: [String] = [])

    case optionalValue(name: String)
}

struct OptionDefinition: Equatable {

    let longName: String

    let shortName: Character?

    let valueKind: OptionValueKind

    let help: String

    init(
        _ longName: String,
        shortName: Character? = nil,
        valueKind: OptionValueKind = .flag,
        help: String = "",
    ) {
        self.longName = longName
        self.shortName = shortName
        self.valueKind = valueKind
        self.help = help
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
        case .optionalValue(let name):
            return "\(names) [<\(name)>]"
        }
    }
}

struct ArgumentDefinition: Equatable {

    let synopsis: String

    let help: String
}

struct CommandDefinition: Equatable {

    let name: String

    let abstract: String

    let usages: [String]

    let arguments: [ArgumentDefinition]

    let options: [OptionDefinition]

    var supportsFinalEphemeralSelector: Bool {
        ["expand", "apply", "collapse"].contains(name)
    }
}

enum CommandCatalog {

    static let abstract = "Reconstruct, apply, and author portable Git patchsets."

    static let colorOption =
        OptionDefinition(
            "color",
            valueKind: .value(
                name: "when",
                allowedValues: ColorMode.allCases.map(\.rawValue),
            ),
            help: "Colorize human-facing output: auto, always, or never. (default: auto)",
        )

    static let helpOption =
        OptionDefinition(
            "help",
            shortName: "h",
            help: "Show help information.",
        )

    static let versionOption =
        OptionDefinition(
            "version",
            help: "Show the version.",
        )

    static let completionOption =
        OptionDefinition(
            "generate-completion-script",
            valueKind: .value(
                name: "shell",
                allowedValues: CompletionShell.allCases.map(\.rawValue),
            ),
            help: "Generate a completion script for bash, zsh, or fish.",
        )

    static let commands = [
        CommandDefinition(
            name: "init",
            abstract: "Initialize a patchset root or add an upstream version.",
            usages: ["uri init [SOURCE] [VERSION] [options]"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] [VERSION]",
                    help: "Optional local SOURCE directory followed by an optional VERSION.",
                ),
            ],
            options: [
                .init(
                    "upstream",
                    valueKind: .value(name: "url"),
                    help: "Upstream Git URL for a new root.",
                ),
                .init(
                    "branch-prefix",
                    valueKind: .value(name: "prefix"),
                    help: "Generated branch prefix. (default: uri)",
                ),
                .init(
                    "committer-name",
                    valueKind: .value(name: "name"),
                    help: "Explicit committer name; requires --committer-email.",
                ),
                .init(
                    "committer-email",
                    valueKind: .value(name: "email"),
                    help: "Explicit committer email; requires --committer-name.",
                ),
            ],
        ),
        CommandDefinition(
            name: "add",
            abstract: "Add a patchset or feature.",
            usages: ["uri add [SOURCE] VERSION PATCHSET [FEATURE] [options]"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET [FEATURE]",
                    help: "Patchset coordinates and an optional feature ID.",
                ),
            ],
            options: [
                .init("name", valueKind: .value(name: "name")),
                .init("description", valueKind: .value(name: "description")),
                .init("dependencies", valueKind: .value(name: "ids")),
                .init("dev-dependencies", valueKind: .value(name: "ids")),
                .init("inherits", valueKind: .value(name: "patchset")),
                .init("inherits-upstream", valueKind: .value(name: "version")),
            ],
        ),
        CommandDefinition(
            name: "remove",
            abstract: "Remove a version, patchset, or feature.",
            usages: ["uri remove [SOURCE] VERSION [PATCHSET] [FEATURE] [options]"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION [PATCHSET] [FEATURE]",
                    help: "The local hierarchy to remove.",
                ),
            ],
            options: [
                .init(
                    "force",
                    shortName: "f",
                    help: "Skip the confirmation prompt.",
                ),
            ],
        ),
        CommandDefinition(
            name: "exclude",
            abstract: "Exclude an inherited feature.",
            usages: ["uri exclude [SOURCE] VERSION PATCHSET FEATURE"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET FEATURE",
                    help: "The inherited feature to exclude.",
                ),
            ],
            options: [],
        ),
        CommandDefinition(
            name: "include",
            abstract: "Re-include an excluded feature.",
            usages: ["uri include [SOURCE] VERSION PATCHSET FEATURE"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET FEATURE",
                    help: "The excluded feature to include again.",
                ),
            ],
            options: [],
        ),
        CommandDefinition(
            name: "list",
            abstract: "List patchset versions, patchsets, features, or ephemeral workspaces.",
            usages: [
                "uri list [SOURCE] [VERSION] [PATCHSET]",
                "uri list --ephemeral [ID] [--path]",
            ],
            arguments: [
                .init(
                    synopsis: "[SOURCE] [VERSION] [PATCHSET]",
                    help: "The patchset hierarchy to list.",
                ),
            ],
            options: [
                .init(
                    "ephemeral",
                    valueKind: .optionalValue(name: "id"),
                    help: "List ephemeral workspaces, or inspect one ID.",
                ),
                .init(
                    "path",
                    help: "With --ephemeral ID, print only its repository path.",
                ),
            ],
        ),
        CommandDefinition(
            name: "graph",
            abstract: "Print a feature dependency graph.",
            usages: ["uri graph [SOURCE] VERSION PATCHSET [options]"],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET",
                    help: "The patchset whose dependencies should be printed.",
                ),
            ],
            options: [
                .init(
                    "include-dev",
                    help: "Include development dependencies.",
                ),
                .init(
                    "format",
                    valueKind: .value(name: "format", allowedValues: ["tree", "dot"]),
                    help: "Output format: tree or dot. (default: tree)",
                ),
            ],
        ),
        CommandDefinition(
            name: "expand",
            abstract: "Expand one feature and its dependencies into editable branches.",
            usages: [
                "uri expand [SOURCE] VERSION PATCHSET FEATURE [TARGET] [options]",
                "uri expand [TARGET] (--continue | --abort) [--ephemeral [ID]]",
            ],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET FEATURE [TARGET]",
                    help: "Start arguments, or an optional recovery TARGET.",
                ),
            ],
            options: workflowOptions + [
                .init("force", help: "Replace colliding generated branches."),
                .init("no-dev", help: "Exclude development dependencies."),
            ],
        ),
        CommandDefinition(
            name: "apply",
            abstract: "Apply the complete regular dependency graph.",
            usages: [
                "uri apply [SOURCE] VERSION PATCHSET [TARGET] [options]",
                "uri apply [TARGET] (--continue | --abort) [--ephemeral [ID]]",
            ],
            arguments: [
                .init(
                    synopsis: "[SOURCE] VERSION PATCHSET [TARGET]",
                    help: "Start arguments, or an optional recovery TARGET.",
                ),
            ],
            options: workflowOptions,
        ),
        CommandDefinition(
            name: "collapse",
            abstract: "Reconstruct patches from a completed expansion.",
            usages: ["uri collapse [TARGET] [options] [--ephemeral [ID]]"],
            arguments: [
                .init(
                    synopsis: "[TARGET]",
                    help: "Expansion state supplies SOURCE, VERSION, PATCHSET, and FEATURE.",
                ),
            ],
            options: [
                .init("recursive", help: "Collapse dependency features recursively."),
                .init("discard", help: "Discard expansion state without writing patches."),
                ephemeralOption,
            ],
        ),
        CommandDefinition(
            name: "vanish",
            abstract: "Safely remove an ephemeral workspace.",
            usages: ["uri vanish [ID] [--force]"],
            arguments: [
                .init(
                    synopsis: "[ID]",
                    help: "Omit to auto-select one workspace or prompt on a TTY.",
                ),
            ],
            options: [
                .init(
                    "force",
                    help: "Ignore dirty worktree and changed-HEAD checks.",
                ),
            ],
        ),
    ]

    static let rootOptions = [
        colorOption,
        completionOption,
        versionOption,
        helpOption,
    ]

    static let globalCommandOptions = [
        colorOption,
        versionOption,
        helpOption,
    ]

    static func command(named name: String) -> CommandDefinition? {
        commands.first(where: { $0.name == name })
    }

    private static let ephemeralOption =
        OptionDefinition(
            "ephemeral",
            valueKind: .optionalValue(name: "id"),
            help: "Use an ephemeral TARGET, optionally with ID. This selector must be last.",
        )

    private static let workflowOptions = [
        OptionDefinition("continue", help: "Continue after resolving a conflict."),
        OptionDefinition("abort", help: "Abort the operation and restore its starting state."),
        ephemeralOption,
    ]
}
