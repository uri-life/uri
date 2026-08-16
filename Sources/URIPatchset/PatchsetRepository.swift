public import Foundation
public import URIModel

public struct PatchsetRepository: Sendable {

    public let rootURL: URL

    private var manifests: ManifestStore {
        .init(rootURL: rootURL)
    }

    private var patches: PatchStore {
        .init(manifests: manifests)
    }

    private var rootManifestStore: RootManifestStore {
        .init(rootURL: rootURL)
    }

    public init(rootURL: URL) throws {
        let rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard
            (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            throw PatchsetError.invalidRepositoryRoot(rootURL)
        }

        self.rootURL = rootURL
    }

    public func rootManifest() throws -> RootManifest {
        try rootManifestStore.load()
    }

    public func initializeRoot(with manifest: RootManifest) throws {
        try rootManifestStore.save(manifest, replacingExisting: false)
        let versionsURL = rootURL.appending(path: "versions", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: versionsURL,
                withIntermediateDirectories: true,
            )
        }
        catch {
            try? FileManager.default.removeItem(at: rootManifestStore.manifestURL)
            throw PatchsetError.fileSystem(
                operation: "create",
                url: versionsURL,
                reason: String(describing: error),
            )
        }
    }

    public func saveRootManifest(_ manifest: RootManifest) throws {
        _ = try rootManifestStore.load()
        try rootManifestStore.save(manifest, replacingExisting: true)
    }

    /// Returns valid upstream-version directory names in ascending order.
    public func upstreamVersions() throws -> [String] {
        let versionsURL = rootURL.appending(path: "versions", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: versionsURL.path) else {
            return []
        }

        return try directoryNames(at: versionsURL)
            .filter(IdentifierValidator.isValid)
            .sorted()
    }

    /// Returns patchsets that contain a manifest for one upstream version.
    public func patchsets(
        in upstreamVersion: String,
    ) throws -> [PatchsetReference] {
        try IdentifierValidator.validate(upstreamVersion, label: "upstream version")
        let upstreamURL = rootURL
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: upstreamVersion, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: upstreamURL.path) else {
            throw PatchsetError.upstreamVersionNotFound(upstreamVersion)
        }

        let patchesURL = manifests.patchesURL(for: upstreamVersion)
        guard FileManager.default.fileExists(atPath: patchesURL.path) else {
            return []
        }

        return try directoryNames(at: patchesURL)
            .filter(IdentifierValidator.isValid)
            .compactMap({ patchsetVersion in
                guard
                    let reference = try? PatchsetReference(
                        upstreamVersion: upstreamVersion,
                        patchsetVersion: patchsetVersion,
                    ),
                    isRegularFile(manifests.manifestURL(for: reference))
                else {
                    return nil
                }

                return reference
            })
            .sorted()
    }

    public func manifest(
        for reference: PatchsetReference,
    ) throws -> PatchsetManifest {
        try manifests.load(reference)
    }

    public func resolve(
        _ reference: PatchsetReference,
    ) throws -> ResolvedPatchset {
        try resolved(reference, overriding: [:])
    }

    public func patch(
        _ identifier: PatchIdentifier,
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        let resolved = try resolve(reference)
        return try patches.find(identifier, in: resolved.inheritanceChain)
    }

    public func patch(
        for featureID: String,
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        try patch(.feature(featureID), inheritedBy: reference)
    }

    public func antePatch(
        for featureID: String,
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        try patch(.ante(featureID), inheritedBy: reference)
    }

    public func postPatch(
        for featureID: String,
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        try patch(.post(featureID), inheritedBy: reference)
    }

    public func pairResolutionPatch(
        for currentFeatureID: String,
        completedFeatureID: String,
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        try patch(
            .pair(current: currentFeatureID, completed: completedFeatureID),
            inheritedBy: reference,
        )
    }

    public func applicablePairResolutionPatch(
        for currentFeatureID: String,
        completedFeatureIDs: [String],
        inheritedBy reference: PatchsetReference,
    ) throws -> PatchFile? {
        for completedFeatureID in completedFeatureIDs.reversed() {
            if
                let patch = try pairResolutionPatch(
                    for: currentFeatureID,
                    completedFeatureID: completedFeatureID,
                    inheritedBy: reference,
                )
            {
                return patch
            }
        }

        return nil
    }

    public func createUpstreamVersion(_ upstreamVersion: String) throws {
        try IdentifierValidator.validate(upstreamVersion, label: "upstream version")
        let upstreamURL = rootURL
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: upstreamVersion, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: upstreamURL.path) else {
            throw PatchsetError.upstreamVersionAlreadyExists(upstreamVersion)
        }

        do {
            try FileManager.default.createDirectory(
                at: manifests.patchesURL(for: upstreamVersion),
                withIntermediateDirectories: true,
            )
        }
        catch {
            try? FileManager.default.removeItem(at: upstreamURL)
            throw PatchsetError.fileSystem(
                operation: "create",
                url: upstreamURL,
                reason: String(describing: error),
            )
        }
    }

    public func createPatchset(
        _ reference: PatchsetReference,
        inheriting parent: PatchsetReference? = nil,
    ) throws {
        let patchesURL = manifests.patchesURL(for: reference.upstreamVersion)
        guard FileManager.default.fileExists(atPath: patchesURL.path) else {
            throw PatchsetError.upstreamVersionNotFound(reference.upstreamVersion)
        }

        let patchsetURL = manifests.patchsetURL(for: reference)
        guard !FileManager.default.fileExists(atPath: patchsetURL.path) else {
            throw PatchsetError.patchsetAlreadyExists(reference)
        }

        let inheritance = parent.map({ parent in
            PatchsetManifest.Inherits.detailed(
                .init(
                    upstreamVersion: parent.upstreamVersion,
                    patchsetVersion: parent.patchsetVersion,
                ),
            )
        })
        let manifest = PatchsetManifest(
            inherits: inheritance,
            excludes: [],
            features: [],
        )

        do {
            try FileManager.default.createDirectory(
                at: patchsetURL,
                withIntermediateDirectories: false,
            )
            _ = try resolved(reference, overriding: [reference: manifest])
            try manifests.save(manifest, for: reference)
        }
        catch {
            try? FileManager.default.removeItem(at: patchsetURL)
            throw error
        }
    }

    public func removeUpstreamVersion(_ upstreamVersion: String) throws {
        try IdentifierValidator.validate(upstreamVersion, label: "upstream version")
        let upstreamURL = rootURL
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: upstreamVersion, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: upstreamURL.path) else {
            throw PatchsetError.upstreamVersionNotFound(upstreamVersion)
        }
        do {
            try FileManager.default.removeItem(at: upstreamURL)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "remove",
                url: upstreamURL,
                reason: String(describing: error),
            )
        }
    }

    public func removePatchset(_ reference: PatchsetReference) throws {
        let url = manifests.patchsetURL(for: reference)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PatchsetError.manifestNotFound(
                reference: reference,
                url: manifests.manifestURL(for: reference),
            )
        }
        do {
            try FileManager.default.removeItem(at: url)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "remove",
                url: url,
                reason: String(describing: error),
            )
        }
    }

    public func addFeature(
        _ feature: Feature,
        to reference: PatchsetReference,
    ) throws {
        try IdentifierValidator.validate(feature.id, label: "feature")
        var manifest = try manifests.load(reference)
        var directFeatures = featureMap(in: manifest)
        guard directFeatures[feature.id] == nil else {
            throw PatchsetError.featureAlreadyExists(
                featureID: feature.id,
                reference: reference,
            )
        }

        let patchIdentifier = PatchIdentifier.feature(feature.id)
        let patchURL = try patches.url(for: patchIdentifier, in: reference)
        guard !FileManager.default.fileExists(atPath: patchURL.path) else {
            throw PatchsetError.patchAlreadyExists(patchURL)
        }

        directFeatures[feature.id] = feature
        manifest.features = Set(directFeatures.values)
        _ = try resolved(reference, overriding: [reference: manifest])

        try patches.write(
            Data(),
            as: patchIdentifier,
            in: reference,
            replacingExisting: false,
        )
        do {
            try manifests.save(manifest, for: reference)
        }
        catch {
            try? patches.remove(patchIdentifier, in: reference)
            throw error
        }
    }

    public func updateFeature(
        _ feature: Feature,
        in reference: PatchsetReference,
    ) throws {
        try IdentifierValidator.validate(feature.id, label: "feature")
        var manifest = try manifests.load(reference)
        var directFeatures = featureMap(in: manifest)
        guard directFeatures[feature.id] != nil else {
            throw PatchsetError.featureNotDirectlyDeclared(
                featureID: feature.id,
                reference: reference,
            )
        }

        directFeatures[feature.id] = feature
        manifest.features = Set(directFeatures.values)
        _ = try resolved(reference, overriding: [reference: manifest])
        try manifests.save(manifest, for: reference)
    }

    public func removeFeature(
        _ featureID: String,
        from reference: PatchsetReference,
    ) throws {
        try removeFeature(featureID, from: reference, force: false)
    }

    public func removeFeature(
        _ featureID: String,
        from reference: PatchsetReference,
        force: Bool,
    ) throws {
        try IdentifierValidator.validate(featureID, label: "feature")
        let originalManifest = try manifests.load(reference)
        var candidate = originalManifest
        var directFeatures = featureMap(in: originalManifest)
        guard directFeatures.removeValue(forKey: featureID) != nil else {
            throw PatchsetError.featureNotDirectlyDeclared(
                featureID: featureID,
                reference: reference,
            )
        }

        candidate.features = Set(directFeatures.values)
        if !force {
            _ = try resolved(reference, overriding: [reference: candidate])
        }

        let staged = try patches.stageRemoval(.feature(featureID), in: reference)
        do {
            try manifests.save(candidate, for: reference)
        }
        catch {
            if let staged {
                try patches.restore(staged)
            }
            throw error
        }

        if let staged {
            do {
                try patches.discard(staged)
            }
            catch {
                try? patches.restore(staged)
                try? manifests.save(originalManifest, for: reference)
                throw error
            }
        }
    }

    public func excludeFeature(
        _ featureID: String,
        from reference: PatchsetReference,
    ) throws {
        try IdentifierValidator.validate(featureID, label: "feature")
        var manifest = try manifests.load(reference)
        guard featureMap(in: manifest)[featureID] == nil else {
            throw PatchsetError.declaredAndExcluded(
                featureID: featureID,
                reference: reference,
            )
        }
        guard !(manifest.excludes ?? []).contains(featureID) else {
            throw PatchsetError.featureAlreadyExcluded(
                featureID: featureID,
                reference: reference,
            )
        }
        guard try resolve(reference).features[featureID] != nil else {
            throw PatchsetError.featureNotFound(
                featureID: featureID,
                reference: reference,
            )
        }

        manifest.excludes = (manifest.excludes ?? []) + [featureID]
        _ = try resolved(reference, overriding: [reference: manifest])
        try manifests.save(manifest, for: reference)
    }

    public func includeFeature(
        _ featureID: String,
        in reference: PatchsetReference,
    ) throws {
        try IdentifierValidator.validate(featureID, label: "feature")
        var manifest = try manifests.load(reference)
        guard (manifest.excludes ?? []).contains(featureID) else {
            throw PatchsetError.featureNotExcluded(
                featureID: featureID,
                reference: reference,
            )
        }

        manifest.excludes = (manifest.excludes ?? []).filter({$0 != featureID})
        _ = try resolved(reference, overriding: [reference: manifest])
        try manifests.save(manifest, for: reference)
    }

    public func replacePatch(
        _ data: Data,
        identifiedBy identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws {
        _ = try manifests.load(reference)
        try patches.write(
            data,
            as: identifier,
            in: reference,
            replacingExisting: true,
        )
    }

    public func removePatch(
        identifiedBy identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws {
        _ = try manifests.load(reference)
        try patches.remove(identifier, in: reference)
    }

    public func replaceFeaturePatchesTransactionally(
        _ patchesByFeatureID: [String: Data],
        in reference: PatchsetReference,
    ) throws {
        let resolved = try resolve(reference)
        for featureID in patchesByFeatureID.keys.sorted() {
            try IdentifierValidator.validate(featureID, label: "feature")
            guard resolved.features[featureID] != nil else {
                throw PatchsetError.featureNotFound(featureID: featureID, reference: reference)
            }
        }
        guard !patchesByFeatureID.isEmpty else {
            return
        }

        let patchsetURL = manifests.patchsetURL(for: reference)
        let transactionURL = patchsetURL.appending(
            path: ".uri-transaction-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let candidateURL = transactionURL.appending(path: "candidates", directoryHint: .isDirectory)
        let backupURL = transactionURL.appending(path: "backups", directoryHint: .isDirectory)
        var replaced = [String]()
        var backedUp = Set<String>()

        do {
            try FileManager.default.createDirectory(
                at: candidateURL,
                withIntermediateDirectories: true,
            )
            try FileManager.default.createDirectory(
                at: backupURL,
                withIntermediateDirectories: true,
            )
            for (featureID, data) in patchesByFeatureID {
                try data.write(
                    to: candidateURL.appending(path: try PatchIdentifier.feature(featureID).filename),
                    options: .atomic,
                )
            }

            for featureID in patchesByFeatureID.keys.sorted() {
                let filename = try PatchIdentifier.feature(featureID).filename
                let destination = patchsetURL.appending(path: filename)
                let candidate = candidateURL.appending(path: filename)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.moveItem(
                        at: destination,
                        to: backupURL.appending(path: filename),
                    )
                    backedUp.insert(featureID)
                }
                try FileManager.default.moveItem(at: candidate, to: destination)
                replaced.append(featureID)
            }
            try FileManager.default.removeItem(at: transactionURL)
        }
        catch {
            for featureID in replaced.reversed() {
                if let filename = try? PatchIdentifier.feature(featureID).filename {
                    try? FileManager.default.removeItem(at: patchsetURL.appending(path: filename))
                }
            }
            for featureID in backedUp {
                if let filename = try? PatchIdentifier.feature(featureID).filename {
                    try? FileManager.default.moveItem(
                        at: backupURL.appending(path: filename),
                        to: patchsetURL.appending(path: filename),
                    )
                }
            }
            try? FileManager.default.removeItem(at: transactionURL)
            throw PatchsetError.fileSystem(
                operation: "replace patches transactionally in",
                url: patchsetURL,
                reason: String(describing: error),
            )
        }
    }

    private func resolved(
        _ reference: PatchsetReference,
        overriding manifestsByReference: [PatchsetReference: PatchsetManifest],
    ) throws -> ResolvedPatchset {
        let chain = try inheritanceChain(
            startingAt: reference,
            overriding: manifestsByReference,
        )
        var mergedFeatures = [String: Feature]()

        for (currentReference, manifest) in chain.reversed() {
            let directFeatures = featureMap(in: manifest)
            for featureID in directFeatures.keys {
                try IdentifierValidator.validate(featureID, label: "feature")
            }

            var seenExclusions = Set<String>()
            for featureID in manifest.excludes ?? [] {
                try IdentifierValidator.validate(featureID, label: "excluded feature")
                guard seenExclusions.insert(featureID).inserted else {
                    throw PatchsetError.duplicateExclusion(
                        featureID: featureID,
                        reference: currentReference,
                    )
                }
                guard directFeatures[featureID] == nil else {
                    throw PatchsetError.declaredAndExcluded(
                        featureID: featureID,
                        reference: currentReference,
                    )
                }
                guard mergedFeatures[featureID] != nil else {
                    throw PatchsetError.invalidExclusion(
                        featureID: featureID,
                        reference: currentReference,
                    )
                }
            }

            for (featureID, feature) in directFeatures {
                if let inherited = mergedFeatures[featureID] {
                    mergedFeatures[featureID] = merge(inherited, with: feature)
                }
                else {
                    mergedFeatures[featureID] = feature
                }
            }
            for featureID in manifest.excludes ?? [] {
                mergedFeatures.removeValue(forKey: featureID)
            }
        }

        try DependencyResolver(features: mergedFeatures).validate()
        return .init(
            reference: reference,
            inheritanceChain: chain.map(\.reference),
            features: mergedFeatures,
        )
    }

    private func inheritanceChain(
        startingAt reference: PatchsetReference,
        overriding manifestsByReference: [PatchsetReference: PatchsetManifest],
    ) throws -> [(reference: PatchsetReference, manifest: PatchsetManifest)] {
        var chain = [(reference: PatchsetReference, manifest: PatchsetManifest)]()
        var current = reference

        while true {
            if let cycleStart = chain.firstIndex(where: {$0.reference == current}) {
                throw PatchsetError.circularInheritance(
                    chain[cycleStart...].map(\.reference) + [current],
                )
            }

            let manifest = try manifestsByReference[current] ?? manifests.load(current)
            chain.append((reference: current, manifest: manifest))
            guard let parent = try parentReference(of: manifest, at: current) else {
                return chain
            }
            current = parent
        }
    }

    private func parentReference(
        of manifest: PatchsetManifest,
        at reference: PatchsetReference,
    ) throws -> PatchsetReference? {
        guard let inheritance = manifest.inherits else {
            return nil
        }

        do {
            switch inheritance {
            case .simple(let value):
                if let separator = value.firstIndex(of: "+") {
                    return try .init(
                        upstreamVersion: String(value[..<separator]),
                        patchsetVersion: String(value[value.index(after: separator)...]),
                    )
                }

                return try .init(
                    upstreamVersion: reference.upstreamVersion,
                    patchsetVersion: value,
                )
            case .detailed(let detailed):
                guard let upstreamVersion = detailed.upstreamVersion else {
                    throw PatchsetError.invalidInheritance(
                        reference: reference,
                        reason: "upstream-version is required.",
                    )
                }

                return try .init(
                    upstreamVersion: upstreamVersion,
                    patchsetVersion: detailed.patchsetVersion,
                )
            }
        }
        catch let error as PatchsetError {
            switch error {
            case .invalidInheritance:
                throw error
            default:
                throw PatchsetError.invalidInheritance(
                    reference: reference,
                    reason: error.description,
                )
            }
        }
    }

    private func featureMap(
        in manifest: PatchsetManifest,
    ) -> [String: Feature] {
        Dictionary(
            uniqueKeysWithValues: (manifest.features ?? []).map({($0.id, $0)}),
        )
    }

    private func merge(
        _ inherited: Feature,
        with child: Feature,
    ) -> Feature {
        .init(
            id: child.id,
            name: child.name ?? inherited.name,
            description: child.description ?? inherited.description,
            dependencies: child.dependencies ?? inherited.dependencies,
            devDependencies: child.devDependencies ?? inherited.devDependencies,
        )
    }

    private func directoryNames(at url: URL) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
            ).filter({ item in
                try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            }).map(\.lastPathComponent)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "list",
                url: url,
                reason: String(describing: error),
            )
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
