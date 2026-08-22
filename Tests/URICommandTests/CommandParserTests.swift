import Testing

@testable
import URICommand

@Suite("Command Parser")
struct CommandParserTests {

    @Test
    func `catalog exposes the complete URI 2_0 command surface`() {
        #expect(
            CommandCatalog.commands.map(\.name) == [
                "init", "add", "remove", "exclude", "include", "list", "graph",
                "diff", "expand", "apply", "collapse", "vanish",
            ],
        )
    }

    @Test
    func `every command accepts its primary and recovery forms`() {
        let examples = [
            ["init", "./patches", "v1", "--upstream=https://example.com/project.git"],
            ["add", "--name", "Feature", "./patches", "v1", "p1", "feature"],
            ["remove", "-f", "./patches", "v1", "p1", "feature"],
            ["exclude", "./patches", "v1", "p1", "feature"],
            ["include", "./patches", "v1", "p1", "feature"],
            ["list", "./patches", "v1", "p1"],
            ["list", "--ephemeral"],
            ["graph", "v1", "--include-dev", "p1", "--format=dot"],
            [
                "diff", "./patches",
                "--from", "v1", "p1", "first",
                "--to", "v2", "p2", "second",
            ],
            ["expand", "--no-dev", "v1", "p1", "feature", "./target"],
            ["expand", "./target", "--continue"],
            ["expand", "v1", "p1", "feature", "--ephemeral"],
            ["apply", "v1", "p1", "./target"],
            ["apply", "--abort", "./target"],
            ["apply", "v1", "p1", "--ephemeral", "peach"],
            ["collapse", "--discard", "--ephemeral", "peach"],
            ["vanish", "peach", "--force"],
        ]

        for arguments in examples {
            #expect(throws: Never.self, "Rejected: \(arguments.joined(separator: " "))") {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `diff requires complete from and to feature operands in either option order`() throws {
        let forward = try parsedDiff([
            "diff", "./patches",
            "--from", "v1", "p1", "first",
            "--to", "v2", "p2", "second",
        ])
        let reversed = try parsedDiff([
            "diff",
            "--to", "v2", "p2", "second",
            "--from", "v1", "p1", "first",
        ])

        #expect(forward.values == ["./patches"])
        #expect(forward.from == ["v1", "p1", "first"])
        #expect(forward.to == ["v2", "p2", "second"])
        #expect(reversed.values.isEmpty)
        #expect(reversed.from == forward.from)
        #expect(reversed.to == forward.to)

        let invalidExamples = [
            ["diff", "--from", "v1", "p1", "--to", "v2", "p2", "second"],
            ["diff", "--from", "v1", "p1", "first"],
            ["diff", "--to", "v2", "p2", "second"],
            [
                "diff", "--from=v1", "p1", "first",
                "--to", "v2", "p2", "second",
            ],
            [
                "diff", "--from", "v1", "p1", "first",
                "--from", "v1", "p1", "first",
                "--to", "v2", "p2", "second",
            ],
        ]
        for arguments in invalidExamples {
            #expect(throws: CommandUsageError.self) {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `apply development mode defaults to disabled and is position independent for new operations`()
        throws
    {
        let regular = try parsedApply(["apply", "v1", "p1", "./target"])
        let leading = try parsedApply(["apply", "--dev", "v1", "p1", "./target"])
        let trailing = try parsedApply(["apply", "v1", "p1", "./target", "--dev"])
        let ephemeral = try parsedApply([
            "apply", "v1", "p1", "--ephemeral", "peach", "--dev",
        ])

        #expect(!regular.includeDevelopmentDependencies)
        #expect(leading.includeDevelopmentDependencies)
        #expect(trailing.includeDevelopmentDependencies)
        #expect(ephemeral.includeDevelopmentDependencies)
        #expect(ephemeral.target == .ephemeral(id: "peach"))
    }

    @Test
    func `apply development mode is rejected during continue and abort`() {
        let examples = [
            ["apply", "--continue", "./target", "--dev"],
            ["apply", "--dev", "--abort", "--ephemeral", "peach"],
        ]

        for arguments in examples {
            #expect(
                throws: CommandUsageError.self,
                "Accepted: \(arguments.joined(separator: " "))",
            )
            {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `workflow TARGET distinguishes omitted path automatic named and equals forms`() throws {
        #expect(try parsedExpand(["expand", "v1", "p1", "feature"]).target == .omitted)
        #expect(
            try parsedExpand(["expand", "v1", "p1", "feature", "./target"]).target
                == .path("./target"),
        )
        #expect(
            try parsedExpand(["expand", "v1", "p1", "feature", "--ephemeral"]).target
                == .ephemeral(id: nil),
        )
        #expect(
            try parsedExpand([
                "expand", "v1", "p1", "feature", "--ephemeral", "peach",
            ]).target == .ephemeral(id: "peach"),
        )
        #expect(
            try parsedExpand([
                "expand", "v1", "p1", "feature", "--ephemeral=plum",
            ]).target == .ephemeral(id: "plum"),
        )
    }

    @Test
    func `workflow options may precede or follow an ephemeral TARGET`() throws {
        let applyTargetFirst = try parsedApply([
            "apply", "--ephemeral", "peach", "--continue",
        ])
        let applyOptionFirst = try parsedApply([
            "apply", "--continue", "--ephemeral", "peach",
        ])
        let expand = try parsedExpand([
            "expand", "v1", "p1", "feature", "--ephemeral", "peach", "--no-dev",
        ])
        let collapse = try parsedCollapse([
            "collapse", "--ephemeral", "peach", "--discard",
        ])

        #expect(applyTargetFirst.target == .ephemeral(id: "peach"))
        #expect(applyTargetFirst.continueOperation)
        #expect(applyOptionFirst.target == .ephemeral(id: "peach"))
        #expect(applyOptionFirst.continueOperation)
        #expect(expand.target == .ephemeral(id: "peach"))
        #expect(expand.noDevelopmentDependencies)
        #expect(collapse.target == .ephemeral(id: "peach"))
        #expect(collapse.discard)
    }

    @Test
    func `double dash makes ephemeral spelling a literal path TARGET`() throws {
        let apply = try parsedApply(["apply", "v1", "p1", "--", "--ephemeral"])
        let collapse = try parsedCollapse(["collapse", "--", "--ephemeral"])
        let invocation = try CommandParser().parse(["vanish", "--", "--peach"])
        guard case .run(.vanish(let vanish)) = invocation.action else {
            Issue.record("Expected vanish command.")
            return
        }

        #expect(apply.target == .path("--ephemeral"))
        #expect(collapse.target == .path("--ephemeral"))
        #expect(vanish.id == "--peach")
    }

    @Test
    func `ephemeral TARGET rejects ordering and duplication that cannot fill its positional slot`()
    {
        let examples = [
            ["apply", "--ephemeral", "peach", "v1", "p1"],
            ["expand", "--ephemeral=peach", "v1", "p1", "feature"],
            ["apply", "v1", "p1", "./target", "--ephemeral=peach"],
            ["apply", "v1", "p1", "--ephemeral=peach", "./target"],
            ["apply", "v1", "p1", "first", "second"],
            ["collapse", "./target", "--ephemeral=peach"],
            ["collapse", "--ephemeral=peach", "--"],
            ["apply", "v1", "p1", "--ephemeral=peach", "--", "trailing"],
            ["apply", "v1", "p1", "--ephemeral=123-invalid"],
        ]

        for arguments in examples {
            #expect(throws: CommandUsageError.self, "Accepted: \(arguments.joined(separator: " "))")
            {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `list ephemeral accepts an optional general SOURCE in either option order`() throws {
        let invocation = try CommandParser().parse(["list", "--ephemeral"])
        guard case .run(.list(let command)) = invocation.action else {
            Issue.record("Expected list command.")
            return
        }
        #expect(command.mode == .ephemeral(source: nil))

        let examples = [
            (["list", "--ephemeral", "."], "."),
            (["list", "--ephemeral", "~"], "~"),
            (["list", "--ephemeral", "nested/patches"], "nested/patches"),
            (["list", "--ephemeral", "./patches"], "./patches"),
            (["list", "./patches", "--ephemeral"], "./patches"),
            (["list", "--ephemeral", "https://example.com/patches/"], "https://example.com/patches/"),
            (["list", "--ephemeral", "git+https://example.com/patches.git"], "git+https://example.com/patches.git"),
        ]
        for (arguments, source) in examples {
            let invocation = try CommandParser().parse(arguments)
            guard case .run(.list(let command)) = invocation.action else {
                Issue.record("Expected list command.")
                continue
            }
            #expect(command.mode == .ephemeral(source: source))
        }

        let invalidExamples = [
            ["list", "--ephemeral", "peach"],
            ["list", "--ephemeral", "--", "peach"],
            ["list", "--ephemeral=peach"],
            ["list", "--ephemeral", "./patches", "extra"],
            ["list", "--path"],
            ["list", "v1", "p1", "--ephemeral"],
        ]
        for arguments in invalidExamples {
            #expect(throws: CommandUsageError.self) {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `hierarchy list preserves its positional values`() throws {
        let invocation = try CommandParser().parse(["list", "./patches", "v1", "p1"])
        guard case .run(.list(let command)) = invocation.action else {
            Issue.record("Expected list command.")
            return
        }
        #expect(command.mode == .hierarchy(["./patches", "v1", "p1"]))
    }

    @Test
    func `global color is accepted before or within a command`() throws {
        let before = try CommandParser().parse([
            "--color", "always", "apply", "v1", "p1",
        ])
        let within = try CommandParser().parse([
            "graph", "v1", "--color=never", "p1",
        ])

        #expect(before.colorMode == .always)
        #expect(within.colorMode == .never)
    }

    @Test
    func `root actions accept interspersed color and reject conflicts or trailing arguments`()
        throws
    {
        let version = try CommandParser().parse(["--version", "--color=always"])
        let completion = try CommandParser().parse([
            "--generate-completion-script", "fish", "--color", "never",
        ])
        let invalidExamples = [
            ["--version", "--version"],
            ["--help", "--unknown"],
            ["--version", "apply", "v1", "p1"],
            ["--generate-completion-script", "bash", "extra"],
            ["--help", "--version"],
        ]

        #expect(version.colorMode == .always)
        #expect(completion.colorMode == .never)
        for arguments in invalidExamples {
            #expect(throws: CommandUsageError.self) {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `unknown duplicate missing and mutually exclusive options are usage errors`() {
        let examples = [
            ["unknown"],
            ["apply", "v1", "p1", "--unknown"],
            ["apply", "v1", "p1", "--color"],
            ["apply", "v1", "p1", "--color", "sometimes"],
            ["graph", "v1", "p1", "--format", "json"],
            ["remove", "v1", "--force", "--force"],
            ["apply", "--continue", "--abort"],
            ["expand", "--continue", "--force"],
            ["collapse", "--recursive", "--discard"],
            ["add", "v1"],
        ]

        for arguments in examples {
            #expect(throws: CommandUsageError.self, "Accepted: \(arguments.joined(separator: " "))")
            {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `every command rejects positional counts outside its forms`() {
        let examples = [
            ["init", "version", "extra"],
            ["add", "v1"],
            ["add", "v1", "p1", "feature", "extra"],
            ["remove"],
            ["remove", "v1", "p1", "feature", "extra"],
            ["exclude", "v1", "p1"],
            ["exclude", "v1", "p1", "feature", "extra"],
            ["include", "v1", "p1"],
            ["include", "v1", "p1", "feature", "extra"],
            ["list", "v1", "p1", "extra"],
            ["graph", "v1"],
            ["graph", "v1", "p1", "extra"],
            [
                "diff", "extra",
                "--from", "v1", "p1", "first",
                "--to", "v2", "p2", "second",
            ],
            ["expand", "v1", "p1"],
            ["expand", "v1", "p1", "feature", "target", "extra"],
            ["apply", "v1"],
            ["apply", "v1", "p1", "target", "extra"],
            ["collapse", "target", "extra"],
            ["vanish", "first", "second"],
        ]

        for arguments in examples {
            #expect(throws: CommandUsageError.self, "Accepted: \(arguments.joined(separator: " "))")
            {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `source overloading consumes dot tilde and slash-bearing leading sources`() {
        #expect(CLI.splitSource(["v1", "p1"]).source == nil)
        for source in [".", "~", "/", "nested/path", "path/", "./patches"] {
            #expect(CLI.splitSource([source, "v1", "p1"]).source == source)
        }
        #expect(
            CLI.splitSource(["git+https://example.com/p.git", "v1", "p1"]).rest
                == ["v1", "p1"],
        )
    }

    private func parsedExpand(_ arguments: [String]) throws -> Expand {
        let invocation = try CommandParser().parse(arguments)
        guard case .run(.expand(let command)) = invocation.action else {
            throw CommandUsageError(message: "Expected expand command.", commandName: "expand")
        }
        return command
    }

    private func parsedDiff(_ arguments: [String]) throws -> Diff {
        let invocation = try CommandParser().parse(arguments)
        guard case .run(.diff(let command)) = invocation.action else {
            throw CommandUsageError(message: "Expected diff command.", commandName: "diff")
        }
        return command
    }

    private func parsedApply(_ arguments: [String]) throws -> Apply {
        let invocation = try CommandParser().parse(arguments)
        guard case .run(.apply(let command)) = invocation.action else {
            throw CommandUsageError(message: "Expected apply command.", commandName: "apply")
        }
        return command
    }

    private func parsedCollapse(_ arguments: [String]) throws -> Collapse {
        let invocation = try CommandParser().parse(arguments)
        guard case .run(.collapse(let command)) = invocation.action else {
            throw CommandUsageError(message: "Expected collapse command.", commandName: "collapse")
        }
        return command
    }
}
