import Foundation

internal enum GitStandardInput: Sendable {

    case data(Data)

    case file(URL)
}

internal struct GitCommandOutput: Sendable {

    internal let exitStatus: Int32

    internal let standardOutput: Data

    internal let standardError: Data
}

internal actor GitProcess {

    private struct RunningProcess {

        let id: UUID

        let process: Process
    }

    private let executableURL: URL

    private let prefixArguments: [String]

    private var isAvailable: Bool = true

    private var waiters: [CheckedContinuation<Void, Never>] = []

    private var running: RunningProcess?

    internal init(
        executableURL: URL = URL(filePath: "/usr/bin/env"),
        prefixArguments: [String] = ["git"],
    ) {
        self.executableURL = executableURL
        self.prefixArguments = prefixArguments
    }

    internal func run(
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        input: GitStandardInput? = nil,
        environment: [String: String] = [:],
    ) async throws -> GitCommandOutput {
        await acquire()
        defer { release() }
        try Task.checkCancellation()

        let capture = try Capture(input: input)
        defer { capture.remove() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = prefixArguments + arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_ASKPASS": "/bin/false",
                "GIT_PAGER": "cat",
                "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
                "GIT_TERMINAL_PROMPT": "0",
                "SSH_ASKPASS": "/bin/false",
            ].merging(environment, uniquingKeysWith: { _, override in override }),
            uniquingKeysWith: { _, override in override },
        )
        process.standardInput = capture.standardInput
        process.standardOutput = capture.standardOutput
        process.standardError = capture.standardError

        let id = UUID()
        running = .init(id: id, process: process)
        defer { running = nil }

        let exitStatus = try await withTaskCancellationHandler(
            operation: {
                try await launchAndWait(process, arguments: arguments)
            },
            onCancel: {
                Task {
                    await self.terminateProcess(id: id)
                }
            },
        )
        capture.close()
        try Task.checkCancellation()

        return try .init(
            exitStatus: exitStatus,
            standardOutput: Data(contentsOf: capture.standardOutputURL),
            standardError: Data(contentsOf: capture.standardErrorURL),
        )
    }

    private func acquire() async {
        if isAvailable {
            isAvailable = false
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isAvailable = true
        }
        else {
            waiters.removeFirst().resume()
        }
    }

    private func launchAndWait(
        _ process: Process,
        arguments: [String],
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.resume(returning: terminatedProcess.terminationStatus)
            }

            do {
                try process.run()
            }
            catch {
                process.terminationHandler = nil
                continuation.resume(
                    throwing: GitError.processLaunch(
                        arguments: arguments,
                        reason: String(describing: error),
                    ),
                )
            }
        }
    }

    private func terminateProcess(id: UUID) {
        guard running?.id == id, running?.process.isRunning == true else {
            return
        }

        running?.process.terminate()
    }
}

private final class Capture {

    let directoryURL: URL

    let standardOutputURL: URL

    let standardErrorURL: URL

    let standardInput: FileHandle?

    let standardOutput: FileHandle

    let standardError: FileHandle

    init(input: GitStandardInput?) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "URIGit-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
            )
            let standardOutputURL = directoryURL.appending(path: "stdout")
            let standardErrorURL = directoryURL.appending(path: "stderr")
            try Data().write(to: standardOutputURL)
            try Data().write(to: standardErrorURL)

            self.directoryURL = directoryURL
            self.standardOutputURL = standardOutputURL
            self.standardErrorURL = standardErrorURL
            self.standardOutput = try FileHandle(forWritingTo: standardOutputURL)
            self.standardError = try FileHandle(forWritingTo: standardErrorURL)

            switch input {
            case .data(let data):
                let standardInputURL = directoryURL.appending(path: "stdin")
                try data.write(to: standardInputURL)
                self.standardInput = try FileHandle(forReadingFrom: standardInputURL)
            case .file(let url):
                self.standardInput = try FileHandle(forReadingFrom: url)
            case nil:
                self.standardInput = nil
            }
        }
        catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw GitError.fileSystem(
                operation: "create Git process capture at",
                url: directoryURL,
                reason: String(describing: error),
            )
        }
    }

    func close() {
        try? standardInput?.close()
        try? standardOutput.close()
        try? standardError.close()
    }

    func remove() {
        close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
