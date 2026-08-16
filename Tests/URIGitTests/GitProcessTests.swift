import Foundation
import Testing

@testable
import URIGit

@Suite("Git Process")
struct GitProcessTests {

    @Test
    func `large standard output and error are captured without blocking termination`() async throws {
        let scriptURL = try executableTestScript(
            """
            #!/bin/sh
            i=0
            while [ "$i" -lt 12000 ]; do
                printf '0123456789abcdef0123456789abcdef\n'
                printf 'fedcba9876543210fedcba9876543210\n' >&2
                i=$((i + 1))
            done
            exit 7
            """,
        )
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let process = GitProcess(executableURL: scriptURL, prefixArguments: [])

        let output = try await process.run(arguments: [])

        #expect(output.exitStatus == 7)
        #expect(output.standardOutput.count > 300_000)
        #expect(output.standardError.count > 300_000)
    }

    @Test
    func `task cancellation terminates the child and throws cancellation`() async throws {
        let scriptURL = try executableTestScript(
            """
            #!/bin/sh
            exec sleep 30
            """,
        )
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let process = GitProcess(executableURL: scriptURL, prefixArguments: [])
        let task = Task {
            try await process.run(arguments: [])
        }
        try await Task.sleep(for: .milliseconds(100))

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError.")
        }
        catch is CancellationError {
        }
        catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
    }

}
