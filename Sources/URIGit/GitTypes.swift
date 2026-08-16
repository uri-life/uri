public struct GitIdentity: Equatable, Hashable, Sendable {

    public let name: String

    public let email: String

    public init(
        name: String,
        email: String,
    ) throws {
        guard
            !name.isEmpty,
            !email.isEmpty,
            !name.contains(where: { $0.isNewline }),
            !email.contains(where: { $0.isNewline })
        else {
            throw GitError.invalidIdentity(name: name, email: email)
        }

        self.name = name
        self.email = email
    }
}

public struct GitCommit: Equatable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) throws {
        guard
            [40, 64].contains(rawValue.utf8.count),
            rawValue.utf8.allSatisfy({ byte in
                (48...57).contains(byte)
                    || (65...70).contains(byte)
                    || (97...102).contains(byte)
            })
        else {
            throw GitError.invalidReference(rawValue)
        }

        self.rawValue = rawValue.lowercased()
    }
}

extension GitCommit: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}

public struct GitReference: Equatable, Hashable, Sendable {

    public static let head = try! GitReference(rawValue: "HEAD")

    public let rawValue: String

    public init(rawValue: String) throws {
        guard
            !rawValue.isEmpty,
            !rawValue.hasPrefix("-"),
            !rawValue.contains("\0"),
            !rawValue.contains(where: { $0.isNewline })
        else {
            throw GitError.invalidReference(rawValue)
        }

        self.rawValue = rawValue
    }

    public init(_ commit: GitCommit) {
        rawValue = commit.rawValue
    }
}

extension GitReference: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}

public struct GitStatus: Equatable, Hashable, Sendable {

    public let hasTrackedChanges: Bool

    public let hasUntrackedFiles: Bool

    public var isTrackedClean: Bool {
        !hasTrackedChanges
    }

    public var isCompletelyClean: Bool {
        !hasTrackedChanges && !hasUntrackedFiles
    }

    public init(
        hasTrackedChanges: Bool,
        hasUntrackedFiles: Bool,
    ) {
        self.hasTrackedChanges = hasTrackedChanges
        self.hasUntrackedFiles = hasUntrackedFiles
    }
}

public enum GitFetchScope: Equatable, Hashable, Sendable {

    case allRemotesAndTags

    case tags
}

public enum GitApplyResult: Equatable, Hashable, Sendable {

    case applied

    case conflicted
}

public struct GitCloneOptions: Equatable, Hashable, Sendable {

    public var branch: String?

    public var depth: Int?

    public var singleBranch: Bool

    public var noCheckout: Bool

    public var shared: Bool

    public init(
        branch: String? = nil,
        depth: Int? = nil,
        singleBranch: Bool = false,
        noCheckout: Bool = false,
        shared: Bool = false,
    ) {
        self.branch = branch
        self.depth = depth
        self.singleBranch = singleBranch
        self.noCheckout = noCheckout
        self.shared = shared
    }
}
