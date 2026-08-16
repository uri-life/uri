import Foundation
import Testing
import URIModel

@Suite("Patchset Manifest")
struct PatchsetManifestTests {

    @Test
    func `PatchsetManifest initialization defaults every field to nil`() {
        let manifest = PatchsetManifest()

        #expect(manifest.inherits == nil)
        #expect(manifest.excludes == nil)
        #expect(manifest.features == nil)
    }

    @Test
    func `PatchsetManifest initialization preserves every field`() {
        let inherits =
            PatchsetManifest.Inherits.detailed(
                .init(
                    upstreamVersion: "v4.5.0",
                    patchsetVersion: "uri1",
                ),
            )
        let features: Set<Feature> = [
            .init(id: "core", name: "Core"),
        ]
        let manifest =
            PatchsetManifest(
                inherits: inherits,
                excludes: ["legacy"],
                features: features,
            )

        #expect(manifest.inherits == inherits)
        #expect(manifest.excludes == ["legacy"])
        #expect(manifest.features == features)
    }

    @Test
    func `an empty PatchsetManifest omits optional keys when encoded`() throws {
        let data = try encoder.encode(PatchsetManifest())

        #expect(String(decoding: data, as: UTF8.self) == "{}")
        #expect(try decoder.decode(PatchsetManifest.self, from: data) == PatchsetManifest())
    }

    @Test
    func `simple inheritance round-trips through Codable`() throws {
        let manifest =
            PatchsetManifest(
                inherits: .simple("v4.5.0+uri1"),
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PatchsetManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"inherits":"v4.5.0+uri1"}"#,
        )
    }

    @Test
    func `detailed inheritance round-trips with manifest wire keys`() throws {
        let manifest =
            PatchsetManifest(
                inherits: .detailed(
                    .init(
                        upstreamVersion: "v4.5.0",
                        patchsetVersion: "uri1",
                    ),
                ),
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PatchsetManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"inherits":{"patchset-version":"uri1","upstream-version":"v4.5.0"}}"#,
        )
    }

    @Test
    func `detailed inheritance omits an absent upstream version`() throws {
        let manifest =
            PatchsetManifest(
                inherits: .detailed(
                    .init(patchsetVersion: "uri1"),
                ),
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PatchsetManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"inherits":{"patchset-version":"uri1"}}"#,
        )
    }

    @Test
    func `feature maps round-trip IDs and optional payload fields`() throws {
        let manifest =
            PatchsetManifest(
                excludes: ["legacy", "experimental"],
                features: [
                    .init(
                        id: "search",
                        name: "Search",
                        description: "Adds search",
                        dependencies: ["core"],
                        devDependencies: ["fixtures"],
                    ),
                    .init(id: "core", name: "Core"),
                ],
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(PatchsetManifest.self, from: data)
        let decodedCore = decoded.features?.first(where: {$0.id == "core"})
        let decodedSearch = decoded.features?.first(where: {$0.id == "search"})

        #expect(decoded == manifest)
        #expect(decoded.excludes == ["legacy", "experimental"])
        #expect(decoded.features?.count == 2)
        #expect(decodedCore?.name == "Core")
        #expect(decodedCore?.description == nil)
        #expect(decodedCore?.dependencies == nil)
        #expect(decodedCore?.devDependencies == nil)
        #expect(decodedSearch?.name == "Search")
        #expect(decodedSearch?.description == "Adds search\n")
        #expect(decodedSearch?.dependencies == ["core"])
        #expect(decodedSearch?.devDependencies == ["fixtures"])
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"excludes":["legacy","experimental"],"features":{"core":{"name":"Core"},"search":{"dependencies":["core"],"description":"Adds search\n","dev-dependencies":["fixtures"],"name":"Search"}}}"#,
        )
    }

    @Test
    func `an empty feature payload decodes with no name`() throws {
        let data = Data(#"{"features":{"core":{}}}"#.utf8)

        let manifest = try decoder.decode(PatchsetManifest.self, from: data)
        let feature = manifest.features?.first

        #expect(feature?.id == "core")
        #expect(feature?.name == nil)
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
