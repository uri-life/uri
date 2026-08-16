import Foundation
import Testing
import URIPatchset

@Suite("Repository Discovery")
struct RepositoryDiscoveryTests {

    @Test
    func `an empty repository reports no upstream versions`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }

        #expect(try fixture.repository.upstreamVersions() == [])
    }

    @Test
    func `repository discovery returns only valid directories with manifests`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let first = try fixture.reference("v1.2.3", "patch1.0")
        let second = try fixture.reference("v1.2.3", "patch1.2")
        try fixture.writeManifest("features: {}", for: second)
        try fixture.writeManifest("features: {}", for: first)

        let patchesURL = fixture.manifestURL(for: first).deletingLastPathComponent()
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: patchesURL.appending(path: "invalid name"),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: patchesURL.appending(path: "patch1.1"),
            withIntermediateDirectories: true,
        )

        #expect(try fixture.repository.upstreamVersions() == ["v1.2.3"])
        #expect(try fixture.repository.patchsets(in: "v1.2.3") == [first, second])
    }

    @Test
    func `repository initialization rejects a missing root`() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        let error = capturedPatchsetError({try PatchsetRepository(rootURL: url)})

        #expect(error == .invalidRepositoryRoot(url.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test
    func `resolving a patchset without a manifest preserves its expected path`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        let expectedURL = fixture.manifestURL(for: reference)

        let error = capturedPatchsetError({try fixture.repository.resolve(reference)})

        #expect(error == .manifestNotFound(reference: reference, url: expectedURL))
    }
}
