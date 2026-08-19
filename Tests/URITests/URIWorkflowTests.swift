import Foundation
import Testing
import URIModel
import URIPatchset

@testable import URI

@Suite("URI Workflow")
struct URIWorkflowTests {

    @Test
    func `generic expand commit collapse and apply round trip through Git`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1.0.0", patchsetVersion: "p1")
        let paths = RuntimePaths(homeURL: fixture.home)
        let workflow = URIWorkflow(paths: paths)
        let operationIndex = OperationIndex(paths: paths)

        let expandTarget = try fixture.cloneTarget(named: "expand")
        let expanded = try await workflow.expand(
            source: source,
            reference: reference,
            featureID: "feature",
            targetURL: expandTarget,
            currentDirectoryURL: fixture.root,
            ephemeral: .none,
            includeDevelopmentDependencies: true,
            force: false,
        )
        #expect(expanded.branch == "uri/v1.0.0/p1/feature")
        #expect(
            try fixture.gitString(["-C", expandTarget.path, "branch", "--show-current"])
                == "uri/v1.0.0/p1/feature",
        )
        let expandedListings = try await operationIndex.list()
        #expect(expandedListings.count == 1)
        #expect(expandedListings[0].targetURL.path == expandTarget.path)
        #expect(expandedListings[0].state.mode == .expand)
        #expect(expandedListings[0].state.phase == .active)

        try fixture.write("base\nfeature\nedited\n", to: expandTarget.appending(path: "content.txt"))
        _ = try fixture.git(["-C", expandTarget.path, "add", "content.txt"])
        _ = try fixture.git([
            "-C", expandTarget.path, "-c", "user.name=Editor", "-c", "user.email=e@example.com",
            "commit", "-q", "-m", "Edit expanded feature",
        ])
        _ = try await workflow.collapse(
            targetURL: expandTarget,
            currentDirectoryURL: fixture.root,
            ephemeralID: nil,
            recursive: false,
            discard: false,
        )
        let savedPatch = try Data(
            contentsOf: fixture.patchset.appending(
                path: "versions/v1.0.0/patches/p1/feature.patch",
            ),
        )
        #expect(String(decoding: savedPatch, as: UTF8.self).contains("edited"))
        #expect(
            try fixture.gitString(["-C", expandTarget.path, "branch", "--show-current"]).isEmpty,
        )
        #expect(try await operationIndex.list().isEmpty)

        let applyTarget = try fixture.cloneTarget(named: "apply")
        let applied = try await workflow.apply(
            source: source,
            reference: reference,
            targetURL: applyTarget,
            currentDirectoryURL: fixture.root,
            ephemeral: .none,
        )
        #expect(applied.branch == "uri/v1.0.0/p1")
        #expect(
            try String(contentsOf: applyTarget.appending(path: "content.txt"), encoding: .utf8)
                == "base\nfeature\nedited\n",
        )
        #expect(try await operationIndex.list().isEmpty)
    }

    @Test
    func `dirty targets are rejected before checkout`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1.0.0", patchsetVersion: "p1")
        let target = try fixture.cloneTarget(named: "dirty")
        try fixture.write("dirty\n", to: target.appending(path: "untracked.txt"))

        await #expect(throws: URIError.self) {
            _ = try await URIWorkflow(paths: .init(homeURL: fixture.home)).apply(
                source: source,
                reference: reference,
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeral: .none,
            )
        }
        #expect(
            try fixture.gitString(["-C", target.path, "branch", "--show-current"])
                != "uri/v1.0.0/p1",
        )
    }

    @Test
    func `index registration failure leaves the target checkout and state unchanged`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let reference = try PatchsetReference(upstreamVersion: "v1.0.0", patchsetVersion: "p1")
        let target = try fixture.cloneTarget(named: "index-failure")
        let startingBranch = try fixture.gitString(["-C", target.path, "branch", "--show-current"])
        let startingCommit = try fixture.gitString(["-C", target.path, "rev-parse", "HEAD"])
        let paths = RuntimePaths(homeURL: fixture.home)
        try FileManager.default.createDirectory(
            at: paths.rootURL,
            withIntermediateDirectories: true,
        )
        try Data().write(to: paths.operationIndexURL)

        await #expect(throws: URIError.self) {
            _ = try await URIWorkflow(paths: paths).expand(
                source: source,
                reference: reference,
                featureID: "feature",
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeral: .none,
                includeDevelopmentDependencies: true,
                force: false,
            )
        }

        #expect(try fixture.gitString(["-C", target.path, "branch", "--show-current"])
            == startingBranch)
        #expect(try fixture.gitString(["-C", target.path, "rev-parse", "HEAD"])
            == startingCommit)
        #expect(
            !FileManager.default.fileExists(
                atPath: target.appending(path: ".git/uri/state.json").path,
            ),
        )
    }

    @Test
    func `expand conflict can be resolved and continued from saved workflow state`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let reference = try fixture.prepareConflictPatchset()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let target = try fixture.cloneTarget(named: "continue")
        let paths = RuntimePaths(homeURL: fixture.home)
        let workflow = URIWorkflow(paths: paths)

        await #expect(throws: URIError.self) {
            _ = try await workflow.expand(
                source: source,
                reference: reference,
                featureID: "feature",
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeral: .none,
                includeDevelopmentDependencies: true,
                force: false,
            )
        }
        let operationIndex = OperationIndex(paths: paths)
        let interruptedListings = try await operationIndex.list()
        #expect(interruptedListings.count == 1)
        #expect(interruptedListings[0].state.mode == .expand)
        #expect(interruptedListings[0].state.phase != .active)
        let indexStore = OperationIndexStore(paths: paths)
        try indexStore.remove(targetURL: target)
        #expect(try await operationIndex.list().isEmpty)
        try fixture.write("resolved\n", to: target.appending(path: "content.txt"))
        _ = try fixture.git(["-C", target.path, "add", "content.txt"])

        let result = try await workflow.continue(
            mode: .expand,
            targetURL: target,
            currentDirectoryURL: fixture.root,
            ephemeralID: nil,
        )
        #expect(result.branch == "uri/v1.0.0/conflict/feature")
        #expect(
            try String(contentsOf: target.appending(path: "content.txt"), encoding: .utf8)
                == "resolved\n",
        )
        let continuedListings = try await operationIndex.list()
        #expect(continuedListings.count == 1)
        #expect(continuedListings[0].state.phase == .active)
        try indexStore.remove(targetURL: target)
        try FileManager.default.removeItem(at: paths.operationIndexURL)
        try Data().write(to: paths.operationIndexURL)

        await #expect(throws: URIError.self) {
            _ = try await workflow.collapse(
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeralID: nil,
                recursive: false,
                discard: true,
            )
        }
        #expect(
            FileManager.default.fileExists(
                atPath: target.appending(path: ".git/uri/state.json").path,
            ),
        )
        #expect(try fixture.gitString(["-C", target.path, "branch", "--show-current"])
            == result.branch)
        try FileManager.default.removeItem(at: paths.operationIndexURL)

        _ = try await workflow.collapse(
            targetURL: target,
            currentDirectoryURL: fixture.root,
            ephemeralID: nil,
            recursive: false,
            discard: true,
        )
        #expect(try await operationIndex.list().isEmpty)
    }

    @Test
    func `apply conflict abort restores the starting branch commit and state`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let reference = try fixture.prepareConflictPatchset()
        let source = try PatchsetSourceLocator.locate(
            fixture.patchset.path,
            currentDirectoryURL: fixture.root,
        )
        let target = try fixture.cloneTarget(named: "abort")
        let startingBranch = try fixture.gitString(["-C", target.path, "branch", "--show-current"])
        let startingCommit = try fixture.gitString(["-C", target.path, "rev-parse", "HEAD"])
        let paths = RuntimePaths(homeURL: fixture.home)
        let workflow = URIWorkflow(paths: paths)

        await #expect(throws: URIError.self) {
            _ = try await workflow.apply(
                source: source,
                reference: reference,
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeral: .none,
            )
        }
        let operationIndex = OperationIndex(paths: paths)
        let interruptedListings = try await operationIndex.list()
        #expect(interruptedListings.count == 1)
        #expect(interruptedListings[0].state.mode == .apply)
        #expect(interruptedListings[0].state.phase != .active)
        try OperationIndexStore(paths: paths).remove(targetURL: target)
        try FileManager.default.removeItem(at: paths.operationIndexURL)
        try Data().write(to: paths.operationIndexURL)

        await #expect(throws: URIError.self) {
            _ = try await workflow.abort(
                mode: .apply,
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeralID: nil,
            )
        }
        #expect(
            FileManager.default.fileExists(
                atPath: target.appending(path: ".git/uri/state.json").path,
            ),
        )
        try FileManager.default.removeItem(at: paths.operationIndexURL)

        _ = try await workflow.abort(
            mode: .apply,
            targetURL: target,
            currentDirectoryURL: fixture.root,
            ephemeralID: nil,
        )

        #expect(try fixture.gitString(["-C", target.path, "branch", "--show-current"])
            == startingBranch)
        #expect(try fixture.gitString(["-C", target.path, "rev-parse", "HEAD"])
            == startingCommit)
        #expect(
            try String(contentsOf: target.appending(path: "content.txt"), encoding: .utf8)
                == "base\n",
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: target.appending(path: ".git/uri/state.json").path,
            ),
        )
        #expect(try await operationIndex.list().isEmpty)
    }

    @Test
    func `remote source snapshot survives conflict and is removed after abort`() async throws {
        let fixture = try GenericWorkflowFixture()
        defer { fixture.remove() }
        try fixture.prepare()
        let reference = try fixture.prepareConflictPatchset()
        _ = try fixture.git(["-C", fixture.patchset.path, "init", "-q"])
        _ = try fixture.git(["-C", fixture.patchset.path, "add", "."])
        _ = try fixture.git([
            "-C", fixture.patchset.path, "-c", "user.name=Source", "-c",
            "user.email=s@example.com", "commit", "-q", "-m", "Patchset snapshot",
        ])
        let target = try fixture.cloneTarget(named: "remote-conflict")
        let workflow = URIWorkflow(paths: .init(homeURL: fixture.home))

        await #expect(throws: URIError.self) {
            _ = try await workflow.expand(
                source: .init(kind: .git, original: fixture.patchset.path),
                reference: reference,
                featureID: "feature",
                targetURL: target,
                currentDirectoryURL: fixture.root,
                ephemeral: .none,
                includeDevelopmentDependencies: true,
                force: false,
            )
        }
        let stateURL = target.appending(path: ".git/uri/state.json")
        let state = try OperationStateStore().load(from: stateURL)
        let snapshotPath = try #require(state.snapshotPath)
        #expect(FileManager.default.fileExists(atPath: snapshotPath))

        _ = try await workflow.abort(
            mode: .expand,
            targetURL: target,
            currentDirectoryURL: fixture.root,
            ephemeralID: nil,
        )
        #expect(!FileManager.default.fileExists(atPath: snapshotPath))
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
    }
}

