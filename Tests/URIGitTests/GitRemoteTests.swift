import Foundation
import Testing
import URIGit

@Suite("Git Remote")
struct GitRemoteTests {

    @Test
    func `HTTPS and SCP remotes normalize credentials host and default port`() throws {
        let baseURL = FileManager.default.temporaryDirectory
        let https = try GitRemoteIdentity(
            "https://user:secret@GitHub.COM:443/org/Repo.git/",
            relativeTo: baseURL,
        )
        let scp = try GitRemoteIdentity(
            "git@github.com:org/Repo",
            relativeTo: baseURL,
        )

        #expect(https == scp)
        #expect(https.description == "remote:github.com/org/Repo")
    }

    @Test
    func `remote repository path comparison remains case sensitive`() throws {
        let baseURL = FileManager.default.temporaryDirectory

        #expect(
            try GitRemoteIdentity(
                "https://github.com/Org/Repo.git",
                relativeTo: baseURL,
            )
                != GitRemoteIdentity(
                    "https://github.com/org/repo.git",
                    relativeTo: baseURL,
                ),
        )
    }

    @Test
    func `relative local path and file URL resolve to one canonical identity`() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "GitRemoteTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repositoryURL = rootURL.appending(path: "source.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let relative = try GitRemoteIdentity("./source.git", relativeTo: rootURL)
        let file = try GitRemoteIdentity("file://\(repositoryURL.path)", relativeTo: rootURL)

        #expect(relative == file)
        #expect(relative.description == "local:\(rootURL.path)/source")
    }

    @Test
    func `repository remote validation accepts equivalent forms and rejects a different path`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        try fixture.git([
            "remote",
            "add",
            "origin",
            "git@GitHub.COM:org/Repo.git",
        ])
        let repository = try await fixture.repository()

        try await repository.validateRemote(
            matches: "https://github.com/org/Repo.git",
            relativeTo: fixture.rootURL,
        )

        do {
            try await repository.validateRemote(
                matches: "https://github.com/org/Other.git",
                relativeTo: fixture.rootURL,
            )
            Issue.record("Expected remoteMismatch.")
        }
        catch let error as GitError {
            guard case .remoteMismatch = error else {
                Issue.record("Expected remoteMismatch, received \(error).")
                return
            }
        }
    }

    @Test
    func `missing origin reports the repository and remote name`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()

        do {
            _ = try await repository.remoteURL()
            Issue.record("Expected missingRemote.")
        }
        catch let error as GitError {
            #expect(
                error
                    == .missingRemote(
                        name: "origin",
                        repositoryURL: fixture.rootURL,
                    ),
            )
        }
    }
}
