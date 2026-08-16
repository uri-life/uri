public import Foundation

public struct MissingDependency: Equatable, Hashable, Sendable {

    public enum Kind: String, Equatable, Hashable, Sendable {

        case regular

        case development
    }

    public let featureID: String

    public let kind: Kind

    public let dependencyID: String

    public init(
        featureID: String,
        kind: Kind,
        dependencyID: String,
    ) {
        self.featureID = featureID
        self.kind = kind
        self.dependencyID = dependencyID
    }
}

public enum PatchsetError: Error, Equatable, Sendable {

    case invalidIdentifier(label: String, value: String)

    case invalidRepositoryRoot(URL)

    case rootManifestAlreadyExists(URL)

    case rootManifestNotFound(URL)

    case upstreamVersionAlreadyExists(String)

    case upstreamVersionNotFound(String)

    case patchsetAlreadyExists(PatchsetReference)

    case manifestNotFound(reference: PatchsetReference, url: URL)

    case invalidManifest(url: URL, reason: String)

    case invalidInheritance(reference: PatchsetReference, reason: String)

    case circularInheritance([PatchsetReference])

    case duplicateExclusion(featureID: String, reference: PatchsetReference)

    case invalidExclusion(featureID: String, reference: PatchsetReference)

    case declaredAndExcluded(featureID: String, reference: PatchsetReference)

    case missingDependencies([MissingDependency])

    case circularDependencies([String])

    case featureAlreadyExists(featureID: String, reference: PatchsetReference)

    case featureNotFound(featureID: String, reference: PatchsetReference)

    case featureNotDirectlyDeclared(featureID: String, reference: PatchsetReference)

    case featureAlreadyExcluded(featureID: String, reference: PatchsetReference)

    case featureNotExcluded(featureID: String, reference: PatchsetReference)

    case patchAlreadyExists(URL)

    case patchNotFound(URL)

    case fileSystem(operation: String, url: URL, reason: String)
}

extension PatchsetError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .invalidIdentifier(let label, let value):
            "Invalid \(label): \(value)"
        case .invalidRepositoryRoot(let url):
            "Patchset repository root does not exist: \(url.path)"
        case .rootManifestAlreadyExists(let url):
            "Patchset root manifest already exists: \(url.path)"
        case .rootManifestNotFound(let url):
            "Could not find patchset root manifest: \(url.path)"
        case .upstreamVersionAlreadyExists(let version):
            "Upstream version already exists: \(version)"
        case .upstreamVersionNotFound(let version):
            "Upstream version does not exist: \(version)"
        case .patchsetAlreadyExists(let reference):
            "Patchset already exists: \(reference)"
        case .manifestNotFound(_, let url):
            "Could not find manifest: \(url.path)"
        case .invalidManifest(let url, let reason):
            "Invalid manifest at \(url.path): \(reason)"
        case .invalidInheritance(let reference, let reason):
            "Invalid inheritance for \(reference): \(reason)"
        case .circularInheritance(let references):
            "Circular inheritance: \(references.map(\.description).joined(separator: " -> "))"
        case .duplicateExclusion(let featureID, let reference):
            "Duplicate exclusion \(featureID) in \(reference)"
        case .invalidExclusion(let featureID, let reference):
            "Could not find inherited feature \(featureID) in \(reference)"
        case .declaredAndExcluded(let featureID, let reference):
            "Feature \(featureID) is declared and excluded in \(reference)"
        case .missingDependencies(let dependencies):
            "Missing dependencies: \(dependencies.map({"\($0.featureID).\($0.kind.rawValue) -> \($0.dependencyID)"}).joined(separator: ", "))"
        case .circularDependencies(let featureIDs):
            "Circular dependencies: \(featureIDs.joined(separator: ", "))"
        case .featureAlreadyExists(let featureID, let reference):
            "Feature \(featureID) already exists in \(reference)"
        case .featureNotFound(let featureID, let reference):
            "Feature \(featureID) does not exist in \(reference)"
        case .featureNotDirectlyDeclared(let featureID, let reference):
            "Feature \(featureID) is not declared directly by \(reference)"
        case .featureAlreadyExcluded(let featureID, let reference):
            "Feature \(featureID) is already excluded by \(reference)"
        case .featureNotExcluded(let featureID, let reference):
            "Feature \(featureID) is not excluded by \(reference)"
        case .patchAlreadyExists(let url):
            "Patch already exists: \(url.path)"
        case .patchNotFound(let url):
            "Patch does not exist: \(url.path)"
        case .fileSystem(let operation, let url, let reason):
            "Could not \(operation) \(url.path): \(reason)"
        }
    }
}
