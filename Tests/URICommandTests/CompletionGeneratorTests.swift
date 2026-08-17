import Testing

@testable
import URICommand

@Suite("Completion Generator")
struct CompletionGeneratorTests {

    @Test
    func `all supported shells receive every command and global option`() {
        for shell in CompletionShell.allCases {
            let script = CompletionGenerator().script(for: shell)
            #expect(!script.isEmpty)
            for command in CommandCatalog.commands {
                #expect(script.contains(command.name))
            }
            for option in CommandCatalog.rootOptions {
                #expect(script.contains(option.longName))
            }
        }
    }

    @Test
    func `completion values include every finite parser choice`() {
        for shell in CompletionShell.allCases {
            let script = CompletionGenerator().script(for: shell)
            for value in ["auto", "always", "never", "tree", "dot", "bash", "zsh", "fish"] {
                #expect(script.contains(value))
            }
        }
    }
}
