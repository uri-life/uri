public struct Feature: Equatable, Hashable, Identifiable, Sendable {

    public var id: String

    public var name: String?

    /// A description with LF line endings and exactly one trailing LF when non-nil.
    public var description: String? {
        get {
            _description
        }
        set {
            _description = Self.normalizedDescription(newValue)
        }
    }

    public var dependencies: [String]?

    public var devDependencies: [String]?

    private var _description: String?

    public init(
        id: String,
        name: String? = nil,
        description: String? = nil,
        dependencies: [String]? = nil,
        devDependencies: [String]? = nil,
    ) {
        self.id = id
        self.name = name
        self.dependencies = dependencies
        self.devDependencies = devDependencies
        self._description = Self.normalizedDescription(description)
    }

    private static func normalizedDescription(_ description: String?) -> String? {
        guard let description else {
            return nil
        }

        var normalized = ""
        var hasPendingCarriageReturn = false
        for scalar in description.unicodeScalars {
            if scalar == "\r" {
                if hasPendingCarriageReturn {
                    normalized.append("\n")
                }
                hasPendingCarriageReturn = true
                continue
            }

            if hasPendingCarriageReturn {
                normalized.append("\n")
                hasPendingCarriageReturn = false
                if scalar == "\n" {
                    continue
                }
            }
            normalized.unicodeScalars.append(scalar)
        }
        if hasPendingCarriageReturn {
            normalized.append("\n")
        }

        while normalized.last == "\n" {
            normalized.removeLast()
        }
        normalized.append("\n")
        return normalized
    }

    // MARK: Equatable

    public static func == (
        lhs: Feature,
        rhs: Feature,
    ) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
