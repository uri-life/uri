import Testing

@testable
import URICommand

@Suite("Completion Generator")
struct CompletionGeneratorTests {

    @Test
    func `all supported shells delegate completion to the hidden action`() {
        for shell in CompletionShell.allCases {
            let script = CompletionGenerator().script(for: shell)
            #expect(!script.isEmpty)
            #expect(script.contains("uri --_complete --"))
            #expect(!script.contains("--path"))
        }
    }

    @Test
    func `shell adapters preserve the current token and request native directories`() {
        let bash = CompletionGenerator().script(for: .bash)
        let zsh = CompletionGenerator().script(for: .zsh)
        let fish = CompletionGenerator().script(for: .fish)

        #expect(bash.contains("COMP_WORDS[@]:1:$COMP_CWORD"))
        #expect(bash.contains("compgen -d"))
        #expect(zsh.contains("(@)words[2,$CURRENT]"))
        #expect(zsh.contains("_path_files -/"))
        #expect(fish.contains("commandline -opc"))
        #expect(fish.contains("commandline -ct"))
        #expect(fish.contains("__fish_complete_directories"))
    }
}
