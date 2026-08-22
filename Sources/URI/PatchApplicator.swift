import Foundation
import URIGit
import URIPatchset

internal struct PatchApplicator {

    internal let sourceRepository: PatchsetRepository

    internal let reference: PatchsetReference

    internal let repository: GitRepository

    internal let committer: GitIdentity

    internal func apply(_ patch: PatchFile?) async throws -> GitApplyResult {
        guard let patch, try !Data(contentsOf: patch.url).isEmpty else {
            return .applied
        }
        return try await repository.applyMailboxPatch(
            at: patch.url,
            committer: committer,
        )
    }

    internal func applyMain(
        _ patch: PatchFile?,
        featureID: String,
        completedFeatureIDs: [String],
    ) async throws -> GitApplyResult {
        let result = try await apply(patch)
        guard result == .conflicted else {
            return result
        }
        guard let resolution = try sourceRepository.applicablePairResolutionPatch(
            for: featureID,
            completedFeatureIDs: completedFeatureIDs,
            inheritedBy: reference,
        ) else {
            return .conflicted
        }
        _ = try await repository.applyResolutionPatch(at: resolution.url)
        try await repository.continueMailboxApply(committer: committer)
        return .applied
    }
}
