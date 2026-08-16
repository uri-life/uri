import Foundation
import Testing
import URIGit

@Suite("Git Branch And History")
struct GitBranchHistoryTests {

    @Test
    func `branch creation checkout detachment and forced deletion update repository state`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()

        try await repository.createBranch("saved")
        #expect(try await repository.branchExists("saved"))
        #expect(try await repository.currentBranch() == "main")

        try await repository.createAndCheckoutBranch("work")
        #expect(try await repository.currentBranch() == "work")
        try await repository.detachHead()
        #expect(try await repository.currentBranch() == nil)
        try await repository.checkoutBranch("main")
        try await repository.deleteBranch("work", force: true)
        #expect(try await !repository.branchExists("work"))
    }

    @Test
    func `tag checkout detaches HEAD at the tagged commit`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        try fixture.git([
            "tag",
            "v1.0.0",
        ])
        let repository = try await fixture.repository()
        let expected = try await repository.currentCommit()

        try await repository.checkoutTag("v1.0.0")

        #expect(try await repository.currentBranch() == nil)
        #expect(try await repository.currentCommit() == expected)
    }

    @Test
    func `commit count ancestry and diff reflect the selected references`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()
        let baseCommit = try await repository.currentCommit()
        _ = try fixture.commit("second\n", to: "second.txt", message: "second")
        let headCommit = try await repository.currentCommit()
        let base = GitReference(baseCommit)
        let head = GitReference(headCommit)

        #expect(try await repository.commitCount(fromExclusive: base, through: head) == 1)
        #expect(try await repository.isAncestor(base, of: head))
        #expect(try await !repository.isAncestor(head, of: base))
        #expect(try await repository.hasDiff(between: base, and: head))
        #expect(try await !repository.hasDiff(between: head, and: head))
    }

    @Test
    func `clone and exact tag fetch use a local upstream without fetching unrelated tags`() async throws {
        let source = try GitTestFixture()
        defer { source.remove() }
        let cloneURL = FileManager.default.temporaryDirectory
            .appending(path: "URIGitClone-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cloneURL) }
        let git = Git()
        let clone = try await git.cloneRepository(from: source.rootURL.path, to: cloneURL)

        _ = try source.commit("tagged\n", to: "tagged.txt", message: "tagged")
        try source.git([
            "tag",
            "v2.0.0",
        ])
        try source.git([
            "tag",
            "unrelated",
        ])
        try await clone.fetchTag("v2.0.0")
        try await clone.checkoutTag("v2.0.0")

        #expect(try await clone.currentBranch() == nil)
        #expect(FileManager.default.fileExists(atPath: cloneURL.appending(path: "tagged.txt").path))
        #expect(
            try await !clone.referenceExists(
                GitReference(rawValue: "refs/tags/unrelated"),
            ),
        )
    }
}
