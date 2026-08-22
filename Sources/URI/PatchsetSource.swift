public import Foundation
public import URIPatchset
import Yams

public enum PatchsetSourceKind: String, Codable, Hashable, Sendable {

    case local

    case http

    case git
}

public struct PatchsetSource: Codable, Hashable, Sendable {

    public let kind: PatchsetSourceKind

    public let original: String

    public let localRootURL: URL?

    public init(
        kind: PatchsetSourceKind,
        original: String,
        localRootURL: URL? = nil,
    ) {
        self.kind = kind
        self.original = original
        self.localRootURL = localRootURL
    }

    public var isRemote: Bool {
        kind != .local
    }
}

public struct ResolvedPatchsetSource: Sendable {

    public let source: PatchsetSource

    public let repository: PatchsetRepository

    public let snapshotURL: URL?

    public init(
        source: PatchsetSource,
        repository: PatchsetRepository,
        snapshotURL: URL?,
    ) {
        self.source = source
        self.repository = repository
        self.snapshotURL = snapshotURL
    }
}

public enum PatchsetSourceLocator {

    public static func recognizesExplicitSource(_ value: String) -> Bool {
        isExplicitLocalPath(value) || isHTTP(value) || isGit(value)
    }

    public static func locate(
        _ value: String?,
        currentDirectoryURL: URL,
    ) throws -> PatchsetSource {
        if let value {
            if isHTTP(value) {
                guard let url = URL(string: value), url.user == nil, url.password == nil else {
                    throw URIError.unsupportedSource("Static HTTP authentication is not supported: \(value)")
                }
                return .init(kind: .http, original: normalizedHTTPRoot(url).absoluteString)
            }
            if isGit(value) {
                return .init(kind: .git, original: value)
            }
            guard isExplicitLocalPath(value) else {
                throw URIError.unsupportedSource("SOURCE must be an explicit path or supported URL: \(value)")
            }
            let expanded = expandTilde(value)
            let url = URL(filePath: expanded, relativeTo: currentDirectoryURL).standardizedFileURL
            let root = try discoverLocalRoot(from: url)
            return .init(kind: .local, original: value, localRootURL: root)
        }

        let root = try discoverLocalRoot(from: currentDirectoryURL)
        return .init(kind: .local, original: root.path, localRootURL: root)
    }

    public static func discoverLocalRoot(from startURL: URL) throws -> URL {
        var candidate = startURL.standardizedFileURL.resolvingSymlinksInPath()
        if (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            candidate.deleteLastPathComponent()
        }

        while true {
            let manifestURL = candidate.appending(path: "manifest.yaml")
            if (try? manifestURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                if manifestLooksLikeRoot(at: manifestURL) {
                    let repository = try PatchsetRepository(rootURL: candidate)
                    _ = try repository.rootManifest()
                    return repository.rootURL
                }
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            candidate = parent
        }
        throw URIError.sourceNotFound(
            "Could not find a root manifest.yaml from \(startURL.standardizedFileURL.path).",
        )
    }

    public static func gitRemote(from source: PatchsetSource) throws -> String {
        guard source.kind == .git else {
            throw URIError.unsupportedSource("Not a Git source: \(source.original)")
        }
        if source.original.hasPrefix("git+") {
            return String(source.original.dropFirst(4))
        }
        return source.original
    }

    private static func isExplicitLocalPath(_ value: String) -> Bool {
        value == "." || value == "~" || value.contains("/")
    }

    private static func isHTTP(_ value: String) -> Bool {
        value.hasPrefix("http://") || value.hasPrefix("https://")
    }

    private static func isGit(_ value: String) -> Bool {
        if value.hasPrefix("git+https://")
            || value.hasPrefix("git+ssh://")
            || value.hasPrefix("ssh://")
            || value.hasPrefix("git://")
        {
            return true
        }
        guard let colon = value.firstIndex(of: ":") else {
            return false
        }
        let prefix = value[..<colon]
        return prefix.contains("@") && !prefix.contains("/")
    }

    private static func normalizedHTTPRoot(_ url: URL) -> URL {
        var value = url.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value) ?? url
    }

    private static func expandTilde(_ value: String) -> String {
        guard value == "~" || value.hasPrefix("~/") else {
            return value
        }
        let suffix = value.dropFirst(value == "~" ? 1 : 2)
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: String(suffix))
            .path
    }

    private static func manifestLooksLikeRoot(at url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        guard let node = try? Yams.compose(yaml: contents), let mapping = node.mapping else {
            return false
        }
        return mapping.contains(where: { key, _ in key.string == "upstream" })
    }
}
