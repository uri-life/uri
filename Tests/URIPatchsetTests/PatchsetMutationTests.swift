import Foundation
import Testing
import URIModel
import URIPatchset

@Suite("Patchset Mutation")
struct PatchsetMutationTests {

    @Test
    func `upstream and cross upstream patchsets are created with canonical manifests`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("v1.2.3", "patch1.0")
        let child = try fixture.reference("v1.2.4", "patch1.1")

        try fixture.repository.createUpstreamVersion("v1.2.3")
        try fixture.repository.createUpstreamVersion("v1.2.4")
        try fixture.repository.createPatchset(parent)
        try fixture.repository.createPatchset(child, inheriting: parent)

        let resolved = try fixture.repository.resolve(child)
        let contents = try String(contentsOf: fixture.manifestURL(for: child), encoding: .utf8)

        #expect(resolved.inheritanceChain == [child, parent])
        #expect(
            contents
                == """
                inherits:
                  upstream-version: v1.2.3
                  patchset-version: patch1.0

                features: {}

                """,
        )
    }

    @Test
    func `feature add update patch replacement and removal keep manifest and patch in sync`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.repository.createUpstreamVersion(reference.upstreamVersion)
        try fixture.repository.createPatchset(reference)

        try fixture.repository.addFeature(.init(id: "base"), to: reference)
        try fixture.repository.addFeature(
            .init(id: "feature", dependencies: ["base"]),
            to: reference,
        )
        try fixture.repository.replacePatch(
            Data("updated patch\n".utf8),
            identifiedBy: .feature("feature"),
            in: reference,
        )
        try fixture.repository.updateFeature(
            .init(
                id: "feature",
                name: "Feature",
                description: "Updated",
                dependencies: ["base"],
            ),
            in: reference,
        )

        let patchURL = try fixture.patchURL(for: .feature("feature"), in: reference)
        #expect(try Data(contentsOf: patchURL) == Data("updated patch\n".utf8))
        #expect(try fixture.repository.resolve(reference).features["feature"]?.name == "Feature")

        let manifestBeforeFailure = try Data(contentsOf: fixture.manifestURL(for: reference))
        let patchBeforeFailure = try Data(contentsOf: fixture.patchURL(for: .feature("base"), in: reference))
        #expect(
            capturedPatchsetError({try fixture.repository.removeFeature("base", from: reference)})
                == .missingDependencies([
                    .init(
                        featureID: "feature",
                        kind: .regular,
                        dependencyID: "base",
                    ),
                ]),
        )
        #expect(try Data(contentsOf: fixture.manifestURL(for: reference)) == manifestBeforeFailure)
        #expect(
            try Data(contentsOf: fixture.patchURL(for: .feature("base"), in: reference))
                == patchBeforeFailure,
        )

        try fixture.repository.updateFeature(
            .init(id: "feature", name: "Feature"),
            in: reference,
        )
        try fixture.repository.removeFeature("base", from: reference)
        let removedPatchURL = try fixture.patchURL(for: .feature("base"), in: reference)

        #expect(try fixture.repository.resolve(reference).features["base"] == nil)
        #expect(!FileManager.default.fileExists(atPath: removedPatchURL.path))
    }

    @Test
    func `exclude and include validate the complete candidate and omit an empty excludes key`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("patch1.0")
        let child = try fixture.reference("patch1.1")
        try fixture.writeManifest(
            """
            features:
              base: {}
              dependent:
                dependencies: [base]
            """,
            for: parent,
        )
        try fixture.writeManifest("inherits: patch1.0\nfeatures: {}", for: child)
        let original = try Data(contentsOf: fixture.manifestURL(for: child))

        #expect(
            capturedPatchsetError({
                try fixture.repository.excludeFeature("base", from: child)
            }) == .missingDependencies([
                .init(
                    featureID: "dependent",
                    kind: .regular,
                    dependencyID: "base",
                ),
            ]),
        )
        #expect(try Data(contentsOf: fixture.manifestURL(for: child)) == original)

        try fixture.repository.excludeFeature("dependent", from: child)
        #expect(try fixture.repository.resolve(child).features["dependent"] == nil)
        try fixture.repository.includeFeature("dependent", in: child)
        #expect(try fixture.repository.resolve(child).features["dependent"] != nil)
        let contents = try String(contentsOf: fixture.manifestURL(for: child), encoding: .utf8)
        #expect(!contents.contains("excludes:"))
    }

    @Test
    func `patch replacement and deletion report missing files without changing the manifest`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest("features: {base: {}}", for: reference)
        let original = try Data(contentsOf: fixture.manifestURL(for: reference))

        try fixture.repository.replacePatch(
            Data("base patch\n".utf8),
            identifiedBy: .feature("base"),
            in: reference,
        )
        try fixture.repository.removePatch(identifiedBy: .feature("base"), in: reference)

        let patchURL = try fixture.patchURL(for: .feature("base"), in: reference)
        #expect(!FileManager.default.fileExists(atPath: patchURL.path))
        #expect(
            capturedPatchsetError({
                try fixture.repository.removePatch(
                    identifiedBy: .feature("base"),
                    in: reference,
                )
            }) == .patchNotFound(patchURL),
        )
        #expect(try Data(contentsOf: fixture.manifestURL(for: reference)) == original)
    }

    @Test
    func `feature addition rolls back its patch when manifest replacement fails`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest("features: {}", for: reference)
        let manifestURL = fixture.manifestURL(for: reference)
        let original = try Data(contentsOf: manifestURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: manifestURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.immutable: false],
                ofItemAtPath: manifestURL.path,
            )
        }

        let error = capturedPatchsetError({
            try fixture.repository.addFeature(.init(id: "base"), to: reference)
        })

        guard case .fileSystem(let operation, let failedURL, _)? = error else {
            Issue.record("Expected fileSystem.")
            return
        }
        let patchURL = try fixture.patchURL(for: .feature("base"), in: reference)
        #expect(operation == "write")
        #expect(failedURL == manifestURL)
        #expect(try Data(contentsOf: manifestURL) == original)
        #expect(!FileManager.default.fileExists(atPath: patchURL.path))
    }
}
