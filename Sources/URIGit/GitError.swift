public import Foundation

public enum GitError: Error, Equatable, Sendable {

    case invalidRepository(URL)

    case invalidIdentity(name: String, email: String)

    case invalidReference(String)

    case missingRemote(name: String, repositoryURL: URL)

    case remoteMismatch(
        name: String,
        expected: GitRemoteIdentity,
        actual: GitRemoteIdentity,
    )

    case unresolvableLocalRemote(value: String, relativeTo: URL)

    case malformedOutput(operation: String, output: Data)

    case fileSystem(operation: String, url: URL, reason: String)

    case processLaunch(arguments: [String], reason: String)

    case commandFailed(
        arguments: [String],
        exitStatus: Int32,
        standardOutput: Data,
        standardError: Data,
    )
}

extension GitError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .invalidRepository(let url):
            return "Not a Git worktree: \(url.path)"
        case .invalidIdentity(let name, let email):
            return "Invalid Git identity: \(name) <\(email)>"
        case .invalidReference(let reference):
            return "Invalid Git reference: \(reference)"
        case .missingRemote(let name, let repositoryURL):
            return "Git remote \(name) does not exist in \(repositoryURL.path)"
        case .remoteMismatch(let name, let expected, let actual):
            return "Git remote \(name) does not match: expected \(expected), found \(actual)"
        case .unresolvableLocalRemote(let value, let baseURL):
            return "Could not resolve local Git remote \(value) relative to \(baseURL.path)"
        case .malformedOutput(let operation, _):
            return "Git returned malformed output for \(operation)"
        case .fileSystem(let operation, let url, let reason):
            return "Could not \(operation) \(url.path): \(reason)"
        case .processLaunch(let arguments, let reason):
            return "Could not launch git \(arguments.joined(separator: " ")): \(reason)"
        case .commandFailed(let arguments, let exitStatus, _, let standardError):
            let error = String(decoding: standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = error.isEmpty ? "" : ": \(error)"
            return "git \(arguments.joined(separator: " ")) failed with status \(exitStatus)\(suffix)"
        }
    }
}
