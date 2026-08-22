import AsyncHTTPClient
public import Foundation
import NIOCore
import NIOHTTP1
public import URIGit
import URIModel
public import URIPatchset

public struct PatchsetSourceResolver: Sendable {

    typealias RequestExecutor = @Sendable (HTTPClientRequest) async throws -> HTTPClientResponse

    private let git: Git

    private let paths: RuntimePaths

    private let requestExecutor: RequestExecutor

    public init(
        git: Git = .init(),
        paths: RuntimePaths = .init(),
    ) {
        self.init(
            git: git,
            paths: paths,
            requestExecutor: {
                try await HTTPClient.shared.execute($0, timeout: .seconds(60))
            },
        )
    }

    init(
        git: Git = .init(),
        paths: RuntimePaths = .init(),
        requestExecutor: @escaping RequestExecutor,
    ) {
        self.git = git
        self.paths = paths
        self.requestExecutor = requestExecutor
    }

    public func resolve(
        _ source: PatchsetSource,
        reference: PatchsetReference? = nil,
        includePatches: Bool = false,
    ) async throws -> ResolvedPatchsetSource {
        try await resolve(
            source,
            references: reference.map({[$0]}) ?? [],
            includePatches: includePatches,
        )
    }

    public func resolve(
        _ source: PatchsetSource,
        references: [PatchsetReference],
        includePatches: Bool = false,
    ) async throws -> ResolvedPatchsetSource {
        switch source.kind {
        case .local:
            guard let rootURL = source.localRootURL else {
                throw URIError.invalidState("A local source has no root path: \(source.original)")
            }
            let repository = try PatchsetRepository(rootURL: rootURL)
            _ = try repository.rootManifest()
            for reference in references {
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
                for reference in references {
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
                references: references,
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
        references: [PatchsetReference],
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

            if !references.isEmpty {
                try await downloadInheritance(
                    startingAt: references,
                    rootURL: rootURL,
                    snapshotURL: snapshotURL,
                    repository: repository,
                )
                let resolved = try references.map(repository.resolve)
                if includePatches {
                    var downloadedPaths = Set<String>()
                    for patchset in resolved {
                        try await downloadPatches(
                            for: patchset,
                            rootURL: rootURL,
                            snapshotURL: snapshotURL,
                            downloadedPaths: &downloadedPaths,
                        )
                    }
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
        startingAt references: [PatchsetReference],
        rootURL: URL,
        snapshotURL: URL,
        repository: PatchsetRepository,
    ) async throws {
        var downloaded = Set<PatchsetReference>()
        for startingReference in references {
            var seen = Set<PatchsetReference>()
            var current: PatchsetReference? = startingReference
            while let reference = current {
                guard seen.insert(reference).inserted else {
                    throw URIError.invalidState(
                        "Circular HTTP patchset inheritance at \(reference).",
                    )
                }
                let relativePath = manifestRelativePath(reference)
                if downloaded.insert(reference).inserted {
                    try await downloadRequired(
                        rootURL.appending(path: relativePath),
                        to: snapshotURL.appending(path: relativePath),
                    )
                }
                current = try parentReference(
                    of: repository.manifest(for: reference),
                    at: reference,
                )
            }
        }
    }

    private func downloadPatches(
        for resolved: ResolvedPatchset,
        rootURL: URL,
        snapshotURL: URL,
        downloadedPaths: inout Set<String>,
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
                guard downloadedPaths.insert(relativePath).inserted else {
                    continue
                }
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
        var request = HTTPClientRequest(url: remoteURL.absoluteString)
        request.method = .GET
        request.headers.add(name: "User-Agent", value: "uri/2")
        let response = try await requestExecutor(request)
        let statusCode = Int(response.status.code)
        if statusCode == 404 {
            try await discard(response.body)
            return false
        }
        guard (200...299).contains(statusCode) else {
            try await discard(response.body)
            throw URIError.http(status: statusCode, url: remoteURL.absoluteString)
        }
        try await write(response.body, to: localURL)
        return true
    }

    private func discard(_ body: HTTPClientResponse.Body) async throws {
        for try await _ in body {}
    }

    private func write(_ body: HTTPClientResponse.Body, to localURL: URL) async throws {
        let directoryURL = localURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appending(
            path: ".\(localURL.lastPathComponent).uri-\(UUID().uuidString).tmp",
        )
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
            )
        }
        catch {
            throw URIError.fileSystem("Could not save \(localURL.path): \(error)")
        }
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw URIError.fileSystem("Could not create temporary file for \(localURL.path).")
        }
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryURL)
        }
        catch {
            throw URIError.fileSystem("Could not save \(localURL.path): \(error)")
        }
        var shouldCloseFile = true
        defer {
            if shouldCloseFile {
                try? fileHandle.close()
            }
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        var iterator = body.makeAsyncIterator()
        while let buffer = try await iterator.next() {
            do {
                try fileHandle.write(contentsOf: Data(buffer.readableBytesView))
            }
            catch {
                throw URIError.fileSystem("Could not save \(localURL.path): \(error)")
            }
        }
        try Task.checkCancellation()
        do {
            try fileHandle.close()
            shouldCloseFile = false
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
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
