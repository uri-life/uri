package import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

package struct EphemeralWorkspaceInitialization: Codable, Hashable, Sendable {

    package static let currentSchemaVersion = 1

    package var schemaVersion: Int

    package var id: String

    package var targetPath: String

    package var createdAt: String

    package init(
        id: String,
        targetPath: String,
        createdAt: String,
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.targetPath = targetPath
        self.createdAt = createdAt
    }
}

/// Describes a managed workspace or hidden lifecycle artifact for package diagnostics.
package struct EphemeralWorkspaceInspection: Hashable, Sendable {

    package enum Location: Hashable, Sendable {

        case active

        case allocation

        case removal
    }

    package enum Status: Hashable, Sendable {

        case valid(EphemeralListing)

        case initializing(EphemeralWorkspaceInitialization?)

        case interruptedInitialization(EphemeralWorkspaceInitialization?)

        case legacyIncomplete

        case deferredRemoval
    }

    package let id: String

    package let rootURL: URL

    package let location: Location

    package let status: Status
}

/// Owns one advisory lock and serializes its one-time release across workspace copies.
package final class EphemeralWorkspaceInitializationLease: @unchecked Sendable {

    private let lock = NSLock()

    private var releaseAction: ((Bool) -> Void)?

    package init(
        releaseAction: @escaping (Bool) -> Void,
    ) {
        self.releaseAction = releaseAction
    }

    deinit {
        finish(removingMarker: false)
    }

    package func finish(removingMarker: Bool) {
        lock.lock()
        let action = releaseAction
        releaseAction = nil
        lock.unlock()
        action?(removingMarker)
    }
}

package struct EphemeralWorkspaceLockOperations: Sendable {

    package let createLease:
        @Sendable (URL, URL, Data) throws -> EphemeralWorkspaceInitializationLease

    package let tryAcquireLease:
        @Sendable (URL) throws -> EphemeralWorkspaceInitializationLease?

    package init(
        createLease: @escaping @Sendable (URL, URL, Data) throws -> EphemeralWorkspaceInitializationLease,
        tryAcquireLease: @escaping @Sendable (URL) throws -> EphemeralWorkspaceInitializationLease?,
    ) {
        self.createLease = createLease
        self.tryAcquireLease = tryAcquireLease
    }

    package static let live = Self(
        createLease: { storageURL, removalURL, data in
            try data.write(to: storageURL, options: .atomic)
            guard let lease = try lockedLease(
                at: storageURL,
                removalURL: removalURL,
                nonblocking: false,
            ) else {
                throw URIError.fileSystem(
                    "Could not lock ephemeral initialization at \(storageURL.path).",
                )
            }
            return lease
        },
        tryAcquireLease: { url in
            try lockedLease(at: url, removalURL: url, nonblocking: true)
        },
    )

    private static func lockedLease(
        at url: URL,
        removalURL: URL,
        nonblocking: Bool,
    ) throws -> EphemeralWorkspaceInitializationLease? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: url)
        }
        catch {
            throw URIError.fileSystem(
                "Could not open ephemeral initialization at \(url.path): \(error)",
            )
        }

        let operation = LOCK_EX | (nonblocking ? LOCK_NB : 0)
        guard flock(handle.fileDescriptor, operation) == 0 else {
            let code = errno
            try? handle.close()
            if nonblocking, code == EWOULDBLOCK || code == EAGAIN {
                return nil
            }
            throw URIError.fileSystem(
                "Could not lock ephemeral initialization at \(url.path): POSIX error \(code)",
            )
        }

        return .init(
            releaseAction: { removingMarker in
                if removingMarker {
                    try? FileManager.default.removeItem(at: removalURL)
                }
                _ = flock(handle.fileDescriptor, LOCK_UN)
                try? handle.close()
            },
        )
    }
}

package struct EphemeralWorkspaceFileOperations: Sendable {

    package let moveItem: @Sendable (URL, URL) throws -> Void

    package let removeItem: @Sendable (URL) throws -> Void

    package init(
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        removeItem: @escaping @Sendable (URL) throws -> Void,
    ) {
        self.moveItem = moveItem
        self.removeItem = removeItem
    }

    package static let live = Self(
        moveItem: { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        },
        removeItem: { url in
            try FileManager.default.removeItem(at: url)
        },
    )
}

package struct EphemeralWorkspaceDeferredCleanup: Sendable {

    package let rootURL: URL

    package let parentURL: URL

    package let snapshotURL: URL?

    package let paths: RuntimePaths

    package let fileOperations: EphemeralWorkspaceFileOperations

    package init(
        rootURL: URL,
        parentURL: URL,
        snapshotURL: URL?,
        paths: RuntimePaths,
        fileOperations: EphemeralWorkspaceFileOperations,
    ) {
        self.rootURL = rootURL
        self.parentURL = parentURL
        self.snapshotURL = snapshotURL
        self.paths = paths
        self.fileOperations = fileOperations
    }

    package func perform() -> Bool {
        do {
            if let snapshotURL,
                FileManager.default.fileExists(atPath: snapshotURL.path)
            {
                let canonical = snapshotURL.standardizedFileURL.resolvingSymlinksInPath()
                let cache = paths.operationCacheURL.standardizedFileURL.resolvingSymlinksInPath()
                guard canonical.deletingLastPathComponent().path == cache.path else {
                    return false
                }
                try fileOperations.removeItem(canonical)
            }
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try fileOperations.removeItem(rootURL)
            }
            if FileManager.default.fileExists(atPath: parentURL.path) {
                try fileOperations.removeItem(parentURL)
            }
            return true
        }
        catch {
            return false
        }
    }
}

/// Retains isolated removals for one silent retry before the current CLI command returns.
package final class EphemeralWorkspaceCleanupRegistry: @unchecked Sendable {

    package static let shared = EphemeralWorkspaceCleanupRegistry()

    private let lock = NSLock()

    private var cleanups = [EphemeralWorkspaceDeferredCleanup]()

    package init() {}

    package var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cleanups.count
    }

    package func schedule(_ cleanup: EphemeralWorkspaceDeferredCleanup) {
        lock.lock()
        cleanups.append(cleanup)
        lock.unlock()
    }

    package func retry() {
        lock.lock()
        let pending = cleanups
        cleanups.removeAll()
        lock.unlock()

        let failed = pending.filter({!$0.perform()})
        guard !failed.isEmpty else {
            return
        }
        lock.lock()
        cleanups.append(contentsOf: failed)
        lock.unlock()
    }
}
