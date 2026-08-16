public import Foundation
#if canImport(FoundationNetworking)
public import FoundationNetworking
#endif
public import URIGit
import URIModel
public import URIPatchset

public struct PatchsetSourceResolver: Sendable {

    private let git: Git

    private let paths: RuntimePaths

    private let session: URLSession

    public init(
        git: Git = .init(),
        paths: RuntimePaths = .init(),
        session: URLSession = .shared,
    ) {
        self.git = git
        self.paths = paths
        self.session = session
    }

    public func resolve(
        _ source: PatchsetSource,
        reference: PatchsetReference? = nil,
        includePatches: Bool = false,
    ) async throws -> ResolvedPatchsetSource {
        switch source.kind {
        case .local:
            guard let rootURL = source.localRootURL else {
                throw URIError.invalidState("A local source has no root path: \(source.original)")
            }
            let repository = try PatchsetRepository(rootURL: rootURL)
            _ = try repository.rootManifest()
            if let reference {
                _ = try repository.resolve(reference)
            }
            return .init(source: source, repository: repository, snapshotURL: nil)
        case .git:
            let snapshotURL = try paths.createOperationSnapshotDirectory()
            let repositoryURL = snapshotURL.appending(path: "source", directoryHint: .isDirectory)
            do {
                _ = try await git.cloneRepository(
                    from: PatchsetSourceLocator.gitRemote(from: source),
                    to: repositoryURL,
                    options: .init(depth: 1, singleBranch: true),
                )
                let repository = try PatchsetRepository(rootURL: repositoryURL)
                _ = try repository.rootManifest()
                if let reference {
                    _ = try repository.resolve(reference)
                }
                return .init(source: source, repository: repository, snapshotURL: snapshotURL)
            }
            catch {
                try? FileManager.default.removeItem(at: snapshotURL)
                throw error
            }
        case .http:
            return try await resolveHTTP(
                source,
                reference: reference,
                includePatches: includePatches,
            )
        }
    }

    public func removeSnapshot(at snapshotURL: URL?) throws {
        guard let snapshotURL else {
            return
        }
        let canonical = snapshotURL.standardizedFileURL.resolvingSymlinksInPath()
        let cache = paths.operationCacheURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.deletingLastPathComponent().path == cache.path else {
            throw URIError.invalidState("Refusing to remove an unmanaged snapshot: \(canonical.path)")
        }
        do {
            try FileManager.default.removeItem(at: canonical)
        }
        catch {
            throw URIError.fileSystem("Could not remove snapshot \(canonical.path): \(error)")
        }
    }

    private func resolveHTTP(
        _ source: PatchsetSource,
        reference: PatchsetReference?,
        includePatches: Bool,
    ) async throws -> ResolvedPatchsetSource {
        guard let rootURL = URL(string: source.original) else {
            throw URIError.unsupportedSource("Invalid HTTP source: \(source.original)")
        }
        let snapshotURL = try paths.createOperationSnapshotDirectory()
        do {
            let rootManifestURL = snapshotURL.appending(path: "manifest.yaml")
            try await downloadRequired(
                rootURL.appending(path: "manifest.yaml"),
                to: rootManifestURL,
            )
            let repository = try PatchsetRepository(rootURL: snapshotURL)
            _ = try repository.rootManifest()

            if let reference {
                try await downloadInheritance(
                    startingAt: reference,
                    rootURL: rootURL,
                    snapshotURL: snapshotURL,
                    repository: repository,
                )
                let resolved = try repository.resolve(reference)
                if includePatches {
                    try await downloadPatches(
                        for: resolved,
                        rootURL: rootURL,
                        snapshotURL: snapshotURL,
                    )
                }
            }
            return .init(source: source, repository: repository, snapshotURL: snapshotURL)
        }
        catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
    }

    private func downloadInheritance(
        startingAt reference: PatchsetReference,
        rootURL: URL,
        snapshotURL: URL,
        repository: PatchsetRepository,
    ) async throws {
        var seen = Set<PatchsetReference>()
        var current: PatchsetReference? = reference
        while let reference = current {
            guard seen.insert(reference).inserted else {
                throw URIError.invalidState("Circular HTTP patchset inheritance at \(reference).")
            }
            let relativePath = manifestRelativePath(reference)
            try await downloadRequired(
                rootURL.appending(path: relativePath),
                to: snapshotURL.appending(path: relativePath),
            )
            current = try parentReference(
                of: repository.manifest(for: reference),
                at: reference,
            )
        }
    }

    private func downloadPatches(
        for resolved: ResolvedPatchset,
        rootURL: URL,
        snapshotURL: URL,
    ) async throws {
        let features = try resolved.orderedFeatures(in: .includingDevelopment).map(\.id)
        var filenames = Set<String>()
        for feature in features {
            filenames.insert(try PatchIdentifier.feature(feature).filename)
            filenames.insert(try PatchIdentifier.ante(feature).filename)
            filenames.insert(try PatchIdentifier.post(feature).filename)
        }
        for (index, current) in features.enumerated() where index > 0 {
            for completed in features[..<index] {
                filenames.insert(
                    try PatchIdentifier.pair(current: current, completed: completed).filename,
                )
            }
        }

        for reference in resolved.inheritanceChain {
            let directory = patchsetRelativePath(reference)
            for filename in filenames.sorted() {
                let relativePath = "\(directory)/\(filename)"
                _ = try await downloadOptional(
                    rootURL.appending(path: relativePath),
                    to: snapshotURL.appending(path: relativePath),
                )
            }
        }
    }

    private func parentReference(
        of manifest: URIModel.PatchsetManifest,
        at reference: PatchsetReference,
    ) throws -> PatchsetReference? {
        guard let inherits = manifest.inherits else {
            return nil
        }
        switch inherits {
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
        case .detailed(let value):
            guard let upstreamVersion = value.upstreamVersion else {
                throw URIError.invalidState("HTTP inheritance at \(reference) has no upstream-version.")
            }
            return try .init(
                upstreamVersion: upstreamVersion,
                patchsetVersion: value.patchsetVersion,
            )
        }
    }

    private func downloadRequired(_ remoteURL: URL, to localURL: URL) async throws {
        guard try await downloadOptional(remoteURL, to: localURL) else {
            throw URIError.http(status: 404, url: remoteURL.absoluteString)
        }
    }

    @discardableResult
    private func downloadOptional(_ remoteURL: URL, to localURL: URL) async throws -> Bool {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.setValue("uri/2", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URIError.unsupportedSource("Non-HTTP response from \(remoteURL.absoluteString)")
        }
        if response.statusCode == 404 {
            return false
        }
        guard (200...299).contains(response.statusCode) else {
            throw URIError.http(status: response.statusCode, url: remoteURL.absoluteString)
        }
        do {
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: localURL, options: .atomic)
            return true
        }
        catch {
            throw URIError.fileSystem("Could not save \(localURL.path): \(error)")
        }
    }

    private func manifestRelativePath(_ reference: PatchsetReference) -> String {
        "\(patchsetRelativePath(reference))/manifest.yaml"
    }

    private func patchsetRelativePath(_ reference: PatchsetReference) -> String {
        "versions/\(reference.upstreamVersion)/patches/\(reference.patchsetVersion)"
    }
}
