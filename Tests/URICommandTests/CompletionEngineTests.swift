import Foundation
import Testing
import URI
import URIModel
import URIPatchset

@testable
import URICommand

@Suite("Completion Engine")
struct CompletionEngineTests {

    @Test
    func `root command option and finite value candidates come from the command catalog`() {
        let engine = CompletionEngine()

        #expect(values(engine.complete(["ap"])) == ["apply"])
        #expect(values(engine.complete(["--color", "al"])) == ["always"])
        #expect(values(engine.complete(["graph", "--format=d"])) == ["--format=dot"])
        #expect(values(engine.complete(["list", "--ep"])) == ["--ephemeral"])
        #expect(values(engine.complete(["list", "--pa"])).isEmpty)
    }

    @Test
    func `local hierarchy candidates follow positional source version and patchset context`() throws {
        let fixture = try CompletionFixture()
        defer { fixture.remove() }

        #expect(values(fixture.engine.complete(["list", ""])).contains(["v1", "v2"]))
        #expect(
            values(fixture.engine.complete(["list", "v1", ""]))
                .contains(["base", "child", "open"]),
        )
        #expect(
            values(fixture.engine.complete(["list", fixture.rootURL.path, ""]))
                .contains(["v1", "v2"]),
        )
        #expect(values(fixture.engine.complete(["init", "v"])).isEmpty)
    }

    @Test
    func `feature candidates distinguish direct inherited excluded and active features`() throws {
        let fixture = try CompletionFixture()
        defer { fixture.remove() }

        #expect(positionalValues(fixture.engine.complete(["add", "v1", "open", ""])).isEmpty)
        #expect(
            positionalValues(fixture.engine.complete(["remove", "v1", "child", ""]))
                == ["direct"],
        )
        #expect(
            positionalValues(fixture.engine.complete(["exclude", "v1", "open", ""]))
                == ["inherited"],
        )
        #expect(
            positionalValues(fixture.engine.complete(["include", "v1", "child", ""]))
                == ["inherited"],
        )
        #expect(
            positionalValues(fixture.engine.complete(["expand", "v1", "open", ""]))
                .contains(["direct-open", "inherited"]),
        )
    }

    @Test
    func `dependency and inheritance option values support CSV equals and cross version forms`() throws {
        let fixture = try CompletionFixture()
        defer { fixture.remove() }

        #expect(
            values(
                fixture.engine.complete([
                    "add", "v1", "open", "new", "--dependencies", "in",
                ]),
            ) == ["inherited"],
        )
        #expect(
            values(
                fixture.engine.complete([
                    "add", "v1", "open", "new", "--dependencies=inherited,di",
                ]),
            ) == ["--dependencies=inherited,direct-open"],
        )
        #expect(
            values(
                fixture.engine.complete([
                    "add", "v1", "open", "new", "--dependencies", "inherited,",
                ]),
            ) == ["inherited,direct-open"],
        )
        #expect(
            values(
                fixture.engine.complete([
                    "add", "v1", "new", "--inherits", "",
                ]),
            ).contains(["base", "child", "open", "v2+other"]),
        )
        #expect(
            values(
                fixture.engine.complete([
                    "add", "v1", "new", "--inherits-upstream", "v2", "--inherits", "",
                ]),
            ) == ["other"],
        )
    }

    @Test
    func `TARGET completion separates new and existing ephemeral IDs by command form`() throws {
        let fixture = try CompletionFixture()
        defer { fixture.remove() }

        let start = fixture.engine.complete(["apply", "v1", "open", ""])
        #expect(values(start).contains("--ephemeral"))
        #expect(start.contains(.directories))
        #expect(
            values(
                fixture.engine.complete([
                    "apply", "v1", "open", "--ephemeral", "pe",
                ]),
            ).isEmpty,
        )
        #expect(
            values(
                fixture.engine.complete([
                    "apply", "--continue", "--ephemeral", "pe",
                ]),
            ) == ["peach"],
        )
        #expect(
            values(fixture.engine.complete(["collapse", "--ephemeral=pe"]))
                == ["--ephemeral=peach"],
        )
        #expect(values(fixture.engine.complete(["vanish", "pe"])) == ["peach"])
        #expect(!values(fixture.engine.complete(["list", "--ephemeral", ""])).contains("peach"))
    }

    @Test
    func `double dash and remote sources avoid special TARGET and repository lookup`() throws {
        let fixture = try CompletionFixture()
        defer { fixture.remove() }

        let literal = fixture.engine.complete([
            "apply", "v1", "open", "--", "--ephemeral",
        ])
        #expect(!values(literal).contains("--ephemeral"))
        #expect(literal.contains(.directories))

        let remote = fixture.engine.complete([
            "list", "https://example.com/patches", "",
        ])
        #expect(!values(remote).contains("v1"))
        #expect(fixture.engine.complete(["list", "--unknown", ""]).isEmpty)
    }

    private func values(_ records: [CompletionRecord]) -> [String] {
        records.compactMap({ record in
            guard case .candidate(let value, _) = record else {
                return nil
            }
            return value
        })
    }

    private func positionalValues(_ records: [CompletionRecord]) -> [String] {
        values(records).filter({ !$0.hasPrefix("-") })
    }
}

