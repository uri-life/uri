import Foundation
import Testing
import URIModel
import URIPatchset

@testable import URI

@Suite("Feature Diff")
struct FeatureDiffTests {

    @Test
    func `different upstreams dependencies and commit series with one net effect produce no output`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        let operands = try fixture.prepare()

        let output = try await fixture.differ.compare(
            source: fixture.source,
            from: operands.from,
            to: operands.equivalent,
        )

        #expect(output.isEmpty)
    }

    @Test
    func `changed net effects use stable operand labels and retain patch context`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        let operands = try fixture.prepare()

        let output = try await fixture.differ.compare(
            source: fixture.source,
            from: operands.from,
            to: operands.changed,
        )

        #expect(output.hasPrefix("--- v1 p1 feature\n+++ v2 p3 renamed-feature\n"))
        #expect(output.contains("-+second"))
        #expect(output.contains("++changed"))
        #expect(output.contains("@@ -0,0 +1,2 @@"))
        #expect(!output.contains("index "))
        #expect(!output.contains(fixture.root.path))
        let hunkHeaders = output.split(separator: "\n").filter({$0.hasPrefix("@@")})
        #expect(!hunkHeaders.isEmpty)
        #expect(hunkHeaders.allSatisfy({$0.hasSuffix("@@")}))
    }

    @Test
    func `Git patchset source uses one disposable snapshot and removes it after comparison`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        let operands = try fixture.prepare()
        let source = try fixture.gitSource()

        let output = try await fixture.differ.compare(
            source: source,
            from: operands.from,
            to: operands.equivalent,
        )

        #expect(output.isEmpty)
        let cache = RuntimePaths(homeURL: fixture.home).operationCacheURL
        let snapshots =
            (try? FileManager.default.contentsOfDirectory(
                at: cache,
                includingPropertiesForKeys: nil,
            )) ?? []
        #expect(snapshots.isEmpty)
    }

    @Test
    func `ANTE main and POST patches contribute to the compared feature effect`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        _ = try fixture.prepare()
        let operands = try fixture.phasedOperands()

        let output = try await fixture.differ.compare(
            source: fixture.source,
            from: operands.from,
            to: operands.to,
        )

        #expect(output.contains("ante.txt"))
        #expect(output.contains("main.txt"))
        #expect(output.contains("-+post one"))
        #expect(output.contains("++post two"))
    }

    @Test
    func `unresolved reconstruction conflict identifies the selected operand and phase`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        let operands = try fixture.prepare()
        let conflicted = try fixture.conflictedOperand()

        do {
            _ = try await fixture.differ.compare(
                source: fixture.source,
                from: conflicted,
                to: operands.equivalent,
            )
            Issue.record("Expected a reconstruction conflict.")
        }
        catch let error as URIError {
            #expect(
                error
                    == .conflict(
                        "Conflict while reconstructing --from feature feature main patch.",
                    ),
            )
        }
    }

    @Test
    func `pair resolution completes both reconstructions before net effect comparison`() async throws {
        let fixture = try FeatureDiffFixture()
        defer { fixture.remove() }
        _ = try fixture.prepare()
        let operand = try fixture.pairResolvedOperand()

        let output = try await fixture.differ.compare(
            source: fixture.source,
            from: operand,
            to: operand,
        )

        #expect(output.isEmpty)
    }
}

private final class FeatureDiffFixture {

    struct PhasedOperands {

        let from: FeatureDiffOperand

        let to: FeatureDiffOperand
    }

    struct Operands {

        let from: FeatureDiffOperand

        let equivalent: FeatureDiffOperand

        let changed: FeatureDiffOperand
    }

    let root: URL

    let home: URL

    let upstream: URL

    let patchset: URL

    var differ: FeatureDiffer {
        .init(paths: .init(homeURL: home))
    }

