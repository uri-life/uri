import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
        unsafe MockURLProtocol.responses = [
            "/patches/manifest.yaml": .init(
                status: 200,
                body: "upstream: https://example.com/upstream.git\n",
            ),
            "/patches/versions/v2/patches/p2/manifest.yaml": .init(
                status: 200,
                body:
                    """
                    inherits:
                      upstream-version: v1
                      patchset-version: p1
                    features:
                      child:
                        dependencies: [base]

                    """,
            ),
            "/patches/versions/v1/patches/p1/manifest.yaml": .init(
                status: 200,
                body:
                    """
                    features:
                      base: {}

                    """,
            ),
        ]
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            session: mockSession(),
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
        #expect(try resolved.repository.patch(for: "base", inheritedBy: reference) == nil)
    }

    @Test
    func `HTTP snapshot reports required 404 and non-success responses`() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        unsafe MockURLProtocol.responses = [:]
        let resolver = PatchsetSourceResolver(
            paths: .init(homeURL: home),
            session: mockSession(),
        )

        await #expect(throws: URIError.self) {
            _ = try await resolver.resolve(
                .init(kind: .http, original: "https://example.com/missing"),
            )
        }
    }

    // swift-corelibs-foundation traps when URLProtocol reports a redirect.
    #if canImport(Darwin)
        @Test
        func `HTTP snapshot follows a root manifest redirect`() async throws {
            let home = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: home) }
            unsafe MockURLProtocol.responses = [
                "/redirect/manifest.yaml": .init(
                    status: 302,
                    body: "",
                    location: "https://example.com/final/manifest.yaml",
                ),
                "/final/manifest.yaml": .init(
                    status: 200,
                    body: "upstream: https://example.com/upstream.git\n",
                ),
            ]
            let resolver = PatchsetSourceResolver(
                paths: .init(homeURL: home),
                session: mockSession(),
            )
            let resolved = try await resolver.resolve(
                .init(kind: .http, original: "https://example.com/redirect"),
            )
            defer { try? resolver.removeSnapshot(at: resolved.snapshotURL) }
            #expect(try resolved.repository.rootManifest().upstream
                == "https://example.com/upstream.git")
        }
    #endif

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

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SourceSnapshotTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func git(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
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

private final class MockURLProtocol: URLProtocol {

    struct Response: Sendable {
        let status: Int
        let body: String
        let location: String?

        init(status: Int, body: String, location: String? = nil) {
            self.status = status
            self.body = body
            self.location = location
        }
    }

    nonisolated(unsafe) static var responses = [String: Response]()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let value = unsafe Self.responses[url.path] ?? .init(status: 404, body: "")
        let response = HTTPURLResponse(
            url: url,
            statusCode: value.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/yaml"],
        )!
        if let location = value.location, let redirectURL = URL(string: location) {
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: redirectURL),
                redirectResponse: response,
            )
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !value.body.isEmpty {
            client?.urlProtocol(self, didLoad: Data(value.body.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
