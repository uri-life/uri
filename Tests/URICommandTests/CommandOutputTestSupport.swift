@testable
import URICommand

final class CommandOutputCapture {

    var standardOutput = ""

    var standardError = ""

    var input: String?

    func terminal(
        colorMode: ColorMode,
        environment: [String: String] = [:],
        standardInputIsTTY: Bool = false,
        standardOutputIsTTY: Bool = false,
        standardErrorIsTTY: Bool = false,
    ) -> Terminal {
        Terminal(
            colorMode: colorMode,
            environment: environment,
            standardInputIsTTY: standardInputIsTTY,
            standardOutputIsTTY: standardOutputIsTTY,
            standardErrorIsTTY: standardErrorIsTTY,
            writeStandardOutput: { [self] in
                standardOutput += $0
            },
            writeStandardError: { [self] in
                standardError += $0
            },
            readStandardInput: { [self] in
                input
            },
        )
    }
}
