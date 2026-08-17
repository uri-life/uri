import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum ColorMode: String, CaseIterable, Sendable {

    case auto

    case always

    case never
}

enum TerminalStyle: String {

    case bold = "1"

    case cyan = "36"

    case green = "32"

    case yellow = "33"

    case red = "31"
}

struct Terminal {

    enum Stream {

        case standardOutput

        case standardError
    }

    let colorMode: ColorMode

    let standardInputIsTTY: Bool

    private let environment: [String: String]

    private let standardOutputIsTTY: Bool

    private let standardErrorIsTTY: Bool

    private let writeStandardOutput: (String) -> Void

    private let writeStandardError: (String) -> Void

    private let readStandardInput: () -> String?

    static func standard(colorMode: ColorMode) -> Terminal {
        .init(
            colorMode: colorMode,
            environment: ProcessInfo.processInfo.environment,
            standardInputIsTTY: isatty(STDIN_FILENO) == 1,
            standardOutputIsTTY: isatty(STDOUT_FILENO) == 1,
            standardErrorIsTTY: isatty(STDERR_FILENO) == 1,
            writeStandardOutput: { value in
                FileHandle.standardOutput.write(Data(value.utf8))
            },
            writeStandardError: { value in
                FileHandle.standardError.write(Data(value.utf8))
            },
            readStandardInput: {
                readLine()
            },
        )
    }

    init(
        colorMode: ColorMode,
        environment: [String: String],
        standardInputIsTTY: Bool,
        standardOutputIsTTY: Bool,
        standardErrorIsTTY: Bool,
        writeStandardOutput: @escaping (String) -> Void,
        writeStandardError: @escaping (String) -> Void,
        readStandardInput: @escaping () -> String?,
    ) {
        self.colorMode = colorMode
        self.environment = environment
        self.standardInputIsTTY = standardInputIsTTY
        self.standardOutputIsTTY = standardOutputIsTTY
        self.standardErrorIsTTY = standardErrorIsTTY
        self.writeStandardOutput = writeStandardOutput
        self.writeStandardError = writeStandardError
        self.readStandardInput = readStandardInput
    }

    func styled(
        _ value: String,
        as style: TerminalStyle,
        to stream: Stream,
        machineReadable: Bool = false,
    ) -> String {
        guard !machineReadable, shouldColor(stream) else {
            return value
        }
        return "\u{001B}[\(style.rawValue)m\(value)\u{001B}[0m"
    }

    func output(
        _ value: String,
        terminator: String = "\n",
        machineReadable: Bool = false,
    ) {
        write(
            value + terminator,
            to: .standardOutput,
            machineReadable: machineReadable,
        )
    }

    func errorOutput(
        _ value: String,
        terminator: String = "\n",
    ) {
        write(value + terminator, to: .standardError)
    }

    func success(_ label: String, value: String? = nil) {
        let styledLabel = styled(label, as: .green, to: .standardOutput)
        if let value {
            output("\(styledLabel): \(value)")
        }
        else {
            output(styledLabel)
        }
    }

    func warning(_ value: String) {
        errorOutput(styled(value, as: .yellow, to: .standardError))
    }

    func diagnostic(_ value: String) {
        let label = styled("error:", as: .red, to: .standardError)
        errorOutput("\(label) \(value)")
    }

    func prompt(_ value: String) -> String? {
        errorOutput(
            styled(value, as: .yellow, to: .standardError),
            terminator: "",
        )
        return readStandardInput()
    }

    private func shouldColor(_ stream: Stream) -> Bool {
        switch colorMode {
        case .always:
            return true
        case .never:
            return false
        case .auto:
            guard environment["NO_COLOR"] == nil,
                environment["TERM"]?.lowercased() != "dumb"
            else {
                return false
            }
            switch stream {
            case .standardOutput:
                return standardOutputIsTTY
            case .standardError:
                return standardErrorIsTTY
            }
        }
    }

    private func write(
        _ value: String,
        to stream: Stream,
        machineReadable: Bool = false,
    ) {
        let output = machineReadable ? stripANSI(value) : value
        switch stream {
        case .standardOutput:
            writeStandardOutput(output)
        case .standardError:
            writeStandardError(output)
        }
    }

    private func stripANSI(_ value: String) -> String {
        var result = value
        for style in [TerminalStyle.bold, .cyan, .green, .yellow, .red] {
            result = result.replacingOccurrences(of: "\u{001B}[\(style.rawValue)m", with: "")
        }
        return result.replacingOccurrences(of: "\u{001B}[0m", with: "")
    }
}
