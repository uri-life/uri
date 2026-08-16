import TopologicalSort
import URIModel

internal struct DependencyResolver {

    private let features: [String: Feature]

    internal init(features: [String: Feature]) {
        self.features = features
    }

    internal func validate() throws {
        var missing = [MissingDependency]()

        for featureID in features.keys.sorted() {
            guard let feature = features[featureID] else {
                continue
            }

            try IdentifierValidator.validate(featureID, label: "feature")
            for dependencyID in feature.dependencies ?? [] {
                try IdentifierValidator.validate(dependencyID, label: "feature dependency")
                if features[dependencyID] == nil {
                    missing.append(
                        .init(
                            featureID: featureID,
                            kind: .regular,
                            dependencyID: dependencyID,
                        ),
                    )
                }
            }
            for dependencyID in feature.devDependencies ?? [] {
                try IdentifierValidator.validate(dependencyID, label: "feature dependency")
                if features[dependencyID] == nil {
                    missing.append(
                        .init(
                            featureID: featureID,
                            kind: .development,
                            dependencyID: dependencyID,
                        ),
                    )
                }
            }
        }

        guard missing.isEmpty else {
            throw PatchsetError.missingDependencies(
                missing.sorted(by: {
                    ($0.featureID, $0.kind.rawValue, $0.dependencyID)
                        < ($1.featureID, $1.kind.rawValue, $1.dependencyID)
                }),
            )
        }

        _ = try orderedFeatureIDs(in: .regular)
        _ = try orderedFeatureIDs(in: .includingDevelopment)
    }

    internal func orderedFeatures(
        in scope: DependencyScope,
    ) throws -> [Feature] {
        try orderedFeatureIDs(in: scope).compactMap({features[$0]})
    }

    internal func dependencyOrder(
        for featureID: String,
        in scope: DependencyScope,
        reference: PatchsetReference,
    ) throws -> [Feature] {
        guard features[featureID] != nil else {
            throw PatchsetError.featureNotFound(
                featureID: featureID,
                reference: reference,
            )
        }

        let required = dependencyClosure(startingAt: [featureID], in: scope)
        return try orderedFeatureIDs(in: scope, restrictedTo: required)
            .compactMap({features[$0]})
    }

    internal func applicationOrder() throws -> [Feature] {
        var developmentCandidates = Set<String>()
        for feature in features.values {
            developmentCandidates.formUnion(
                dependencyClosure(
                    startingAt: feature.devDependencies ?? [],
                    in: .includingDevelopment,
                ),
            )
        }

        let roots = Set(features.keys).subtracting(developmentCandidates)
        let required = dependencyClosure(startingAt: roots, in: .regular)
        return try orderedFeatureIDs(in: .regular, restrictedTo: required)
            .compactMap({features[$0]})
    }

    private func dependencyClosure<S>(
        startingAt featureIDs: S,
        in scope: DependencyScope,
    ) -> Set<String>
    where S: Sequence, S.Element == String {
        var required = Set<String>()
        var pending = Array(featureIDs)

        while let featureID = pending.popLast() {
            guard required.insert(featureID).inserted else {
                continue
            }
            guard let feature = features[featureID] else {
                continue
            }

            pending.append(contentsOf: feature.dependencies ?? [])
            if scope == .includingDevelopment {
                pending.append(contentsOf: feature.devDependencies ?? [])
            }
        }

        return required
    }

    private func orderedFeatureIDs(
        in scope: DependencyScope,
        restrictedTo selected: Set<String>? = nil,
    ) throws -> [String] {
        let selected = selected ?? Set(features.keys)
        var graph = [String: [String]]()

        for featureID in selected {
            guard let feature = features[featureID] else {
                continue
            }

            var dependencies = feature.dependencies ?? []
            if scope == .includingDevelopment {
                dependencies.append(contentsOf: feature.devDependencies ?? [])
            }
            graph[featureID] = dependencies.filter({
                $0 != featureID && selected.contains($0)
            })
        }

        do {
            return try graph.topologicalSort()
        }
        catch .cycle(let featureIDs) {
            throw PatchsetError.circularDependencies(featureIDs)
        }
    }
}
