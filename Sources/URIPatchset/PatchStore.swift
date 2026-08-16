import Foundation

internal struct PatchStore {

    private let manifests: ManifestStore

    internal init(manifests: ManifestStore) {
        self.manifests = manifests
    }

    internal func url(
        for identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws -> URL {
        try manifests.patchsetURL(for: reference)
            .appending(path: identifier.filename, directoryHint: .notDirectory)
    }

    internal func find(
        _ identifier: PatchIdentifier,
        in inheritanceChain: [PatchsetReference],
    ) throws -> PatchFile? {
        for reference in inheritanceChain {
            let candidate = try url(for: identifier, in: reference)
            if isRegularFile(candidate) {
                return .init(
                    url: candidate,
                    source: reference,
                    identifier: identifier,
                )
            }
        }

        return nil
    }

    internal func write(
        _ data: Data,
        as identifier: PatchIdentifier,
        in reference: PatchsetReference,
        replacingExisting: Bool,
    ) throws {
        let destination = try url(for: identifier, in: reference)
        if
            !replacingExisting,
            FileManager.default.fileExists(atPath: destination.path)
        {
            throw PatchsetError.patchAlreadyExists(destination)
        }

        do {
            try data.write(to: destination, options: .atomic)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "write",
                url: destination,
                reason: String(describing: error),
            )
        }
    }

    internal func remove(
        _ identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws {
        let target = try url(for: identifier, in: reference)
        guard isRegularFile(target) else {
            throw PatchsetError.patchNotFound(target)
        }

        do {
            try FileManager.default.removeItem(at: target)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "remove",
                url: target,
                reason: String(describing: error),
            )
        }
    }

    internal func stageRemoval(
        _ identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws -> StagedPatchRemoval? {
        let target = try url(for: identifier, in: reference)
        guard isRegularFile(target) else {
            return nil
        }

        let backup = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).backup")
        do {
            try FileManager.default.moveItem(at: target, to: backup)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "stage removal of",
                url: target,
                reason: String(describing: error),
            )
        }

        return .init(original: target, backup: backup)
    }

    internal func restore(_ staged: StagedPatchRemoval) throws {
        do {
            try FileManager.default.moveItem(at: staged.backup, to: staged.original)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "restore",
                url: staged.original,
                reason: String(describing: error),
            )
        }
    }

    internal func discard(_ staged: StagedPatchRemoval) throws {
        do {
            try FileManager.default.removeItem(at: staged.backup)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "remove backup for",
                url: staged.original,
                reason: String(describing: error),
            )
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

internal struct StagedPatchRemoval {

    internal let original: URL

    internal let backup: URL
}
