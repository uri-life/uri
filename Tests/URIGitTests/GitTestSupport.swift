import Foundation
import URIGit

struct GitTestFixture {

    struct CommandOutput {

        let status: Int32

        let standardOutput: Data

        let standardError: Data
    }

    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "URIGitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        try git([
            "init",
            "--initial-branch=main",
        ])
        try git([
            "config",
            "user.name",
            GitIdentity.test.name,
        ])
        try git([
            "config",
            "user.email",
            GitIdentity.test.email,
        ])
        try write("initial\n", to: "README.md")
        try git([
            "add",
            "README.md",
        ])
        try git([
            "commit",
            "-m",
            "initial",
        ])
    }

    init(cloning sourceURL: URL) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "URIGitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let output = try Self.runGit([
            "clone",
            "--",
            sourceURL.path,
            rootURL.path,
        ])
        guard output.status == 0 else {
            throw GitTestError.commandFailed(output)
        }
        try git([
            "config",
            "user.name",
            GitIdentity.test.name,
        ])
        try git([
            "config",
            "user.email",
            GitIdentity.test.email,
        ])
    }

    func repository() async throws -> GitRepository {
        try await Git().openRepository(at: rootURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func write(
        _ contents: String,
        to path: String,
    ) throws {
        try write(Data(contents.utf8), to: path)
    }

    func write(
        _ contents: Data,
        to path: String,
    ) throws {
        let url = rootURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try contents.write(to: url)
    }

    @discardableResult
    func commit(
        _ contents: String,
        to path: String,
        message: String,
    ) throws -> String {
        try write(contents, to: path)
        try git([
            "add",
            "--",
            path,
        ])
        try git([
            "commit",
            "-m",
            message,
        ])
        return try gitString([
            "rev-parse",
            "HEAD",
        ])
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> CommandOutput {
        let output = try Self.runGit(
            [
                "-C",
                rootURL.path,
            ] + arguments,
        )
        guard output.status == 0 else {
            throw GitTestError.commandFailed(output)
        }
        return output
    }

    func gitString(_ arguments: [String]) throws -> String {
        let output = try git(arguments)
        guard let value = String(data: output.standardOutput, encoding: .utf8) else {
            throw GitTestError.invalidUTF8
        }
        return value.trimmingCharacters(in: .newlines)
    }

    static func runGit(_ arguments: [String]) throws -> CommandOutput {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_PAGER": "cat",
                "GIT_TERMINAL_PROMPT": "0",
            ],
            uniquingKeysWith: { _, override in override },
        )
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return .init(
            status: process.terminationStatus,
            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            standardError: standardError.fileHandleForReading.readDataToEndOfFile(),
        )
    }
}

enum GitTestError: Error {

    case commandFailed(GitTestFixture.CommandOutput)

    case invalidUTF8
}

func executableTestScript(_ contents: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "GitProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
    let scriptURL = directoryURL.appending(path: "git-test", directoryHint: .notDirectory)
    try Data(contents.utf8).write(to: scriptURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: scriptURL.path,
    )
    return scriptURL
}

extension GitIdentity {

    static var test: GitIdentity {
        try! .init(name: "Test", email: "test@example.com")
    }
}
