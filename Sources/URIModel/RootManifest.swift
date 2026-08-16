public struct RootManifest: Codable, Hashable, Sendable {

    public static let legacyBranchPrefix = "uri"

    public static let legacyCommitterName = "URI"

    public static let legacyCommitterEmail = "uri@uri.life"

    public var upstream: String

    public var branchPrefix: String?

    public var committer: Committer?

    public init(
        upstream: String,
        branchPrefix: String? = nil,
        committer: Committer? = nil,
    ) {
        self.upstream = upstream
        self.branchPrefix = branchPrefix
        self.committer = committer
    }

    private enum CodingKeys: String, CodingKey {

        case upstream

        case branchPrefix = "branch-prefix"

        case committer
    }
}

extension RootManifest {

    public enum Committer: Codable, Hashable, Sendable {

        case explicit(ExplicitCommitter)

        case repository

        private enum CodingKeys: String, CodingKey {

            case mode
        }

        private enum Mode: String, Codable {

            case explicit

            case repository
        }

        // MARK: Codable

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Mode.self, forKey: .mode) {
            case .explicit:
                self = .explicit(try ExplicitCommitter(from: decoder))
            case .repository:
                self = .repository
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .explicit(let explicitCommitter):
                try container.encode(Mode.explicit, forKey: .mode)
                try explicitCommitter.encode(to: encoder)
            case .repository:
                try container.encode(Mode.repository, forKey: .mode)
            }
        }
    }

    public struct ExplicitCommitter: Codable, Hashable, Sendable {

        public var name: String

        public var email: String

        public init(
            name: String,
            email: String,
        ) {
            self.name = name
            self.email = email
        }
    }
}
