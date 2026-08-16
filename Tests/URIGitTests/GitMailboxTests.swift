import Foundation
import Testing

@testable
import URIGit

@Suite("Git Mailbox")
struct GitMailboxTests {

    @Test
    func `mailbox patch application preserves the author and sets the selected committer`() async throws {
        let source = try GitTestFixture()
        defer { source.remove() }
        let target = try GitTestFixture(cloning: source.rootURL)
        defer { target.remove() }
        let sourceRepository = try await source.repository()
        let targetRepository = try await target.repository()
        let base = GitReference(try await sourceRepository.currentCommit())
        _ = try source.commit("patch\n", to: "patch.txt", message: "add patch")
        let patchURL = source.rootURL.appending(path: "feature.patch")
        try await sourceRepository.writeFormatPatch(
            fromExclusive: base,
            through: .head,
            to: patchURL,
        )
        let committer = try GitIdentity(name: "Patch Bot", email: "patch@example.com")

        let result = try await targetRepository.applyMailboxPatch(
            at: patchURL,
            committer: committer,
        )

        #expect(result == .applied)
        #expect(FileManager.default.fileExists(atPath: target.rootURL.appending(path: "patch.txt").path))
        #expect(try target.gitString(["log", "-1", "--format=%an"]) == "Test")
        #expect(try target.gitString(["log", "-1", "--format=%cn"]) == "Patch Bot")
    }

    @Test
    func `resolution patch stages the conflicted path and continue completes the mailbox apply`() async throws {
        let source = try GitTestFixture()
        defer { source.remove() }
        _ = try source.commit("base\n", to: "conflict.txt", message: "add conflict base")
        _ = try source.commit("base\n", to: "extra file.txt", message: "add extra base")
        let target = try GitTestFixture(cloning: source.rootURL)
        defer { target.remove() }
        let sourceRepository = try await source.repository()
        let targetRepository = try await target.repository()
        let base = GitReference(try await sourceRepository.currentCommit())
        _ = try source.commit("source\n", to: "conflict.txt", message: "source change")
        let patchURL = source.rootURL.appending(path: "conflict.patch")
        try await sourceRepository.writeFormatPatch(
            fromExclusive: base,
            through: .head,
            to: patchURL,
        )
        _ = try target.commit("target\n", to: "conflict.txt", message: "target change")

        let result = try await targetRepository.applyMailboxPatch(
            at: patchURL,
            committer: .test,
        )
        #expect(result == .conflicted)
        #expect(try await targetRepository.isMailboxApplyInProgress())

        let conflictedURL = target.rootURL.appending(path: "conflict.txt")
        let conflicted = try String(contentsOf: conflictedURL, encoding: .utf8)
        let resolutionURL = target.rootURL.appending(path: "resolution.patch")
        try target.write("resolved extra\n", to: "extra file.txt")
        let extraPatch = try target.gitString([
            "diff",
            "--",
            "extra file.txt",
        ]) + "\n"
        try target.write("base\n", to: "extra file.txt")
        try (resolutionPatch(replacing: conflicted, with: "resolved\n") + extraPatch)
            .write(to: resolutionURL, atomically: true, encoding: .utf8)

        let staged = try await targetRepository.applyResolutionPatch(at: resolutionURL)

        #expect(staged == ["conflict.txt", "extra file.txt"])
        #expect(
            try target.gitString(["diff", "--cached", "--name-only"])
                == "conflict.txt\nextra file.txt",
        )
        #expect(try String(contentsOf: conflictedURL, encoding: .utf8) == "resolved\n")
        #expect(
            try String(
                contentsOf: target.rootURL.appending(path: "extra file.txt"),
                encoding: .utf8,
            ) == "resolved extra\n",
        )
        try await targetRepository.continueMailboxApply(committer: .test)
        #expect(try await !targetRepository.isMailboxApplyInProgress())
        #expect(try target.gitString(["log", "-1", "--format=%s"]) == "source change")
        #expect(try target.gitString(["status", "--porcelain", "--", "resolution.patch"]) == "?? resolution.patch")
    }

    @Test
    func `abort restores the commit from before a conflicted mailbox apply`() async throws {
        let source = try GitTestFixture()
        defer { source.remove() }
        _ = try source.commit("base\n", to: "conflict.txt", message: "add conflict base")
        let target = try GitTestFixture(cloning: source.rootURL)
        defer { target.remove() }
        let sourceRepository = try await source.repository()
        let targetRepository = try await target.repository()
        let base = GitReference(try await sourceRepository.currentCommit())
        _ = try source.commit("source\n", to: "conflict.txt", message: "source change")
        let patchURL = source.rootURL.appending(path: "conflict.patch")
        try await sourceRepository.writeFormatPatch(
            fromExclusive: base,
            through: .head,
            to: patchURL,
        )
        _ = try target.commit("target\n", to: "conflict.txt", message: "target change")
        let original = try await targetRepository.currentCommit()
        #expect(
            try await targetRepository.applyMailboxPatch(
                at: patchURL,
                committer: .test,
            ) == .conflicted,
        )

        try await targetRepository.abortMailboxApply()

        #expect(try await !targetRepository.isMailboxApplyInProgress())
        #expect(try await targetRepository.currentCommit() == original)
        #expect(try String(contentsOf: target.rootURL.appending(path: "conflict.txt"), encoding: .utf8) == "target\n")
    }

    @Test
    func `non conflict mailbox failure reports the original command error`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let scriptURL = try executableTestScript(
            """
            #!/bin/sh
            case " $* " in
                *" rev-parse --git-path rebase-apply "*)
                    printf '/path/that/does/not/exist\n'
                    exit 0
                    ;;
                *)
                    exit 23
                    ;;
            esac
            """,
        )
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let process = GitProcess(executableURL: scriptURL, prefixArguments: [])
        let repository = GitRepository(rootURL: fixture.rootURL, process: process)
        let patchURL = fixture.rootURL.appending(path: "invalid.patch")
        try Data("not a mailbox patch\n".utf8).write(to: patchURL)

        do {
            _ = try await repository.applyMailboxPatch(at: patchURL, committer: .test)
            Issue.record("Expected commandFailed.")
        }
        catch let error as GitError {
            guard case .commandFailed(let arguments, let exitStatus, _, _) = error else {
                Issue.record("Expected commandFailed, received \(error).")
                return
            }
            #expect(arguments.contains("am"))
            #expect(exitStatus == 23)
        }
        #expect(try await !repository.isMailboxApplyInProgress())
    }

    private func resolutionPatch(
        replacing original: String,
        with replacement: String,
    ) -> String {
        let originalLines = original.split(
            separator: "\n",
            omittingEmptySubsequences: false,
        ).dropLast()
        let replacementLines = replacement.split(
            separator: "\n",
            omittingEmptySubsequences: false,
        ).dropLast()
        return """
            diff --git a/conflict.txt b/conflict.txt
            --- a/conflict.txt
            +++ b/conflict.txt
            @@ -1,\(originalLines.count) +1,\(replacementLines.count) @@
            \(originalLines.map({ "-" + $0 }).joined(separator: "\n"))
            \(replacementLines.map({ "+" + $0 }).joined(separator: "\n"))

            """
    }
}
