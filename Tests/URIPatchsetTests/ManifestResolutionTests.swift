import Testing
import URIModel
import URIPatchset

@Suite("Manifest Resolution")
struct ManifestResolutionTests {

    @Test
    func `legacy inheritance merges partial feature payloads from ancestor to child`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("patch1.0")
        let child = try fixture.reference("patch1.1")
        try fixture.writeManifest(
            """
            features:
              core: {}
              ui:
                name: Parent UI
                description: Parent description
                dependencies: [core]
            """,
            for: parent,
        )
        try fixture.writeManifest(
            """
            inherits: patch1.0
            features:
              ui:
                name: Child UI
              search:
                dependencies: [ui]
            """,
            for: child,
        )

        let resolved = try fixture.repository.resolve(child)

        #expect(resolved.inheritanceChain == [child, parent])
        #expect(resolved.features["core"]?.name == nil)
        #expect(resolved.features["ui"]?.name == "Child UI")
        #expect(resolved.features["ui"]?.description == "Parent description\n")
        #expect(resolved.features["ui"]?.dependencies == ["core"])
        #expect(resolved.features["search"]?.dependencies == ["ui"])
    }

    @Test
    func `structured inheritance keeps plus characters in both version axes`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("release+meta", "patch+base")
        let child = try fixture.reference("v1.2.4", "patch1.1")
        try fixture.writeManifest(
            """
            features:
              base: {}
            """,
            for: parent,
        )
        try fixture.writeManifest(
            """
            inherits:
              upstream-version: release+meta
              patchset-version: patch+base
            features: {}
            """,
            for: child,
        )

        let resolved = try fixture.repository.resolve(child)

        #expect(resolved.inheritanceChain == [child, parent])
        #expect(resolved.features.keys.sorted() == ["base"])
    }

    @Test
    func `an ancestor exclusion persists until a descendant redeclares the feature`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("patch1.0")
        let child = try fixture.reference("patch1.1")
        let grandchild = try fixture.reference("patch1.2")
        try fixture.writeManifest(
            """
            features:
              base: {}
              theme: {}
            """,
            for: parent,
        )
        try fixture.writeManifest(
            """
            inherits: patch1.0
            excludes: [theme]
            features: {}
            """,
            for: child,
        )
        try fixture.writeManifest(
            """
            inherits: patch1.1
            features:
              theme:
                name: Restored Theme
            """,
            for: grandchild,
        )

        let childFeatures = try fixture.repository.resolve(child).features
        let grandchildFeatures = try fixture.repository.resolve(grandchild).features

        #expect(childFeatures["theme"] == nil)
        #expect(grandchildFeatures["theme"]?.name == "Restored Theme")
        #expect(grandchildFeatures["base"] != nil)
    }

    @Test
    func `exclusions reject missing inherited and directly declared features`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("patch1.0")
        let missing = try fixture.reference("patch1.1")
        let conflict = try fixture.reference("patch1.2")
        try fixture.writeManifest("features: {base: {}}", for: parent)
        try fixture.writeManifest(
            """
            inherits: patch1.0
            excludes: [missing]
            features: {}
            """,
            for: missing,
        )
        try fixture.writeManifest(
            """
            inherits: patch1.0
            excludes: [base]
            features:
              base: {}
            """,
            for: conflict,
        )

        #expect(
            capturedPatchsetError({try fixture.repository.resolve(missing)})
                == .invalidExclusion(featureID: "missing", reference: missing),
        )
        #expect(
            capturedPatchsetError({try fixture.repository.resolve(conflict)})
                == .declaredAndExcluded(featureID: "base", reference: conflict),
        )
    }

    @Test
    func `inheritance cycles report the deterministic repeated chain`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let first = try fixture.reference("patch1.0")
        let second = try fixture.reference("patch1.1")
        try fixture.writeManifest("inherits: patch1.1", for: first)
        try fixture.writeManifest("inherits: patch1.0", for: second)

        let error = capturedPatchsetError({try fixture.repository.resolve(first)})

        #expect(error == .circularInheritance([first, second, first]))
    }

    @Test
    func `manifest loading rejects unknown schema keys before decoding`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let cases = [
            ("patch1.0", "unsupported: true", "unsupported"),
            (
                "patch1.1",
                """
                inherits:
                  upstream-version: v1.2.3
                  patchset-version: patch1.0
                  unsupported: true
                """,
                "unsupported"
            ),
            (
                "patch1.2",
                """
                features:
                  base:
                    unsupported: true
                """,
                "unsupported"
            ),
        ]

        for (patchsetVersion, yaml, unknownKey) in cases {
            let reference = try fixture.reference(patchsetVersion)
            try fixture.writeManifest(yaml, for: reference)
            let error = capturedPatchsetError({
                try fixture.repository.manifest(for: reference)
            })

            guard case .invalidManifest(_, let reason)? = error else {
                Issue.record("Expected invalidManifest for \(patchsetVersion).")
                continue
            }
            #expect(reason.contains(unknownKey))
        }
    }

    @Test
    func `structured inheritance requires both string version values`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            inherits:
              patchset-version: patch0.9
            """,
            for: reference,
        )

        let error = capturedPatchsetError({try fixture.repository.resolve(reference)})

        guard case .invalidManifest(_, let reason)? = error else {
            Issue.record("Expected invalidManifest.")
            return
        }
        #expect(reason.contains("upstream-version"))
    }

    @Test
    func `wire schema does not coerce numeric scalars to strings`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            features:
              base:
                dependencies: [123]
            """,
            for: reference,
        )

        let error = capturedPatchsetError({try fixture.repository.manifest(for: reference)})

        guard case .invalidManifest(_, let reason)? = error else {
            Issue.record("Expected invalidManifest.")
            return
        }
        #expect(reason.contains("only strings"))
    }

    @Test
    func `duplicate exclusions are reported at their declaring generation`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("patch1.0")
        let child = try fixture.reference("patch1.1")
        try fixture.writeManifest("features: {base: {}}", for: parent)
        try fixture.writeManifest(
            "inherits: patch1.0\nexcludes: [base, base]\nfeatures: {}",
            for: child,
        )

        #expect(
            capturedPatchsetError({try fixture.repository.resolve(child)})
                == .duplicateExclusion(featureID: "base", reference: child),
        )
    }
}
