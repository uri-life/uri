import Foundation
import Testing
import URIModel

@testable
import URIPatchset

@Suite("Manifest Writing")
struct ManifestWritingTests {

    @Test
    func `save writes the canonical manifest layout byte for byte`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.1")
        let manifest = PatchsetManifest(
            inherits: .detailed(
                .init(
                    upstreamVersion: "v1.2.3",
                    patchsetVersion: "patch1.0",
                ),
            ),
            excludes: [],
            features: [
                .init(
                    id: "search",
                    name: "Search",
                    description: "Search support",
                    dependencies: ["base"],
                    devDependencies: ["dev-tools"],
                ),
            ],
        )

        try save(manifest, as: reference, in: fixture)

        #expect(
            try contents(of: reference, in: fixture)
                == """
                inherits:
                  upstream-version: v1.2.3
                  patchset-version: patch1.0

                features:
                  search:
                    name: Search
                    description: |
                      Search support
                    dependencies:
                      - base
                    dev-dependencies:
                      - dev-tools

                """,
        )
    }

    @Test
    func `save omits nil and empty excludes but preserves a nonempty sequence`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")

        try save(.init(), as: reference, in: fixture)
        #expect(try contents(of: reference, in: fixture) == "{}\n")

        try save(
            .init(excludes: [], features: []),
            as: reference,
            in: fixture,
        )
        #expect(try contents(of: reference, in: fixture) == "features: {}\n")

        try save(
            .init(excludes: ["legacy", "experimental"]),
            as: reference,
            in: fixture,
        )
        #expect(
            try contents(of: reference, in: fixture)
                == """
                excludes:
                  - legacy
                  - experimental

                """,
        )
    }

    @Test
    func `save sorts features and preserves field and collection order`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        let manifest = PatchsetManifest(
            features: [
                .init(id: "zeta"),
                .init(
                    id: "alpha",
                    dependencies: [],
                    devDependencies: [],
                ),
                .init(
                    id: "middle",
                    dependencies: ["zeta", "alpha", "zeta"],
                ),
            ],
        )

        try save(manifest, as: reference, in: fixture)

        #expect(
            try contents(of: reference, in: fixture)
                == """
                features:
                  alpha:
                    dependencies: []
                    dev-dependencies: []
                  middle:
                    dependencies:
                      - zeta
                      - alpha
                      - zeta
                  zeta: {}

                """,
        )
    }

    @Test
    func `save quotes names and literal descriptions without changing model values`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        let manifest = PatchsetManifest(
            features: [
                .init(id: "boolean", name: "true"),
                .init(id: "empty", name: "null", description: ""),
                .init(
                    id: "indented",
                    description: "  indented\nnext",
                ),
                .init(
                    id: "line-endings",
                    name: "value: # text",
                    description: "First\r\n\rSecond\n\n",
                ),
                .init(
                    id: "unicode",
                    name: "검색 \"Search\"",
                    description: "key: value\n# comment",
                ),
            ],
        )

        try save(manifest, as: reference, in: fixture)
        let loaded = try ManifestStore(rootURL: fixture.rootURL).load(reference)
        let features = Dictionary(
            uniqueKeysWithValues: (loaded.features ?? []).map({($0.id, $0)}),
        )

        #expect(features["boolean"]?.name == "true")
        #expect(features["empty"]?.name == "null")
        #expect(features["empty"]?.description == "\n")
        #expect(features["indented"]?.description == "  indented\nnext\n")
        #expect(features["line-endings"]?.name == "value: # text")
        #expect(features["line-endings"]?.description == "First\n\nSecond\n")
        #expect(features["unicode"]?.name == "검색 \"Search\"")
        #expect(features["unicode"]?.description == "key: value\n# comment\n")
    }

    @Test
    func `save retains simple inheritance on one line`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.1")

        try save(
            .init(inherits: .simple("v1.2.3+patch1.0")),
            as: reference,
            in: fixture,
        )

        #expect(
            try contents(of: reference, in: fixture)
                == "inherits: v1.2.3+patch1.0\n",
        )
    }

    @Test
    func `save round trips a terminal newline only description with one file trailing newline`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")

        try save(
            .init(features: [.init(id: "only", description: "")]),
            as: reference,
            in: fixture,
        )
        let yaml = try contents(of: reference, in: fixture)
        let loaded = try ManifestStore(rootURL: fixture.rootURL).load(reference)

        #expect(yaml.hasSuffix("\n"))
        #expect(!yaml.hasSuffix("\n\n"))
        #expect(loaded.features?.first?.description == "\n")
    }

    private func save(
        _ manifest: PatchsetManifest,
        as reference: PatchsetReference,
        in fixture: PatchsetTestFixture,
    ) throws {
        try FileManager.default.createDirectory(
            at: fixture.manifestURL(for: reference).deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try ManifestStore(rootURL: fixture.rootURL).save(manifest, for: reference)
    }

    private func contents(
        of reference: PatchsetReference,
        in fixture: PatchsetTestFixture,
    ) throws -> String {
        try String(contentsOf: fixture.manifestURL(for: reference), encoding: .utf8)
    }
}
