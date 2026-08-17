import Testing

@testable
import URICommand

@Suite("Command Grammar")
struct CommandGrammarTests {

    @Test
    func `generated usages exactly match the public CLI contract`() {
        let expected = [
            "uri init [SOURCE] [VERSION]",
            "uri add [SOURCE] VERSION PATCHSET [FEATURE]",
            "uri remove [SOURCE] VERSION [PATCHSET] [FEATURE]",
            "uri exclude [SOURCE] VERSION PATCHSET FEATURE",
            "uri include [SOURCE] VERSION PATCHSET FEATURE",
            "uri list [SOURCE] [VERSION] [PATCHSET]",
            "uri list --ephemeral",
            "uri graph [SOURCE] VERSION PATCHSET",
            "uri expand [SOURCE] VERSION PATCHSET FEATURE [TARGET]",
            "uri expand [TARGET] (--continue|--abort)",
            "uri apply [SOURCE] VERSION PATCHSET [TARGET]",
            "uri apply [TARGET] (--continue|--abort)",
            "uri collapse [TARGET]",
            "uri vanish [ID]",
        ]

        #expect(CommandCatalog.commands.flatMap(UsageRenderer().render) == expected)
    }

    @Test
    func `workflow ephemeral spelling comes from TARGET rather than option definitions`() {
        for name in ["expand", "apply", "collapse"] {
            let command = CommandCatalog.command(named: name)!
            #expect(command.ephemeralTarget?.synopsis == "--ephemeral [ID]")
            #expect(!command.options.contains(where: { $0.longName == "ephemeral" }))
            #expect(
                command.arguments.contains(where: { argument in
                    guard argument.id == .target,
                        case .target(let target) = argument.valueKind
                    else {
                        return false
                    }
                    return target.ephemeral?.longName == "ephemeral"
                }),
            )
        }
    }

    @Test
    func `list ephemeral spelling is a value-less option without a TARGET`() {
        let command = CommandCatalog.command(named: "list")!
        let option = command.options.first(where: { $0.id == .listEphemeral })

        #expect(option?.valueKind == .flag)
        #expect(command.ephemeralTarget == nil)
        #expect(!command.arguments.contains(where: { $0.id == .target }))
    }
}
