public import Foundation

public enum GitRemoteIdentity: Equatable, Hashable, Sendable {

    case network(host: String, path: String)

    case local(URL)

    /// Returns the final normalized path component used as the local clone directory.
    public var repositoryName: String? {
        let name: String
        switch self {
        case .network(_, let path):
            name = path
                .split(separator: "/", omittingEmptySubsequences: true)
                .last.map(String.init) ?? ""
        case .local(let url):
            name = url.lastPathComponent
        }
        return name.isEmpty ? nil : name
    }

    public init(
        _ value: String,
        relativeTo baseURL: URL,
    ) throws {
        if value.hasPrefix("file://") {
            self = try Self.localIdentity(
                for: String(value.dropFirst("file://".count)),
                originalValue: value,
                relativeTo: baseURL,
            )
            return
        }

        if let schemeRange = value.range(of: "://") {
            let scheme = value[..<schemeRange.lowerBound].lowercased()
            let remainder = value[schemeRange.upperBound...]
            let separator = remainder.firstIndex(of: "/")
            let authority = separator.map({ remainder[..<$0] }) ?? remainder[...]
            let rawPath = separator.map({ String(remainder[remainder.index(after: $0)...]) }) ?? ""
            let hostWithPort = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
            let host = Self.normalizedHost(String(hostWithPort), for: scheme)
            self = .network(host: host, path: Self.normalizedRemotePath(rawPath))
            return
        }

        if let separator = Self.scpSeparator(in: value) {
            let authority = value[..<separator]
            let path = value[value.index(after: separator)...]
            let host = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
            self = .network(
                host: host.lowercased(),
                path: Self.normalizedRemotePath(String(path)),
            )
            return
        }

        self = try Self.localIdentity(
            for: value,
            originalValue: value,
            relativeTo: baseURL,
        )
    }

    private static func normalizedHost(
        _ host: String,
        for scheme: String,
    ) -> String {
        let defaultPort: String?
        switch scheme {
        case "http":
            defaultPort = ":80"
        case "https":
            defaultPort = ":443"
        case "ssh":
            defaultPort = ":22"
        default:
            defaultPort = nil
        }

        if let defaultPort, host.lowercased().hasSuffix(defaultPort) {
            return String(host.dropLast(defaultPort.count)).lowercased()
        }

        return host.lowercased()
    }

    private static func normalizedRemotePath(_ path: String) -> String {
        var path = path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        return path
    }

    private static func scpSeparator(in value: String) -> String.Index? {
        guard let separator = value.firstIndex(of: ":") else {
            return nil
        }

        let authority = value[..<separator]
        guard
            !authority.isEmpty,
            !authority.contains("/"),
            authority.allSatisfy({ character in
                character.isASCII
                    && (character.isLetter
                        || character.isNumber
                        || ["@", ".", "-"].contains(character))
            })
        else {
            return nil
        }

        return separator
    }

    private static func localIdentity(
        for rawPath: String,
        originalValue: String,
        relativeTo baseURL: URL,
    ) throws -> GitRemoteIdentity {
        var rawPath = rawPath
        if rawPath.hasPrefix("localhost/") {
            rawPath = "/" + rawPath.dropFirst("localhost/".count)
        }

        let candidate: URL
        if rawPath.hasPrefix("/") {
            candidate = URL(filePath: rawPath)
        }
        else {
            candidate = baseURL.appending(path: rawPath)
        }

        let fileManager = FileManager.default
        let standardized = candidate.standardizedFileURL
        let canonical: URL
        if fileManager.fileExists(atPath: standardized.path) {
            canonical = standardized.resolvingSymlinksInPath()
        }
        else {
            let parent = standardized.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: parent.path) else {
                throw GitError.unresolvableLocalRemote(
                    value: originalValue,
                    relativeTo: baseURL,
                )
            }
            canonical = parent.resolvingSymlinksInPath()
                .appending(path: standardized.lastPathComponent)
        }

        var path = canonical.path
        while path.hasSuffix("/") && path != "/" {
            path.removeLast()
        }
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }

        return .local(URL(filePath: path))
    }
}

extension GitRemoteIdentity: CustomStringConvertible {

    public var description: String {
        switch self {
        case .network(let host, let path):
            "remote:\(host)/\(path)"
        case .local(let url):
            "local:\(url.path)"
        }
    }
}
