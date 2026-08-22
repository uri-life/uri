public import Foundation

public struct Git: Sendable {

    private let process: GitProcess

    public init() {
        process = .init()
    }

    internal init(process: GitProcess) {
        self.process = process
    }

    /// Opens the worktree containing `url` and returns its canonical root.
    public func openRepository(at url: URL) async throws -> GitRepository {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        guard
            (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            throw GitError.invalidRepository(candidate)
        }

        let arguments = [
            "-C",
            candidate.path,
            "rev-parse",
            "--show-toplevel",
        ]
        let output = try await process.run(arguments: arguments)
        guard output.exitStatus == 0 else {
            throw GitError.invalidRepository(candidate)
        }
        guard
            let root = String(data: output.standardOutput, encoding: .utf8)
                .map({ $0.trimmingCharacters(in: .newlines) }),
            !root.isEmpty
        else {
            throw GitError.malformedOutput(
                operation: "resolve repository root",
                output: output.standardOutput,
            )
        }

        return .init(
            rootURL: URL(filePath: root, directoryHint: .isDirectory)
                .standardizedFileURL.resolvingSymlinksInPath(),
            process: process,
        )
    }

    /// Clones `remote` into the exact destination and preserves a failed clone for inspection.
    public func cloneRepository(
        from remote: String,
        to destinationURL: URL,
        relativeTo baseURL: URL? = nil,
        options: GitCloneOptions = .init(),
    ) async throws -> GitRepository {
        guard !remote.isEmpty, !remote.contains(where: { $0.isNewline }) else {
            throw GitError.invalidReference(remote)
        }

        let destinationURL = destinationURL.standardizedFileURL
        var arguments = ["clone"]
        if let branch = options.branch {
            guard !branch.isEmpty, !branch.hasPrefix("-"), !branch.contains(where: { $0.isNewline }) else {
                throw GitError.invalidReference(branch)
            }
            arguments += ["--branch", branch]
        }
        if let depth = options.depth {
            guard depth > 0 else {
                throw GitError.invalidReference(String(depth))
            }
            arguments += ["--depth", String(depth)]
        }
        if options.singleBranch {
            arguments.append("--single-branch")
        }
        if options.noCheckout {
            arguments.append("--no-checkout")
        }
        if options.shared {
            arguments.append("--shared")
        }
        arguments += ["--", remote, destinationURL.path]
        let output = try await process.run(
            arguments: arguments,
            currentDirectoryURL: baseURL,
        )
        guard output.exitStatus == 0 else {
            throw GitError.commandFailed(
                arguments: arguments,
                exitStatus: output.exitStatus,
                standardOutput: output.standardOutput,
                standardError: output.standardError,
            )
        }

        return try await openRepository(at: destinationURL)
    }

    /// Returns a unified no-index diff, treating Git's difference status as success.
    public func diffFiles(
        _ firstURL: URL,
        _ secondURL: URL,
    ) async throws -> Data {
        let arguments = [
            "diff",
            "--no-index",
            "--no-color",
            "--no-ext-diff",
            "--no-textconv",
            "--no-renames",
            "--unified=3",
            "--",
            firstURL.path,
            secondURL.path,
        ]
        let output = try await process.run(arguments: arguments)
        switch output.exitStatus {
        case 0:
            return Data()
        case 1:
            return output.standardOutput
        default:
            throw GitError.commandFailed(
                arguments: arguments,
                exitStatus: output.exitStatus,
                standardOutput: output.standardOutput,
                standardError: output.standardError,
            )
        }
    }
}
