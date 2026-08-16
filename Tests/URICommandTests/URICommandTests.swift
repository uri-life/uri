import ArgumentParser
import Testing
import URI

@testable import URICommand

@Suite("URI Command")
struct URICommandTests {

    @Test
    func `root command exposes the complete 2_0 command surface`() {
        let names = URICommand.configuration.subcommands.map({ type in type._commandName })
        #expect(
            names == [
                "init", "add", "remove", "exclude", "include", "list", "graph",
                "expand", "apply", "collapse", "vanish",
            ],
        )
    }

    @Test
    func `ephemeral target selector must be the final command element`() {
        #expect(throws: Never.self) {
            try CLI.preflightEphemeralPosition(arguments: ["apply", "v1", "p1", "--ephemeral"])
        }
        #expect(throws: Never.self) {
            try CLI.preflightEphemeralPosition(
                arguments: ["collapse", "--discard", "--ephemeral", "peach"],
            )
        }
        #expect(throws: URIError.self) {
            try CLI.preflightEphemeralPosition(
                arguments: ["apply", "--ephemeral", "peach", "v1", "p1"],
            )
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

    @Test
    func `ephemeral option accepts either an automatic or explicit final ID`() async throws {
        let automatic = try #require(
            try await URICommand.asyncParseAsRoot([
                "apply", "v1", "p1", "--ephemeral",
            ]) as? Apply,
        )
        let explicit = try #require(
            try await URICommand.asyncParseAsRoot([
                "expand", "v1", "p1", "feature", "--ephemeral", "peach",
            ]) as? Expand,
        )
        #expect(automatic.ephemeralTarget.ephemeral == CLI.automaticEphemeralID)
        #expect(explicit.ephemeralTarget.ephemeral == "peach")
    }

    @Test
    func `ArgumentParser supplies all three official completion generators`() {
        for shell in [CompletionShell.bash, .zsh, .fish] {
            let script = URICommand.completionScript(for: shell)
            #expect(!script.isEmpty)
            #expect(script.contains("uri"))
        }
    }
}
