import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing
import URIGit
import URIModel
import URIPatchset

@testable import URI

@Suite("Source Snapshot", .serialized)
struct SourceSnapshotTests {

    @Test
    func `HTTP snapshot downloads the complete inheritance chain and tolerates missing optional patches`() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let basePatchFilename = try PatchIdentifier.feature("base").filename
        let client = MockHTTPClient(responses: [
            "/patches/manifest.yaml": .init(
                status: 200,
                chunks: ["upstream: https://example.com/", "upstream.git\n"],
            ),
            "/patches/versions/v2/patches/p2/manifest.yaml": .init(
                status: 200,
                chunks: [
                    """
                    inherits:
                      upstream-version: v1
                      patchset-version: p1
                    features:
                      child:
                        dependencies: [base]

                    """
                ],
            ),
            "/patches/versions/v1/patches/p1/manifest.yaml": .init(
                status: 200,
                chunks: [
                    """
                    features:
                      base: {}

                    """
                ],
            ),
            "/patches/versions/v1/patches/p1/\(basePatchFilename)": .init(status: 200),
        ])
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            requestExecutor: {
                try await client.execute($0)
            },
        )
        let reference = try PatchsetReference(upstreamVersion: "v2", patchsetVersion: "p2")
        let resolved = try await resolver.resolve(
            .init(kind: .http, original: "https://example.com/patches"),
            reference: reference,
            includePatches: true,
        )
        defer { try? resolver.removeSnapshot(at: resolved.snapshotURL) }

        let patchset = try resolved.repository.resolve(reference)
        #expect(patchset.inheritanceChain.map(\.description) == ["v2+p2", "v1+p1"])
        #expect(try patchset.dependencyOrder(for: "child").map(\.id) == ["base", "child"])
        let patch = try #require(
            try resolved.repository.patch(for: "base", inheritedBy: reference),
        )
        #expect(try Data(contentsOf: patch.url).isEmpty)
        let requests = await client.recordedRequests()
        #expect(requests.allSatisfy({$0.method == .GET}))
        #expect(requests.allSatisfy({$0.headers.first(name: "User-Agent") == "uri/2"}))
    }

    @Test
    func `HTTP snapshot resolves two patchsets from one root and downloads their patch union`() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let firstPatch = try PatchIdentifier.feature("first").filename
        let secondPatch = try PatchIdentifier.feature("second").filename
        let client = MockHTTPClient(responses: [
            "/patches/manifest.yaml": .init(
                status: 200,
                chunks: ["upstream: https://example.com/upstream.git\n"],
            ),
            "/patches/versions/v1/patches/p1/manifest.yaml": .init(
                status: 200,
                chunks: ["features:\n  first: {}\n"],
            ),
            "/patches/versions/v2/patches/p2/manifest.yaml": .init(
                status: 200,
                chunks: ["features:\n  second: {}\n"],
            ),
            "/patches/versions/v1/patches/p1/\(firstPatch)": .init(
                status: 200,
                chunks: ["first patch\n"],
            ),
            "/patches/versions/v2/patches/p2/\(secondPatch)": .init(
                status: 200,
                chunks: ["second patch\n"],
            ),
        ])
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            requestExecutor: {
                try await client.execute($0)
            },
        )
        let first = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "p1")
        let second = try PatchsetReference(upstreamVersion: "v2", patchsetVersion: "p2")

        let resolved = try await resolver.resolve(
            .init(kind: .http, original: "https://example.com/patches"),
            references: [first, second],
            includePatches: true,
        )
        defer { try? resolver.removeSnapshot(at: resolved.snapshotURL) }

        #expect(Set(try resolved.repository.resolve(first).features.keys) == ["first"])
        #expect(Set(try resolved.repository.resolve(second).features.keys) == ["second"])
        #expect(
            try String(
                contentsOf: #require(
                    try resolved.repository.patch(for: "first", inheritedBy: first),
                ).url,
                encoding: .utf8,
            ) == "first patch\n",
        )
        #expect(
            try String(
                contentsOf: #require(
                    try resolved.repository.patch(for: "second", inheritedBy: second),
                ).url,
                encoding: .utf8,
            ) == "second patch\n",
        )
        let paths = await client.recordedRequests().compactMap({URL(string: $0.url)?.path})
        #expect(paths.filter({ $0 == "/patches/manifest.yaml" }).count == 1)
        #expect(paths.filter({ $0.hasSuffix("/manifest.yaml") }).count == 3)
    }

    @Test
    func `HTTP snapshot reports required 404 and non-success responses`() async throws {
        for status in [404, 500] {
            let home = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: home) }
            let client = MockHTTPClient(responses: [
                "/failure/manifest.yaml": .init(
                    status: status,
                    chunks: ["ignored", " response"],
                ),
            ])
            let resolver = PatchsetSourceResolver(
                paths: .init(homeURL: home),
                requestExecutor: {
                    try await client.execute($0)
                },
            )
            do {
                _ = try await resolver.resolve(
                    .init(kind: .http, original: "https://example.com/failure"),
                )
                Issue.record("Expected HTTP \(status).")
            }
            catch let error as URIError {
                #expect(
                    error == .http(
                        status: status,
                        url: "https://example.com/failure/manifest.yaml",
                    ),
                )
            }
            #expect(try operationSnapshots(in: home).isEmpty)
        }
    }

    @Test
    func `HTTP snapshot removes staged files after a body failure`() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let client = MockHTTPClient(responses: [
            "/failure/manifest.yaml": .init(
                status: 200,
                chunks: ["upstream: https://example.com/"],
                completion: .failure,
            ),
        ])
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            requestExecutor: {
                try await client.execute($0)
            },
        )

        await #expect(throws: MockHTTPError.self) {
            _ = try await resolver.resolve(
                .init(kind: .http, original: "https://example.com/failure"),
            )
        }
        #expect(try operationSnapshots(in: home).isEmpty)
    }

    @Test
    func `HTTP snapshot removes staged files after cancellation`() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let client = MockHTTPClient(responses: [
            "/cancelled/manifest.yaml": .init(
                status: 200,
                chunks: ["upstream: https://example.com/"],
                completion: .cancellation,
            ),
        ])
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            requestExecutor: {
                try await client.execute($0)
            },
        )

        await #expect(throws: CancellationError.self) {
            _ = try await resolver.resolve(
                .init(kind: .http, original: "https://example.com/cancelled"),
            )
        }
        #expect(try operationSnapshots(in: home).isEmpty)
    }

    @Test
    func `Git source snapshot remains pinned after the remote advances`() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appending(path: "origin", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let patchset = try PatchsetRepository(rootURL: origin)
        try patchset.initializeRoot(with: .init(upstream: "https://example.com/first.git"))
        _ = try git(["-C", origin.path, "init", "-q"])
        _ = try git(["-C", origin.path, "add", "manifest.yaml"])
        _ = try git([
            "-C", origin.path, "-c", "user.name=Source", "-c", "user.email=s@example.com",
            "commit", "-q", "-m", "Initial patchset",
        ])

        let resolver = PatchsetSourceResolver(paths: .init(homeURL: home))
        let resolved = try await resolver.resolve(.init(kind: .git, original: origin.path))
        defer { try? resolver.removeSnapshot(at: resolved.snapshotURL) }
        let snapshotGit = try await Git().openRepository(
            at: resolved.snapshotURL!.appending(path: "source"),
        )
        let pinnedCommit = try await snapshotGit.currentCommit()

        try patchset.saveRootManifest(.init(upstream: "https://example.com/second.git"))
        _ = try git(["-C", origin.path, "add", "manifest.yaml"])
        _ = try git([
            "-C", origin.path, "-c", "user.name=Source", "-c", "user.email=s@example.com",
            "commit", "-q", "-m", "Advance patchset",
        ])

        #expect(try resolved.repository.rootManifest().upstream == "https://example.com/first.git")
        #expect(try await snapshotGit.currentCommit() == pinnedCommit)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SourceSnapshotTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func operationSnapshots(in home: URL) throws -> [URL] {
        let cacheURL = RuntimePaths(homeURL: home).operationCacheURL
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: nil,
        )
    }

    private func git(_ arguments: [String]) throws -> Data {
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
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw URIError.fileSystem(
                "test git command failed: \(String(decoding: errorData, as: UTF8.self))",
            )
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

private enum MockHTTPError: Error {

    case interrupted
}

private actor MockHTTPClient {

    enum Completion: Sendable {

        case success

        case failure

        case cancellation
    }

    struct Response: Sendable {

        let status: Int

        let chunks: [Data]

        let completion: Completion

        init(
            status: Int,
            chunks: [String] = [],
            completion: Completion = .success,
        ) {
            self.status = status
            self.chunks = chunks.map({Data($0.utf8)})
            self.completion = completion
        }
    }

    private let responses: [String: Response]

    private var requests = [HTTPClientRequest]()

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func execute(_ request: HTTPClientRequest) throws -> HTTPClientResponse {
        requests.append(request)
        guard let path = URL(string: request.url)?.path else {
            throw MockHTTPError.interrupted
        }
        let response = responses[path] ?? .init(status: 404)
        let body = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
            for chunk in response.chunks {
                continuation.yield(ByteBuffer(bytes: chunk))
            }
            switch response.completion {
            case .success:
                continuation.finish()
            case .failure:
                continuation.finish(throwing: MockHTTPError.interrupted)
            case .cancellation:
                continuation.finish(throwing: CancellationError())
            }
        }
        return .init(
            status: HTTPResponseStatus(statusCode: response.status),
            body: .stream(body),
        )
    }

    func recordedRequests() -> [HTTPClientRequest] {
        requests
    }
}
