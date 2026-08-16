import Foundation
import Testing
import URIPatchset

struct PatchsetTestFixture {

    let rootURL: URL

    let repository: PatchsetRepository

    init() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "URIPatchsetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
        )
        self.rootURL = rootURL
        self.repository = try .init(rootURL: rootURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func reference(
        _ patchsetVersion: String,
    ) throws -> PatchsetReference {
        try reference("v1.2.3", patchsetVersion)
    }

    func reference(
        _ upstreamVersion: String,
        _ patchsetVersion: String,
    ) throws -> PatchsetReference {
        try .init(
            upstreamVersion: upstreamVersion,
            patchsetVersion: patchsetVersion,
        )
    }

    func writeManifest(
        _ yaml: String,
        for reference: PatchsetReference,
    ) throws {
        let url = manifestURL(for: reference)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(normalized(yaml).utf8).write(to: url)
    }

    func writePatch(
        _ contents: String = "patch\n",
        identifiedBy identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws {
        let url = try patchURL(for: identifier, in: reference)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(contents.utf8).write(to: url)
    }

    func manifestURL(for reference: PatchsetReference) -> URL {
        rootURL
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: reference.upstreamVersion, directoryHint: .isDirectory)
            .appending(path: "patches", directoryHint: .isDirectory)
            .appending(path: reference.patchsetVersion, directoryHint: .isDirectory)
            .appending(path: "manifest.yaml", directoryHint: .notDirectory)
    }

    func patchURL(
        for identifier: PatchIdentifier,
        in reference: PatchsetReference,
    ) throws -> URL {
        let filename = try identifier.filename
        return manifestURL(for: reference).deletingLastPathComponent()
            .appending(path: filename, directoryHint: .notDirectory)
    }

    private func normalized(_ yaml: String) -> String {
        yaml.hasSuffix("\n") ? yaml : yaml + "\n"
    }
}

func capturedPatchsetError<T>(
    _ operation: () throws -> T,
) -> PatchsetError? {
    do {
        _ = try operation()
        return nil
    }
    catch let error as PatchsetError {
        return error
    }
    catch {
        Issue.record("Expected PatchsetError, received \(error).")
        return nil
    }
}
