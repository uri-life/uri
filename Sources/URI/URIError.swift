public enum URIError: Error, Equatable, Sendable {

    case invalidArguments(String)

    case sourceNotFound(String)

    case unsupportedSource(String)

    case remoteSourceIsReadOnly(String)

    case targetRequired

    case dirtyTarget(String)

    case operationAlreadyExists(String)

    case operationNotFound(String)

    case operationModeMismatch(expected: String, actual: String)

    case conflict(String)

    case invalidState(String)

    case invalidEphemeralID(String)

    case ephemeralExists(String)

    case ephemeralNotFound(String)

    case ephemeralInitializing(String)

    case incompleteEphemeral(String)

    case unsafeEphemeral(String)

    case http(status: Int, url: String)

    case fileSystem(String)
}

extension URIError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .invalidArguments(let message),
            .sourceNotFound(let message),
            .unsupportedSource(let message),
            .remoteSourceIsReadOnly(let message),
            .dirtyTarget(let message),
            .operationAlreadyExists(let message),
            .operationNotFound(let message),
            .conflict(let message),
            .invalidState(let message),
            .unsafeEphemeral(let message),
            .fileSystem(let message):
            return message
        case .targetRequired:
            return "No TARGET was provided and the current directory is not inside a Git worktree."
        case .operationModeMismatch(let expected, let actual):
            return "Expected a \(expected) operation, but the saved operation is \(actual)."
        case .invalidEphemeralID(let id):
            return "Invalid ephemeral ID: \(id)"
        case .ephemeralExists(let id):
            return "Ephemeral workspace already exists: \(id)"
        case .ephemeralNotFound(let id):
            return "Ephemeral workspace does not exist: \(id)"
        case .ephemeralInitializing(let id):
            return "Ephemeral workspace is still being initialized: \(id)"
        case .incompleteEphemeral(let id):
            return "Ephemeral workspace is incomplete; use --force to discard it: \(id)"
        case .http(let status, let url):
            return "HTTP \(status) while reading \(url)"
        }
    }
}
