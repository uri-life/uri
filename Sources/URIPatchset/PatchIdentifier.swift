public import Foundation

public enum PatchIdentifier: Equatable, Hashable, Sendable {

    case feature(String)

    case ante(String)

    case post(String)

    case pair(current: String, completed: String)

    public var filename: String {
        get throws {
            switch self {
            case .feature(let featureID):
                try IdentifierValidator.validate(featureID, label: "feature")
                return "\(featureID).patch"
            case .ante(let featureID):
                try IdentifierValidator.validate(featureID, label: "feature")
                return "\(featureID)~ANTE.patch"
            case .post(let featureID):
                try IdentifierValidator.validate(featureID, label: "feature")
                return "\(featureID)~POST.patch"
            case .pair(let current, let completed):
                try IdentifierValidator.validate(current, label: "feature")
                try IdentifierValidator.validate(completed, label: "feature")
                return "\(current)~\(completed).patch"
            }
        }
    }
}

public struct PatchFile: Equatable, Hashable, Sendable {

    public let url: URL

    public let source: PatchsetReference

    public let identifier: PatchIdentifier

    public init(
        url: URL,
        source: PatchsetReference,
        identifier: PatchIdentifier,
    ) {
        self.url = url
        self.source = source
        self.identifier = identifier
    }
}
