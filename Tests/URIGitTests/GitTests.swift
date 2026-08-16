import Foundation
import Testing
import URIGit

@Suite("Git Repository")
struct GitTests {

    @Test
    func `opening a nested directory returns the canonical worktree root`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let nestedURL = fixture.rootURL.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: false)

        let repository = try await Git().openRepository(at: nestedURL)

        #expect(repository.rootURL == fixture.rootURL.resolvingSymlinksInPath())
    }

    @Test
    func `opening a directory outside a worktree reports the invalid root`() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "URIGitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        do {
            _ = try await Git().openRepository(at: rootURL)
            Issue.record("Expected invalidRepository.")
        }
        catch let error as GitError {
            #expect(error == .invalidRepository(rootURL))
        }
    }

    @Test
    func `status distinguishes tracked changes from untracked files`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()

        #expect(try await repository.status().isCompletelyClean)

        try fixture.write("untracked\n", to: "untracked.txt")
        let untracked = try await repository.status()
        #expect(!untracked.hasTrackedChanges)
        #expect(untracked.hasUntrackedFiles)
        #expect(untracked.isTrackedClean)
        #expect(!untracked.isCompletelyClean)

        try fixture.write("changed\n", to: "README.md")
        let changed = try await repository.status()
        #expect(changed.hasTrackedChanges)
        #expect(changed.hasUntrackedFiles)
    }

    @Test
    func `configured identity reads the repository Git configuration`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }

        let identity = try await fixture.repository().configuredIdentity()

        #expect(identity == GitIdentity.test)
    }

    @Test
    func `identity commit and reference reject malformed values`() throws {
        #expect(throws: GitError.self) {
            _ = try GitIdentity(name: "", email: "test@example.com")
        }
        #expect(throws: GitError.self) {
            _ = try GitIdentity(name: "Test\nUser", email: "test@example.com")
        }
        #expect(throws: GitError.self) {
            _ = try GitCommit(rawValue: "not-a-commit")
        }
        #expect(throws: GitError.self) {
            _ = try GitReference(rawValue: "--option")
        }
    }
}