    var source: PatchsetSource {
        .init(kind: .local, original: patchset.path, localRootURL: patchset)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "FeatureDiffTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        home = root.appending(path: "home", directoryHint: .isDirectory)
        upstream = root.appending(path: "upstream", directoryHint: .isDirectory)
        patchset = root.appending(path: "patchset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: patchset, withIntermediateDirectories: true)
    }

    func prepare() throws -> Operands {
        try prepareUpstream()
        let repository = try PatchsetRepository(rootURL: patchset)
        try repository.initializeRoot(with: .init(upstream: upstream.path))
        for version in ["v1", "v2"] {
            try repository.createUpstreamVersion(version)
        }

        let fromReference = try makePatchset(
            repository,
            version: "v1",
            patchsetVersion: "p1",
            dependencyID: "old-dependency",
            featureID: "feature",
            featureContents: ["first\n", "first\nsecond\n"],
        )
        let equivalentReference = try makePatchset(
            repository,
            version: "v2",
            patchsetVersion: "p2",
            dependencyID: "new-dependency",
            featureID: "feature",
            featureContents: ["first\nsecond\n"],
            developmentDependencyID: "development-only",
        )
        let changedReference = try makePatchset(
            repository,
            version: "v2",
            patchsetVersion: "p3",
            dependencyID: "new-dependency",
            featureID: "renamed-feature",
            featureContents: ["first\nchanged\n"],
        )

        return .init(
            from: .init(reference: fromReference, featureID: "feature"),
            equivalent: .init(reference: equivalentReference, featureID: "feature"),
            changed: .init(reference: changedReference, featureID: "renamed-feature"),
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func gitSource() throws -> PatchsetSource {
        _ = try git(["-C", patchset.path, "init", "-q", "--initial-branch=main"])
        _ = try git(["-C", patchset.path, "add", "."])
        try commit(in: patchset, paths: [], message: "Patchsets")
        return .init(kind: .git, original: patchset.path)
    }

    func phasedOperands() throws -> PhasedOperands {
        let repository = try PatchsetRepository(rootURL: patchset)
        let from = try makePhasedPatchset(
            repository,
            version: "v1",
            patchsetVersion: "phased-one",
            suffix: "one",
        )
        let to = try makePhasedPatchset(
            repository,
            version: "v2",
            patchsetVersion: "phased-two",
            suffix: "two",
        )
        return .init(
            from: .init(reference: from, featureID: "feature"),
            to: .init(reference: to, featureID: "feature"),
        )
    }

    func conflictedOperand() throws -> FeatureDiffOperand {
        let repository = try PatchsetRepository(rootURL: patchset)
        let reference = try PatchsetReference(
            upstreamVersion: "v1",
            patchsetVersion: "conflicted",
        )
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "dependency"), to: reference)
        try repository.addFeature(
            .init(id: "feature", dependencies: ["dependency"]),
            to: reference,
        )
        try repository.replacePatch(
            patch(
                version: "v1",
                name: "conflicted-dependency",
                path: "upstream.txt",
                contents: ["dependency\n"],
            ),
            identifiedBy: .feature("dependency"),
            in: reference,
        )
        try repository.replacePatch(
            patch(
                version: "v1",
                name: "conflicted-feature",
                path: "upstream.txt",
                contents: ["feature\n"],
            ),
            identifiedBy: .feature("feature"),
            in: reference,
        )
        return .init(reference: reference, featureID: "feature")
    }

    func pairResolvedOperand() throws -> FeatureDiffOperand {
        let repository = try PatchsetRepository(rootURL: patchset)
        let reference = try PatchsetReference(
            upstreamVersion: "v1",
            patchsetVersion: "pair-resolved",
        )
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "dependency"), to: reference)
        try repository.addFeature(
            .init(id: "feature", dependencies: ["dependency"]),
            to: reference,
        )
        let dependencyPatch = try patch(
            version: "v1",
            name: "pair-dependency",
            path: "upstream.txt",
            contents: ["dependency\n"],
        )
        let featurePatch = try patch(
            version: "v1",
            name: "pair-feature",
            path: "upstream.txt",
            contents: ["feature\n"],
        )
        try repository.replacePatch(
            dependencyPatch,
            identifiedBy: .feature("dependency"),
            in: reference,
        )
        try repository.replacePatch(
            featurePatch,
            identifiedBy: .feature("feature"),
            in: reference,
        )

