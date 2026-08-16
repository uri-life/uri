public struct PatchsetReference: Comparable, Hashable, Sendable {

    public let upstreamVersion: String

    public let patchsetVersion: String

    public init(
        upstreamVersion: String,
        patchsetVersion: String,
    ) throws {
        try IdentifierValidator.validate(upstreamVersion, label: "upstream version")
        try IdentifierValidator.validate(patchsetVersion, label: "patchset version")
        self.upstreamVersion = upstreamVersion
        self.patchsetVersion = patchsetVersion
    }

    public static func < (
        lhs: PatchsetReference,
        rhs: PatchsetReference,
    ) -> Bool {
        if lhs.upstreamVersion != rhs.upstreamVersion {
            return lhs.upstreamVersion < rhs.upstreamVersion
        }

        return lhs.patchsetVersion < rhs.patchsetVersion
    }
}

extension PatchsetReference: CustomStringConvertible {

    public var description: String {
        "\(upstreamVersion)+\(patchsetVersion)"
    }
}

internal enum IdentifierValidator {

    internal static func validate(
        _ value: String,
        label: String,
    ) throws {
        guard isValid(value) else {
            throw PatchsetError.invalidIdentifier(label: label, value: value)
        }
    }

    internal static func isValid(_ value: String) -> Bool {
        guard
            let first = value.utf8.first,
            isASCIIAlphanumeric(first),
            !value.contains(".."),
            !value.hasSuffix(".lock"),
            !value.hasSuffix(".")
        else {
            return false
        }

        return value.utf8.allSatisfy({
            isASCIIAlphanumeric($0) || [43, 45, 46, 95].contains($0)
        })
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...90).contains(byte)
            || (97...122).contains(byte)
    }
}
