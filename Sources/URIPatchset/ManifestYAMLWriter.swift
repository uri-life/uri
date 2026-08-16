import URIModel
import Yams

internal struct ManifestYAMLWriter {

    internal func write(_ manifest: PatchsetManifest) throws -> String {
        var sections = [[String]]()

        if let inherits = manifest.inherits {
            sections.append(try inheritanceSection(inherits))
        }
        if let excludes = manifest.excludes, !excludes.isEmpty {
            sections.append(sequenceSection(key: "excludes", values: excludes, indentation: 0))
        }
        if let features = manifest.features {
            sections.append(try featuresSection(features))
        }

        guard !sections.isEmpty else {
            return "{}\n"
        }

        return sections
            .map({$0.joined(separator: "\n")})
            .joined(separator: "\n\n") + "\n"
    }

    private func inheritanceSection(
        _ inherits: PatchsetManifest.Inherits,
    ) throws -> [String] {
        switch inherits {
        case .simple(let value):
            return ["inherits: \(value)"]
        case .detailed(let detailed):
            guard let upstreamVersion = detailed.upstreamVersion else {
                throw ManifestYAMLWriterError.missingDetailedUpstreamVersion
            }

            return [
                "inherits:",
                "  upstream-version: \(upstreamVersion)",
                "  patchset-version: \(detailed.patchsetVersion)",
            ]
        }
    }

    private func featuresSection(_ features: Set<Feature>) throws -> [String] {
        guard !features.isEmpty else {
            return ["features: {}"]
        }

        var lines = ["features:"]
        for feature in features.sorted(by: {$0.id < $1.id}) {
            var payload = [String]()
            if let name = feature.name {
                payload.append(
                    contentsOf: try scalarField(
                        key: "name",
                        value: name,
                        style: .any,
                        indentation: 4,
                    ),
                )
            }
            if let description = feature.description {
                payload.append(
                    contentsOf: try scalarField(
                        key: "description",
                        value: description,
                        style: .literal,
                        indentation: 4,
                    ),
                )
            }
            if let dependencies = feature.dependencies {
                payload.append(
                    contentsOf: sequenceSection(
                        key: "dependencies",
                        values: dependencies,
                        indentation: 4,
                    ),
                )
            }
            if let devDependencies = feature.devDependencies {
                payload.append(
                    contentsOf: sequenceSection(
                        key: "dev-dependencies",
                        values: devDependencies,
                        indentation: 4,
                    ),
                )
            }

            if payload.isEmpty {
                lines.append("  \(feature.id): {}")
            }
            else {
                lines.append("  \(feature.id):")
                lines.append(contentsOf: payload)
            }
        }
        return lines
    }

    private func sequenceSection(
        key: String,
        values: [String],
        indentation: Int,
    ) -> [String] {
        let prefix = String(repeating: " ", count: indentation)
        guard !values.isEmpty else {
            return ["\(prefix)\(key): []"]
        }

        return ["\(prefix)\(key):"]
            + values.map({"\(prefix)  - \($0)"})
    }

    private func scalarField(
        key: String,
        value: String,
        style: Node.Scalar.Style,
        indentation: Int,
    ) throws -> [String] {
        let valueNode: Node
        if style == .any {
            valueNode = .scalar(value.represented())
        }
        else {
            valueNode = Node(value, Tag(.str), style)
        }
        let node = Node(
            [
                (
                    Node(key, Tag(.str)),
                    valueNode
                ),
            ],
            Tag(.map),
            .block,
        )
        var serialized = try Yams.serialize(
            node: node,
            width: -1,
            allowUnicode: true,
        )
        if serialized.hasSuffix("\n") {
            serialized.removeLast()
        }

        var lines = serialized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "..." {
            lines.removeLast()
        }

        let prefix = String(repeating: " ", count: indentation)
        return lines.enumerated().map({ index, line in
            if !line.isEmpty {
                return prefix + line
            }
            if index == lines.indices.last {
                return prefix + "  "
            }
            return ""
        })
    }
}

private enum ManifestYAMLWriterError: Error, CustomStringConvertible {

    case missingDetailedUpstreamVersion

    // MARK: CustomStringConvertible

    fileprivate var description: String {
        "Detailed inheritance requires upstream-version."
    }
}