        let work = root.appending(path: "pair-work", directoryHint: .isDirectory)
        let dependencyURL = root.appending(path: "pair-dependency.patch")
        let featureURL = root.appending(path: "pair-feature.patch")
        try dependencyPatch.write(to: dependencyURL)
        try featurePatch.write(to: featureURL)
        _ = try git(["clone", "-q", "--branch", "v1", upstream.path, work.path])
        let identity = [
            "-c", "user.name=URI",
            "-c", "user.email=uri@example.com",
            "-c", "commit.gpgSign=false",
        ]
        _ = try git(["-C", work.path] + identity + ["am", "--3way", dependencyURL.path])
        let conflict = try gitResult(
            ["-C", work.path] + identity + ["am", "--3way", featureURL.path],
        )
        guard conflict.status != 0 else {
            throw URIError.fileSystem("test feature patch did not conflict")
        }
        let conflictContents = try String(
            contentsOf: work.appending(path: "upstream.txt"),
            encoding: .utf8,
        )
        var conflictLines = conflictContents.split(
            separator: "\n",
            omittingEmptySubsequences: false,
        ).map(String.init)
        if conflictLines.last?.isEmpty == true {
            conflictLines.removeLast()
        }
        let removed = conflictLines.map({"-\($0)"}).joined(separator: "\n")
        let resolution = Data(
            """
            diff --git a/upstream.txt b/upstream.txt
            --- a/upstream.txt
            +++ b/upstream.txt
            @@ -1,\(conflictLines.count) +1 @@
            \(removed)
            +resolved

            """.utf8,
        )
        _ = try git(["-C", work.path] + identity + ["am", "--abort"])
        try repository.replacePatch(
            resolution,
            identifiedBy: .pair(current: "feature", completed: "dependency"),
            in: reference,
        )
        return .init(reference: reference, featureID: "feature")
    }

    private func prepareUpstream() throws {
        _ = try git(["-C", upstream.path, "init", "-q", "--initial-branch=main"])
        try write("upstream one\n", to: upstream.appending(path: "upstream.txt"))
        try commit(in: upstream, paths: ["upstream.txt"], message: "Upstream v1")
        _ = try git(["-C", upstream.path, "tag", "v1"])
        try write("upstream two\n", to: upstream.appending(path: "upstream.txt"))
        try commit(in: upstream, paths: ["upstream.txt"], message: "Upstream v2")
        _ = try git(["-C", upstream.path, "tag", "v2"])
    }

    private func makePatchset(
        _ repository: PatchsetRepository,
        version: String,
        patchsetVersion: String,
        dependencyID: String,
        featureID: String,
        featureContents: [String],
        developmentDependencyID: String? = nil,
    ) throws -> PatchsetReference {
        let reference = try PatchsetReference(
            upstreamVersion: version,
            patchsetVersion: patchsetVersion,
        )
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: dependencyID), to: reference)
        if let developmentDependencyID {
            try repository.addFeature(.init(id: developmentDependencyID), to: reference)
            try repository.replacePatch(
                patch(
                    version: version,
                    name: "\(patchsetVersion)-development",
                    path: "development.txt",
                    contents: ["development\n"],
                ),
                identifiedBy: .feature(developmentDependencyID),
                in: reference,
            )
        }
        try repository.addFeature(
            .init(
                id: featureID,
                dependencies: [dependencyID],
                devDependencies: developmentDependencyID.map({[$0]}),
            ),
            to: reference,
        )
        try repository.replacePatch(
            patch(
                version: version,
                name: "\(patchsetVersion)-dependency",
                path: "\(dependencyID).txt",
                contents: ["dependency\n"],
            ),
            identifiedBy: .feature(dependencyID),
            in: reference,
        )
        try repository.replacePatch(
            patch(
                version: version,
                name: "\(patchsetVersion)-feature",
                path: "feature.txt",
                contents: featureContents,
            ),
            identifiedBy: .feature(featureID),
            in: reference,
        )
        return reference
    }

    private func makePhasedPatchset(
        _ repository: PatchsetRepository,
        version: String,
        patchsetVersion: String,
        suffix: String,
    ) throws -> PatchsetReference {
        let reference = try PatchsetReference(
            upstreamVersion: version,
            patchsetVersion: patchsetVersion,
        )
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "feature"), to: reference)
        try repository.replacePatch(
            patch(
                version: version,
                name: "\(patchsetVersion)-ante",
                path: "ante.txt",
                contents: ["ante \(suffix)\n"],
            ),
            identifiedBy: .ante("feature"),
            in: reference,
        )
        try repository.replacePatch(
            patch(
                version: version,
                name: "\(patchsetVersion)-main",
                path: "main.txt",
                contents: ["main \(suffix)\n"],
            ),
            identifiedBy: .feature("feature"),
            in: reference,
        )
        try repository.replacePatch(
            patch(
                version: version,
                name: "\(patchsetVersion)-post",
                path: "post.txt",
                contents: ["post \(suffix)\n"],
            ),
            identifiedBy: .post("feature"),
            in: reference,
        )
        return reference
    }

    private func patch(
        version: String,
        name: String,
        path: String,
        contents: [String],
    ) throws -> Data {
        let author = root.appending(path: name, directoryHint: .isDirectory)
        _ = try git(["clone", "-q", "--branch", version, upstream.path, author.path])
        let base = try gitString(["-C", author.path, "rev-parse", "HEAD"])
        for (index, content) in contents.enumerated() {
            try write(content, to: author.appending(path: path))
            try commit(in: author, paths: [path], message: "Feature step \(index + 1)")
        }
        return try git([
            "-C", author.path, "format-patch", "--binary", "--stdout", "\(base)..HEAD",
        ])
    }

    private func commit(
        in repository: URL,
        paths: [String],
        message: String,
    ) throws {
        if !paths.isEmpty {
            _ = try git(["-C", repository.path, "add", "--"] + paths)
        }
        _ = try git([
            "-C", repository.path,
            "-c", "user.name=Author",
            "-c", "user.email=author@example.com",
            "-c", "commit.gpgSign=false",
            "commit", "-q", "-m", message,
        ])
    }

    private func write(
        _ value: String,
        to url: URL,
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(value.utf8).write(to: url)
    }

    private func git(_ arguments: [String]) throws -> Data {
        let result = try gitResult(arguments)
        guard result.status == 0 else {
            throw URIError.fileSystem(
                "git \(arguments.joined(separator: " ")) failed: \(String(decoding: result.error, as: UTF8.self))",
            )
        }
        return result.output
    }

    private func gitResult(
        _ arguments: [String],
    ) throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
            ],
            uniquingKeysWith: { _, override in override },
        )
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, data, errorData)
    }

    private func gitString(_ arguments: [String]) throws -> String {
        String(decoding: try git(arguments), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