private final class GenericWorkflowFixture {

    let root: URL
    let home: URL
    let upstream: URL
    let patchset: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "URIWorkflowTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        home = root.appending(path: "home", directoryHint: .isDirectory)
        upstream = root.appending(path: "upstream", directoryHint: .isDirectory)
        patchset = root.appending(path: "patchset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: patchset, withIntermediateDirectories: true)
    }

    func prepare() throws {
        _ = try git(["-C", upstream.path, "init", "-q"])
        try write("base\n", to: upstream.appending(path: "content.txt"))
        _ = try git(["-C", upstream.path, "add", "content.txt"])
        _ = try git([
            "-C", upstream.path, "-c", "user.name=Upstream", "-c", "user.email=u@example.com",
            "commit", "-q", "-m", "Base",
        ])
        _ = try git(["-C", upstream.path, "-c", "tag.gpgSign=false", "tag", "v1.0.0"])

        let repository = try PatchsetRepository(rootURL: patchset)
        try repository.initializeRoot(
            with: .init(
                upstream: upstream.path,
                branchPrefix: "uri",
                committer: .explicit(.init(name: "URI", email: "uri@example.com")),
            ),
        )
        try repository.createUpstreamVersion("v1.0.0")
        let reference = try PatchsetReference(upstreamVersion: "v1.0.0", patchsetVersion: "p1")
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "feature", name: "Feature"), to: reference)

        let author = root.appending(path: "author", directoryHint: .isDirectory)
        _ = try git(["clone", "-q", upstream.path, author.path])
        try write("base\nfeature\n", to: author.appending(path: "content.txt"))
        _ = try git(["-C", author.path, "add", "content.txt"])
        _ = try git([
            "-C", author.path, "-c", "user.name=Author", "-c", "user.email=a@example.com",
            "commit", "-q", "-m", "Add feature",
        ])
        let patch = try git(["-C", author.path, "format-patch", "--stdout", "HEAD~1..HEAD"]).output
        try repository.replacePatch(patch, identifiedBy: .feature("feature"), in: reference)
    }

    func cloneTarget(named name: String) throws -> URL {
        let target = root.appending(path: name, directoryHint: .isDirectory)
        _ = try git(["clone", "-q", upstream.path, target.path])
        return target
    }

    func prepareConflictPatchset() throws -> PatchsetReference {
        let repository = try PatchsetRepository(rootURL: patchset)
        let reference = try PatchsetReference(
            upstreamVersion: "v1.0.0",
            patchsetVersion: "conflict",
        )
        try repository.createPatchset(reference)
        try repository.addFeature(.init(id: "dependency"), to: reference)
        try repository.addFeature(
            .init(id: "feature", dependencies: ["dependency"]),
            to: reference,
        )
        try repository.replacePatch(
            authorPatch(named: "dependency-author", content: "dependency\n"),
            identifiedBy: .feature("dependency"),
            in: reference,
        )
        try repository.replacePatch(
            authorPatch(named: "feature-author", content: "feature\n"),
            identifiedBy: .feature("feature"),
            in: reference,
        )
        return reference
    }

    private func authorPatch(named name: String, content: String) throws -> Data {
        let author = root.appending(path: name, directoryHint: .isDirectory)
        _ = try git(["clone", "-q", upstream.path, author.path])
        try write(content, to: author.appending(path: "content.txt"))
        _ = try git(["-C", author.path, "add", "content.txt"])
        _ = try git([
            "-C", author.path, "-c", "user.name=Author", "-c", "user.email=a@example.com",
            "commit", "-q", "-m", "Change content for \(name)",
        ])
        return try git(["-C", author.path, "format-patch", "--stdout", "HEAD~1..HEAD"]).output
    }

    func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url)
    }

    func git(_ arguments: [String]) throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
            ],
            uniquingKeysWith: { _, override in override },
        )
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let result = (
            process.terminationStatus,
            output.fileHandleForReading.readDataToEndOfFile(),
            error.fileHandleForReading.readDataToEndOfFile()
        )
        guard result.0 == 0 else {
            Issue.record(
                "git \(arguments.joined(separator: " ")) failed: \(String(decoding: result.2, as: UTF8.self))",
            )
            throw URIError.fileSystem("test git command failed")
        }
        return result
    }

    func gitString(_ arguments: [String]) throws -> String {
        String(decoding: try git(arguments).output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