private struct CompletionFixture {

    let rootURL: URL

    let homeURL: URL

    let engine: CompletionEngine

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CompletionEngineTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let rootURL = directory.appending(path: "patchsets", directoryHint: .isDirectory)
        let homeURL = directory.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        let repository = try PatchsetRepository(rootURL: rootURL)
        try repository.initializeRoot(
            with: .init(
                upstream: "https://example.com/upstream.git",
                branchPrefix: "uri",
                committer: .repository,
            ),
        )
        try repository.createUpstreamVersion("v1")
        try repository.createUpstreamVersion("v2")

        let base = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "base")
        try repository.createPatchset(base)
        try repository.addFeature(.init(id: "inherited"), to: base)

        let child = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "child")
        try repository.createPatchset(child, inheriting: base)
        try repository.addFeature(.init(id: "direct"), to: child)
        try repository.excludeFeature("inherited", from: child)

        let open = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "open")
        try repository.createPatchset(open, inheriting: base)
        try repository.addFeature(.init(id: "direct-open"), to: open)

        let other = try PatchsetReference(upstreamVersion: "v2", patchsetVersion: "other")
        try repository.createPatchset(other)

        let paths = RuntimePaths(homeURL: homeURL)
        let manager = EphemeralWorkspaceManager(paths: paths)
        let workspace = try manager.create(requestedID: "peach")
        try FileManager.default.createDirectory(
            at: workspace.repositoryURL,
            withIntermediateDirectories: true,
        )
        try OperationStateStore().save(
            .init(
                mode: .apply,
                phase: .active,
                source: .init(
                    kind: .local,
                    original: rootURL.path,
                    localRootURL: rootURL,
                ),
                snapshotPath: nil,
                upstreamVersion: "v1",
                patchsetVersion: "open",
                feature: nil,
                featureOrder: ["inherited", "direct-open"],
                targetPath: workspace.repositoryURL.path,
                startCommit: String(repeating: "1", count: 40),
                startBranch: nil,
                baselineCommit: String(repeating: "1", count: 40),
                branchPrefix: "uri",
                committerName: "URI",
                committerEmail: "uri@uri.life",
                ephemeralID: "peach",
            ),
            to: workspace.stateURL,
        )

        self.rootURL = rootURL
        self.homeURL = homeURL
        self.engine = CompletionEngine(currentDirectoryURL: rootURL, paths: paths)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent())
    }
}

private extension Array<String> {

    func contains(_ expected: [String]) -> Bool {
        Set(expected).isSubset(of: Set(self))
    }
}
