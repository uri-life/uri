public import URIModel

public enum DependencyScope: Equatable, Hashable, Sendable {

    case regular

    case includingDevelopment
}

public struct ResolvedPatchset: Sendable {

    public let reference: PatchsetReference

    /// References from the requested patchset to its oldest ancestor.
    public let inheritanceChain: [PatchsetReference]

    public let features: [String: Feature]

    internal init(
        reference: PatchsetReference,
        inheritanceChain: [PatchsetReference],
        features: [String: Feature],
    ) {
        self.reference = reference
        self.inheritanceChain = inheritanceChain
        self.features = features
    }

    /// Returns every active feature in deterministic dependency-first order.
    public func orderedFeatures(
        in scope: DependencyScope = .regular,
    ) throws -> [Feature] {
        try DependencyResolver(features: features).orderedFeatures(in: scope)
    }

    /// Returns one feature and its transitive dependencies in application order.
    public func dependencyOrder(
        for featureID: String,
        in scope: DependencyScope = .regular,
    ) throws -> [Feature] {
        try DependencyResolver(features: features).dependencyOrder(
            for: featureID,
            in: scope,
            reference: reference,
        )
    }

    /// Returns the deployment feature order with development-only features removed.
    public func applicationOrder() throws -> [Feature] {
        try DependencyResolver(features: features).applicationOrder()
    }
}
