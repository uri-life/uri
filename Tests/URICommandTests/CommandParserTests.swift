import Testing
import URI

@testable
import URICommand

@Suite("Command Parser")
struct CommandParserTests {

    @Test
    func `catalog exposes the complete URI 2_0 command surface`() {
        #expect(
            CommandCatalog.commands.map(\.name) == [
                "init", "add", "remove", "exclude", "include", "list", "graph",
                "expand", "apply", "collapse", "vanish",
            ],
        )
    }

    @Test
    func `every command accepts its agreed primary and recovery syntax`() {
        let examples = [
            ["init", "./patches", "v1", "--upstream=https://example.com/project.git"],
            ["add", "--name", "Feature", "./patches", "v1", "p1", "feature"],
            ["remove", "-f", "./patches", "v1", "p1", "feature"],
            ["exclude", "./patches", "v1", "p1", "feature"],
            ["include", "./patches", "v1", "p1", "feature"],
            ["list", "./patches", "v1", "p1"],
            ["list", "--ephemeral", "peach", "--path"],
            ["graph", "v1", "--include-dev", "p1", "--format=dot"],
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
    func `root actions accept interspersed color and reject conflicts or trailing arguments`() throws {
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
    func `ephemeral selector distinguishes automatic and explicit IDs`() throws {
        let automatic = try parsedExpand(["expand", "v1", "p1", "feature", "--ephemeral"])
        let explicit = try parsedExpand([
            "expand", "v1", "p1", "feature", "--ephemeral=peach",
        ])

        #expect(automatic.ephemeral == CLI.automaticEphemeralID)
        #expect(explicit.ephemeral == "peach")
    }

    @Test
    func `double dash preserves a positional beginning with a hyphen`() throws {
        let invocation = try CommandParser().parse(["vanish", "--", "--peach"])
        guard case .run(.vanish(let command)) = invocation.action else {
            Issue.record("Expected vanish command.")
            return
        }

        #expect(command.id == "--peach")
    }

    @Test
    func `invalid option forms and command modes are usage errors`() {
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
            ["apply", "v1", "p1", "./target", "--ephemeral"],
            ["apply", "v1", "p1", "--ephemeral", "peach", "--color", "never"],
            ["list", "--ephemeral", "--path"],
            ["add", "v1"],
        ]

        for arguments in examples {
            #expect(
                throws: CommandUsageError.self,
                "Accepted: \(arguments.joined(separator: " "))",
            ) {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `every command rejects positional counts outside its accepted modes`() {
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
            ["expand", "v1", "p1"],
            ["expand", "v1", "p1", "feature", "target", "extra"],
            ["apply", "v1"],
            ["apply", "v1", "p1", "target", "extra"],
            ["collapse", "target", "extra"],
            ["vanish", "first", "second"],
        ]

        for arguments in examples {
            #expect(
                throws: CommandUsageError.self,
                "Accepted: \(arguments.joined(separator: " "))",
            ) {
                _ = try CommandParser().parse(arguments)
            }
        }
    }

    @Test
    func `source overloading consumes only a recognized leading source`() {
        #expect(CLI.splitSource(["v1", "p1"]).source == nil)
        #expect(CLI.splitSource(["./patches", "v1", "p1"]).source == "./patches")
        #expect(
            CLI.splitSource(["git+https://example.com/p.git", "v1", "p1"]).rest
                == ["v1", "p1"],
        )
    }

    private func parsedExpand(_ arguments: [String]) throws -> Expand {
        let invocation = try CommandParser().parse(arguments)
        guard case .run(.expand(let command)) = invocation.action else {
            throw URIError.invalidArguments("Expected expand command.")
        }
        return command
    }
}
