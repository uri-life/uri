import Foundation
public import URIGit
import URIModel
public import URIPatchset

/// Identifies one feature in a resolved patchset generation.
public struct FeatureDiffOperand: Equatable, Hashable, Sendable {

    public let reference: PatchsetReference

    public let featureID: String

    public init(
        reference: PatchsetReference,
        featureID: String,
    ) {
        self.reference = reference
        self.featureID = featureID
    }

    public var label: String {
        "\(reference.upstreamVersion) \(reference.patchsetVersion) \(featureID)"
    }
}

/// Reconstructs and compares the net effects of two patchset features.
public struct FeatureDiffer: Sendable {

    private let git: Git

    private let sourceResolver: PatchsetSourceResolver

    public init(
        git: Git = .init(),
        paths: RuntimePaths = .init(),
    ) {
        self.git = git
        self.sourceResolver = .init(git: git, paths: paths)
    }

    init(
        git: Git,
        sourceResolver: PatchsetSourceResolver,
    ) {
        self.git = git
        self.sourceResolver = sourceResolver
    }

    /// Returns a unified diff of the two feature effects, or an empty string when equal.
    public func compare(
        source: PatchsetSource,
        from: FeatureDiffOperand,
        to: FeatureDiffOperand,
    ) async throws -> String {
        let resolvedSource = try await sourceResolver.resolve(
            source,
            references: [from.reference, to.reference],
            includePatches: true,
        )
        defer { try? sourceResolver.removeSnapshot(at: resolvedSource.snapshotURL) }

        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "uri-diff-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        do {
            try FileManager.default.createDirectory(
                at: temporaryRoot,
                withIntermediateDirectories: false,
            )
        }
        catch {
            throw URIError.fileSystem(
                "Could not create temporary feature comparison directory: \(error)",
            )
        }
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let manifest = try resolvedSource.repository.rootManifest()
        let cloneURL = temporaryRoot.appending(path: "repository", directoryHint: .isDirectory)
        let repository = try await git.cloneRepository(
            from: manifest.upstream,
            to: cloneURL,
            relativeTo: resolvedSource.repository.rootURL,
            options: .init(
                branch: from.reference.upstreamVersion,
                depth: 1,
                singleBranch: true,
            ),
        )
        if from.reference.upstreamVersion != to.reference.upstreamVersion {
            try await repository.fetchTag(to.reference.upstreamVersion, depth: 1)
        }

        let committer = try GitIdentity(
            name: RootManifest.legacyCommitterName,
            email: RootManifest.legacyCommitterEmail,
        )
        try await repository.configureIdentity(committer)

        let fromPatch = try await featureEffect(
            from,
            side: "--from",
            sourceRepository: resolvedSource.repository,
            repository: repository,
            committer: committer,
        )
        let toPatch = try await featureEffect(
            to,
            side: "--to",
            sourceRepository: resolvedSource.repository,
            repository: repository,
            committer: committer,
        )

        let fromURL = temporaryRoot.appending(path: "from.patch")
        let toURL = temporaryRoot.appending(path: "to.patch")
        do {
            try fromPatch.write(to: fromURL, options: .atomic)
            try toPatch.write(to: toURL, options: .atomic)
        }
        catch {
            throw URIError.fileSystem("Could not save temporary feature effects: \(error)")
        }

        let comparison = try await git.diffFiles(fromURL, toURL)
        return render(
            comparison,
            fromLabel: from.label,
            toLabel: to.label,
        )
    }

    private func featureEffect(
        _ operand: FeatureDiffOperand,
        side: String,
        sourceRepository: PatchsetRepository,
        repository: GitRepository,
        committer: GitIdentity,
    ) async throws -> Data {
        try await repository.checkoutTag(operand.reference.upstreamVersion)
        let patchset = try sourceRepository.resolve(operand.reference)
        let features = try patchset.dependencyOrder(for: operand.featureID, in: .regular)
        var completedFeatureIDs = [String]()
        var base: GitCommit?

        for feature in features {
            if feature.id == operand.featureID {
                base = try await repository.currentCommit()
            }
            try await apply(
                featureID: feature.id,
                side: side,
                completedFeatureIDs: completedFeatureIDs,
                sourceRepository: sourceRepository,
                reference: operand.reference,
                repository: repository,
                committer: committer,
            )
            completedFeatureIDs.append(feature.id)
        }

        guard let base else {
            throw URIError.invalidState(
                "Could not locate feature \(operand.featureID) in \(operand.reference).",
            )
        }
        let head = try await repository.currentCommit()
        let data = try await repository.diff(
            from: .init(base),
            to: .init(head),
        )
        return canonicalPatch(data)
    }

    private func apply(
        featureID: String,
        side: String,
        completedFeatureIDs: [String],
        sourceRepository: PatchsetRepository,
        reference: PatchsetReference,
        repository: GitRepository,
        committer: GitIdentity,
    ) async throws {
        let applicator = PatchApplicator(
            sourceRepository: sourceRepository,
            reference: reference,
            repository: repository,
            committer: committer,
        )
        let ante = try await applicator.apply(
            sourceRepository.antePatch(for: featureID, inheritedBy: reference),
        )
        guard ante == .applied else {
            throw comparisonConflict(side: side, featureID: featureID, phase: "ante")
        }
        let main = try await applicator.applyMain(
            sourceRepository.patch(for: featureID, inheritedBy: reference),
            featureID: featureID,
            completedFeatureIDs: completedFeatureIDs,
        )
        guard main == .applied else {
            throw comparisonConflict(side: side, featureID: featureID, phase: "main")
        }
        let post = try await applicator.apply(
            sourceRepository.postPatch(for: featureID, inheritedBy: reference),
        )
        guard post == .applied else {
            throw comparisonConflict(side: side, featureID: featureID, phase: "post")
        }
    }

    private func comparisonConflict(
        side: String,
        featureID: String,
        phase: String,
    ) -> URIError {
        .conflict(
            "Conflict while reconstructing \(side) feature \(featureID) \(phase) patch.",
        )
    }

    private func canonicalPatch(_ data: Data) -> Data {
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter({ !$0.hasPrefix("index ") })
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func render(
        _ data: Data,
        fromLabel: String,
        toLabel: String,
    ) -> String {
        guard !data.isEmpty else {
            return ""
        }
        var rendered = [String]()
        for line in String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
        {
            if line.hasPrefix("diff --git ") || line.hasPrefix("index ") {
                continue
            }
            if line.hasPrefix("@@") {
                rendered.append(hunkHeader(line))
            }
            else if line.hasPrefix("--- ") {
                rendered.append("--- \(fromLabel)")
            }
            else if line.hasPrefix("+++ ") {
                rendered.append("+++ \(toLabel)")
            }
            else {
                rendered.append(String(line))
            }
        }
        return rendered.joined(separator: "\n")
    }

    private func hunkHeader(_ line: Substring) -> String {
        let remainder = line.dropFirst(2)
        guard let closing = remainder.range(of: "@@") else {
            return String(line)
        }
        return String(line[..<closing.upperBound])
    }
}
