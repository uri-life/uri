struct CommandSyntaxRenderer {

    private static let commandNames =
        Set(CommandCatalog.commands.map(\.name) + ["help"])

    let terminal: Terminal

    let stream: Terminal.Stream

    func render(_ syntax: String) -> String {
        var result = ""
        var index = syntax.startIndex
        var isValuePlaceholder = false

        while index < syntax.endIndex {
            let character = syntax[index]
            if character == "<" {
                isValuePlaceholder = true
                result.append(character)
                index = syntax.index(after: index)
            }
            else if character == ">" {
                isValuePlaceholder = false
                result.append(character)
                index = syntax.index(after: index)
            }
            else if character == "-" {
                let end = syntax[index...].firstIndex(where: { !isOptionCharacter($0) })
                    ?? syntax.endIndex
                result += terminal.styled(
                    String(syntax[index..<end]),
                    as: .cyan,
                    to: stream,
                )
                index = end
            }
            else if isWordCharacter(character) {
                let end = syntax[index...].firstIndex(where: { !isWordCharacter($0) })
                    ?? syntax.endIndex
                let word = syntax[index..<end]
                if isValuePlaceholder || isPositionalPlaceholder(word) {
                    result += terminal.styled(String(word), as: .yellow, to: stream)
                }
                else if word == "uri" {
                    result += terminal.styled(String(word), as: .bold, to: stream)
                }
                else if Self.commandNames.contains(String(word)) {
                    result += terminal.styled(String(word), as: .green, to: stream)
                }
                else {
                    result += String(word)
                }
                index = end
            }
            else {
                result.append(character)
                index = syntax.index(after: index)
            }
        }

        return result
    }

    private func isOptionCharacter(_ character: Character) -> Bool {
        isWordCharacter(character) || character == "-"
    }

    private func isPositionalPlaceholder(_ word: Substring) -> Bool {
        word.contains(where: \.isLetter)
            && word.allSatisfy({ !$0.isLetter || $0.isUppercase })
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
