import Foundation
import Yams

internal enum ManifestSchemaValidator {

    internal static func validate(
        yaml: String,
        at url: URL,
    ) throws {
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

        let rootEntries = try mappingEntries(
            in: root,
            allowedKeys: ["excludes", "features", "inherits"],
            path: "manifest",
            url: url,
        )

        if let inherits = rootEntries["inherits"], inherits.null == nil {
            try validateInheritance(inherits, at: url)
        }
        if let excludes = rootEntries["excludes"], excludes.null == nil {
            try validateStringSequence(excludes, path: "excludes", url: url)
        }
        if let features = rootEntries["features"], features.null == nil {
            try validateFeatures(features, at: url)
        }
    }

    private static func validateInheritance(
        _ node: Node,
        at url: URL,
    ) throws {
        if isString(node) {
            return
        }

        let entries = try mappingEntries(
            in: node,
            allowedKeys: ["patchset-version", "upstream-version"],
            path: "inherits",
            url: url,
        )
        guard entries["upstream-version"].map(isString) == true else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "inherits.upstream-version must be a string.",
            )
        }
        guard entries["patchset-version"].map(isString) == true else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "inherits.patchset-version must be a string.",
            )
        }
    }

    private static func validateFeatures(
        _ node: Node,
        at url: URL,
    ) throws {
        guard let mapping = node.mapping else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "features must be an object.",
            )
        }

        var seen = Set<String>()
        for (key, payload) in mapping {
            guard isString(key), let featureID = key.string else {
                throw PatchsetError.invalidManifest(
                    url: url,
                    reason: "Every features key must be a string.",
                )
            }
            guard seen.insert(featureID).inserted else {
                throw PatchsetError.invalidManifest(
                    url: url,
                    reason: "features contains a duplicate key: \(featureID)",
                )
            }

            let entries = try mappingEntries(
                in: payload,
                allowedKeys: ["dependencies", "description", "dev-dependencies", "name"],
                path: "features.\(featureID)",
                url: url,
            )
            for key in ["name", "description"] {
                if let value = entries[key], value.null == nil, !isString(value) {
                    throw PatchsetError.invalidManifest(
                        url: url,
                        reason: "features.\(featureID).\(key) must be a string.",
                    )
                }
            }
            for key in ["dependencies", "dev-dependencies"] {
                if let value = entries[key], value.null == nil {
                    try validateStringSequence(
                        value,
                        path: "features.\(featureID).\(key)",
                        url: url,
                    )
                }
            }
        }
    }

    private static func validateStringSequence(
        _ node: Node,
        path: String,
        url: URL,
    ) throws {
        guard let sequence = node.sequence else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "\(path) must be an array of strings.",
            )
        }
        guard sequence.allSatisfy(isString) else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "\(path) may contain only strings.",
            )
        }
    }

    private static func mappingEntries(
        in node: Node,
        allowedKeys: Set<String>,
        path: String,
        url: URL,
    ) throws -> [String: Node] {
        guard let mapping = node.mapping else {
            throw PatchsetError.invalidManifest(
                url: url,
                reason: "\(path) must be an object.",
            )
        }

        var entries = [String: Node]()
        for (key, value) in mapping {
            guard isString(key), let stringKey = key.string else {
                throw PatchsetError.invalidManifest(
                    url: url,
                    reason: "Every \(path) key must be a string.",
                )
            }
            guard allowedKeys.contains(stringKey) else {
                throw PatchsetError.invalidManifest(
                    url: url,
                    reason: "Unknown \(path) setting: \(stringKey)",
                )
            }
            guard entries.updateValue(value, forKey: stringKey) == nil else {
                throw PatchsetError.invalidManifest(
                    url: url,
                    reason: "\(path) contains a duplicate key: \(stringKey)",
                )
            }
        }

        return entries
    }

    private static func isString(_ node: Node) -> Bool {
        node.scalar != nil && node.tag.rawValue == Tag.Name.str.rawValue
    }
}
