import Foundation
import URIModel
import Yams

internal struct RootManifestStore {

    internal let rootURL: URL

    internal var manifestURL: URL {
        rootURL.appending(path: "manifest.yaml", directoryHint: .notDirectory)
    }

    internal func load() throws -> RootManifest {
        guard isRegularFile(manifestURL) else {
            throw PatchsetError.rootManifestNotFound(manifestURL)
        }

        let yaml: String
        do {
            yaml = try String(contentsOf: manifestURL, encoding: .utf8)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "read",
                url: manifestURL,
                reason: String(describing: error),
            )
        }

        try RootManifestSchemaValidator.validate(yaml: yaml, at: manifestURL)
        do {
            return try YAMLDecoder().decode(RootManifest.self, from: yaml)
        }
        catch {
            throw PatchsetError.invalidManifest(
                url: manifestURL,
                reason: String(describing: error),
            )
        }
    }

    internal func save(
        _ manifest: RootManifest,
        replacingExisting: Bool,
    ) throws {
        if !replacingExisting, FileManager.default.fileExists(atPath: manifestURL.path) {
            throw PatchsetError.rootManifestAlreadyExists(manifestURL)
        }
        guard !manifest.upstream.isEmpty, !manifest.upstream.contains(where: { $0.isNewline }) else {
            throw PatchsetError.invalidManifest(
                url: manifestURL,
                reason: "upstream must be a non-empty single-line string.",
            )
        }
        if let branchPrefix = manifest.branchPrefix {
            try IdentifierValidator.validate(branchPrefix, label: "branch-prefix")
        }
        if case .explicit(let identity) = manifest.committer {
            guard !identity.name.isEmpty,
                !identity.email.isEmpty,
                !identity.name.contains(where: { $0.isNewline }),
                !identity.email.contains(where: { $0.isNewline })
            else {
                throw PatchsetError.invalidManifest(
                    url: manifestURL,
                    reason: "An explicit committer requires single-line name and email values.",
                )
            }
        }

        let yaml = RootManifestYAMLWriter().write(manifest)
        do {
            try Data(yaml.utf8).write(to: manifestURL, options: .atomic)
        }
        catch {
            throw PatchsetError.fileSystem(
                operation: "write",
                url: manifestURL,
                reason: String(describing: error),
            )
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

internal enum RootManifestSchemaValidator {

    internal static func validate(yaml: String, at url: URL) throws {
        let root: Node
        do {
            guard let composed = try Yams.compose(yaml: yaml) else {
                throw PatchsetError.invalidManifest(url: url, reason: "The document is empty.")
            }
            root = composed
        }
        catch let error as PatchsetError {
            throw error
        }
        catch {
            throw PatchsetError.invalidManifest(url: url, reason: String(describing: error))
        }

        let entries = try mappingEntries(
            root,
            allowed: ["upstream", "branch-prefix", "committer"],
            path: "manifest",
            url: url,
        )
        guard let upstream = entries["upstream"], isString(upstream), upstream.string?.isEmpty == false else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "upstream must be a non-empty string.",
            )
        }
        if let prefix = entries["branch-prefix"] {
            guard isString(prefix), let value = prefix.string else {
                throw PatchsetError.invalidManifest(url: url, reason: "branch-prefix must be a string.")
            }
            try IdentifierValidator.validate(value, label: "branch-prefix")
        }
        if let committer = entries["committer"] {
            try validateCommitter(committer, url: url)
        }
    }

    private static func validateCommitter(_ node: Node, url: URL) throws {
        guard let mapping = node.mapping else {
            throw PatchsetError.invalidManifest(url: url, reason: "committer must be an object.")
        }
        let modeNode = mapping.first(where: { $0.0.string == "mode" })?.1
        guard let modeNode, isString(modeNode), let mode = modeNode.string else {
            throw PatchsetError.invalidManifest(url: url, reason: "committer.mode must be a string.")
        }
        switch mode {
        case "repository":
            _ = try mappingEntries(node, allowed: ["mode"], path: "committer", url: url)
        case "explicit":
            let entries = try mappingEntries(
                node,
                allowed: ["mode", "name", "email"],
                path: "committer",
                url: url,
            )
            for key in ["name", "email"] {
                guard let value = entries[key], isString(value), value.string?.isEmpty == false else {
                    throw PatchsetError.invalidManifest(
                        url: url,
                        reason: "An explicit committer requires non-empty name and email values.",
                    )
                }
            }
        default:
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "Unsupported committer mode: \(mode)",
            )
        }
    }

    private static func mappingEntries(
        _ node: Node,
        allowed: Set<String>,
        path: String,
        url: URL,
    ) throws -> [String: Node] {
        guard let mapping = node.mapping else {
            throw PatchsetError.invalidManifest(url: url, reason: "\(path) must be an object.")
        }
        var entries = [String: Node]()
        for (key, value) in mapping {
            guard isString(key), let name = key.string else {
                throw PatchsetError.invalidManifest(url: url, reason: "Every \(path) key must be a string.")
            }
            guard allowed.contains(name) else {
                throw PatchsetError.invalidManifest(url: url, reason: "Unknown \(path) setting: \(name)")
            }
            guard entries.updateValue(value, forKey: name) == nil else {
                throw PatchsetError.invalidManifest(url: url, reason: "\(path) contains a duplicate key: \(name)")
            }
        }
        return entries
    }

    private static func isString(_ node: Node) -> Bool {
        node.scalar != nil && node.tag.rawValue == Tag.Name.str.rawValue
    }
}

internal struct RootManifestYAMLWriter {

    internal func write(_ manifest: RootManifest) -> String {
        var lines = ["upstream: \(quoted(manifest.upstream))"]
        if let branchPrefix = manifest.branchPrefix {
            lines.append("branch-prefix: \(quoted(branchPrefix))")
        }
        if let committer = manifest.committer {
            lines.append("committer:")
            switch committer {
            case .repository:
                lines.append("  mode: repository")
            case .explicit(let identity):
                lines.append("  mode: explicit")
                lines.append("  name: \(quoted(identity.name))")
                lines.append("  email: \(quoted(identity.email))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
