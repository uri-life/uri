import URI
import URIPatchset

struct Diff {

    let values: [String]

    let from: [String]

    let to: [String]

    private let compare:
        (PatchsetSource, FeatureDiffOperand, FeatureDiffOperand) async throws -> String

    init(
        values: [String],
        from: [String],
        to: [String],
        compare: @escaping
            (PatchsetSource, FeatureDiffOperand, FeatureDiffOperand) async throws -> String = {
                try await FeatureDiffer().compare(source: $0, from: $1, to: $2)
            },
    ) {
        self.values = values
        self.from = from
        self.to = to
        self.compare = compare
    }

    func run(terminal: Terminal) async throws {
        let (source, arguments) = try CLI.sourceAndArguments(values)
        guard arguments.isEmpty else {
            throw URIError.invalidArguments("diff accepts only an optional SOURCE positional argument.")
        }
        let output = try await compare(
            source,
            try operand(from, option: "--from"),
            try operand(to, option: "--to"),
        )
        render(output, terminal: terminal)
    }

    private func operand(
        _ values: [String],
        option: String,
    ) throws -> FeatureDiffOperand {
        guard values.count == 3 else {
            throw URIError.invalidArguments("\(option) requires VERSION PATCHSET FEATURE.")
        }
        return try .init(
            reference: .init(
                upstreamVersion: values[0],
                patchsetVersion: values[1],
            ),
            featureID: values[2],
        )
    }

    private func render(
        _ output: String,
        terminal: Terminal,
    ) {
        guard !output.isEmpty else {
            return
        }
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for line in lines {
            let value = String(line)
            let rendered: String
            if value.hasPrefix("@@") {
                rendered = terminal.styled(value, as: .cyan, to: .standardOutput)
            }
            else if value.hasPrefix("-") {
                rendered = terminal.styled(value, as: .red, to: .standardOutput)
            }
            else if value.hasPrefix("+") {
                rendered = terminal.styled(value, as: .green, to: .standardOutput)
            }
            else {
                rendered = value
            }
            terminal.output(rendered)
        }
    }
}
