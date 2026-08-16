import Testing
import URIModel
import URIPatchset

@Suite("Dependency Resolution")
struct DependencyResolutionTests {

    @Test
    func `sorting is deterministic and ignores duplicate and self dependencies`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            features:
              alpha:
                dependencies: [alpha, alpha]
              base: {}
              feature:
                dependencies: [base, base, feature]
              standalone: {}
            """,
            for: reference,
        )

        let resolved = try fixture.repository.resolve(reference)
        let first = try resolved.orderedFeatures().map(\.id)
        let second = try resolved.orderedFeatures().map(\.id)

        #expect(first == ["alpha", "base", "feature", "standalone"])
        #expect(second == first)
    }

    @Test
    func `dependency closure optionally includes development dependencies recursively`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            features:
              base: {}
              dev-base: {}
              dev-middle:
                dependencies: [dev-base]
              feature:
                dependencies: [base]
                dev-dependencies: [dev-middle]
              unrelated: {}
            """,
            for: reference,
        )

        let resolved = try fixture.repository.resolve(reference)

        #expect(
            try resolved.dependencyOrder(for: "feature").map(\.id)
                == ["base", "feature"],
        )
        #expect(
            try resolved.dependencyOrder(
                for: "feature",
                in: .includingDevelopment,
            ).map(\.id) == ["base", "dev-base", "dev-middle", "feature"],
        )
    }

    @Test
    func `apply order excludes development only features but retains regular requirements`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            features:
              common: {}
              dev-helper:
                dependencies: [common]
              feature:
                dependencies: [common]
                dev-dependencies: [dev-helper]
            """,
            for: reference,
        )

        let resolved = try fixture.repository.resolve(reference)

        #expect(try resolved.applicationOrder().map(\.id) == ["common", "feature"])
    }

    @Test
    func `all missing regular and development dependencies are reported together`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            """
            features:
              alpha:
                dependencies: [regular-missing]
                dev-dependencies: [dev-missing]
              beta:
                dev-dependencies: [another-missing]
            """,
            for: reference,
        )

        let error = capturedPatchsetError({try fixture.repository.resolve(reference)})

        #expect(
            error == .missingDependencies([
                .init(
                    featureID: "alpha",
                    kind: .development,
                    dependencyID: "dev-missing",
                ),
                .init(
                    featureID: "alpha",
                    kind: .regular,
                    dependencyID: "regular-missing",
                ),
                .init(
                    featureID: "beta",
                    kind: .development,
                    dependencyID: "another-missing",
                ),
            ]),
        )
    }

    @Test
    func `regular and development cycles are both rejected with their nodes`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let regular = try fixture.reference("patch1.0")
        let development = try fixture.reference("patch1.1")
        try fixture.writeManifest(
            """
            features:
              alpha:
                dependencies: [beta]
              beta:
                dependencies: [alpha]
            """,
            for: regular,
        )
        try fixture.writeManifest(
            """
            features:
              alpha:
                dev-dependencies: [beta]
              beta:
                dev-dependencies: [alpha]
            """,
            for: development,
        )

        #expect(
            capturedPatchsetError({try fixture.repository.resolve(regular)})
                == .circularDependencies(["alpha", "beta"]),
        )
        #expect(
            capturedPatchsetError({try fixture.repository.resolve(development)})
                == .circularDependencies(["alpha", "beta"]),
        )
    }
}
