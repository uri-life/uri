public struct PatchsetManifest: Codable, Hashable, Sendable {

    public var inherits: Inherits?

    public var excludes: [String]?

    public var features: Set<Feature>?

    public init(
        inherits: Inherits? = nil,
        excludes: [String]? = nil,
        features: Set<Feature>? = nil,
    ) {
        self.inherits = inherits
        self.excludes = excludes
        self.features = features
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {

        case inherits

        case excludes

        case features
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inherits = try container.decodeIfPresent(Inherits.self, forKey: .inherits)
        self.excludes = try container.decodeIfPresent([String].self, forKey: .excludes)
        self.features = try container.decodeIfPresent(FeatureMap.self, forKey: .features)?.features
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.inherits, forKey: .inherits)
        try container.encodeIfPresent(self.excludes, forKey: .excludes)
        if let features {
            try container.encode(FeatureMap(features: features), forKey: .features)
        }
    }
}

extension PatchsetManifest {

    public enum Inherits: Codable, Hashable, Sendable {

        case simple(String)

        case detailed(DetailedInherits)

        // MARK: Codable

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let simple = try? container.decode(String.self) {
                self = .simple(simple)
            }
            else {
                let detailed = try container.decode(DetailedInherits.self)
                self = .detailed(detailed)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .simple(let simple):
                try container.encode(simple)
            case .detailed(let detailed):
                try container.encode(detailed)
            }
        }
    }

    public struct DetailedInherits: Codable, Hashable, Sendable {

        public var upstreamVersion: String?

        public var patchsetVersion: String

        public init(
            upstreamVersion: String? = nil,
            patchsetVersion: String,
        ) {
            self.upstreamVersion = upstreamVersion
            self.patchsetVersion = patchsetVersion
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {

            case upstreamVersion = "upstream-version"

            case patchsetVersion = "patchset-version"
        }
    }
}

extension PatchsetManifest {

    private struct FeaturePayload: Codable, Hashable, Sendable {

        fileprivate var name: String?

        fileprivate var description: String?

        fileprivate var dependencies: [String]?

        fileprivate var devDependencies: [String]?

        fileprivate init(feature: Feature) {
            self.name = feature.name
            self.description = feature.description
            self.dependencies = feature.dependencies
            self.devDependencies = feature.devDependencies
        }

        fileprivate func feature(withID id: String) -> Feature {
            .init(
                id: id,
                name: self.name,
                description: self.description,
                dependencies: self.dependencies,
                devDependencies: self.devDependencies,
            )
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {

            case name

            case description

            case dependencies

            case devDependencies = "dev-dependencies"
        }
    }

    private struct FeatureMap: Codable, Hashable, Sendable {

        fileprivate var features: Set<Feature>

        fileprivate init(features: Set<Feature>) {
            self.features = features
        }

        // MARK: Codable

        fileprivate init(from decoder: any Decoder) throws {
            let payloadMap = try [String: FeaturePayload](from: decoder)
            var features = Set<Feature>()
            for (id, payload) in payloadMap {
                features.insert(payload.feature(withID: id))
            }
            self.features = features
        }

        fileprivate func encode(to encoder: any Encoder) throws {
            var payloadMap = [String: FeaturePayload]()
            for feature in self.features {
                payloadMap[feature.id] = FeaturePayload(feature: feature)
            }
            try payloadMap.encode(to: encoder)
        }
    }
}
