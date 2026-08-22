import Foundation
import Testing

@testable
import URI

@Suite("Ephemeral Cleanup Registry")
struct EphemeralWorkspaceCleanupRegistryTests {

    @Test
    func `concurrent retries wait for claimed cleanup and count it until removal finishes`() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "EphemeralCleanupRegistryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let parentURL = root.appending(path: "removal", directoryHint: .isDirectory)
        let workspaceURL = parentURL.appending(path: "peach", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("remaining\n".utf8).write(to: workspaceURL.appending(path: "content"))

        let removalGate = RemovalGate()
        let firstFinished = TestLatch()
        let secondStarted = TestLatch()
        let secondFinished = TestLatch()
        defer {
            removalGate.allowRemoval()
            _ = firstFinished.wait(timeout: 5)
            _ = secondFinished.wait(timeout: 5)
            try? FileManager.default.removeItem(at: root)
        }
        let registry = EphemeralWorkspaceCleanupRegistry()
        registry.schedule(
            .init(
                rootURL: workspaceURL,
                parentURL: parentURL,
                snapshotURL: nil,
                paths: .init(homeURL: root.appending(path: "home")),
                fileOperations: removalGate.fileOperations,
            ),
        )

        Thread {
            registry.retry()
            firstFinished.signal()
        }.start()
        try #require(removalGate.waitUntilRemovalBegins(timeout: 5))

        #expect(registry.pendingCount == 1)

        Thread {
            secondStarted.signal()
            registry.retry()
            secondFinished.signal()
        }.start()
        try #require(secondStarted.wait(timeout: 5))

        #expect(!secondFinished.wait(timeout: 1))

        removalGate.allowRemoval()
        try #require(firstFinished.wait(timeout: 5))
        try #require(secondFinished.wait(timeout: 5))

        #expect(!FileManager.default.fileExists(atPath: parentURL.path))
        #expect(registry.pendingCount == 0)
    }
}

private final class RemovalGate: @unchecked Sendable {

    private let condition = NSCondition()

    private var removalAllowed = false

    private var removalBegan = false

    var fileOperations: EphemeralWorkspaceFileOperations {
        .init(
            moveItem: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { [self] url in
                condition.lock()
                if !removalBegan {
                    removalBegan = true
                    condition.broadcast()
                    while !removalAllowed {
                        condition.wait()
                    }
                }
                condition.unlock()
                try FileManager.default.removeItem(at: url)
            },
        )
    }

    func allowRemoval() {
        condition.lock()
        removalAllowed = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilRemovalBegins(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !removalBegan {
            guard condition.wait(until: deadline) else {
                return removalBegan
            }
        }
        return true
    }
}

private final class TestLatch: @unchecked Sendable {

    private let condition = NSCondition()

    private var signaled = false

    func signal() {
        condition.lock()
        signaled = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !signaled {
            guard condition.wait(until: deadline) else {
                return signaled
            }
        }
        return true
    }
}
