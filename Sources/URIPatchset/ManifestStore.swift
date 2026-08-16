import Foundation
import URIModel
import Yams

internal struct ManifestStore {

    internal let rootURL: URL

    internal func manifestURL(for reference: PatchsetReference) -> URL {
        patchsetURL(for: reference).appending(path: "manifest.yaml", directoryHint: .notDirectory)
    }

    internal func patchsetURL(for reference: PatchsetReference) -> URL {
        patchesURL(for: reference.upstreamVersion)
            .appending(path: reference.patchsetVersion, directoryHint: .isDirectory)
    }

    internal func patchesURL(for upstreamVersion: String) -> URL {
        rootURL
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: upstreamVersion, directoryHint: .isDirectory)
            .appending(path: "patches", directoryHint: .isDirectory)
    }

    internal func load(_ reference: PatchsetReference) throws -> PatchsetManifest {
        let url = manifestURL(for: reference)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PatchsetError.manifestNotFound(reference: reference, url: url)
        }

        let yaml: String
        do {
            yaml = try String(contentsOf: url, encoding: .utf8)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "read",
                url: url,
                reason: String(describing: error),
            )
        }

        try ManifestSchemaValidator.validate(yaml: yaml, at: url)
        do {
            return try YAMLDecoder().decode(PatchsetManifest.self, from: yaml)
        }
        catch {
            throw PatchsetError.invalidManifest(url: url, reason: String(describing: error))
        }
    }

    internal func save(
        _ manifest: PatchsetManifest,
        for reference: PatchsetReference,
    ) throws {
        let url = manifestURL(for: reference)
        let yaml: String
        do {
            yaml = try ManifestYAMLWriter().write(manifest)
        }
        catch {
            throw PatchsetError.invalidManifest(url: url, reason: String(describing: error))
        }

        do {
            try Data(yaml.utf8).write(to: url, options: .atomic)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "write",
                url: url,
                reason: String(describing: error),
            )
        }
    }
}
