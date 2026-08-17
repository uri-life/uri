import Foundation
import URI
import URIModel
import URIPatchset

struct List {

    let values: [String]

    let ephemeral: String?

    let path: Bool

    func run(terminal: Terminal) async throws {
        if let ephemeral {
            guard values.isEmpty else {
                throw URIError.invalidArguments(
                    "Patchset SOURCE arguments cannot be combined with --ephemeral.",
                )
            }
            try listEphemeral(ephemeral, terminal: terminal)
            return
        }
        guard !path else {
            throw URIError.invalidArguments("--path requires --ephemeral ID.")
        }
        let (source, arguments) = try CLI.sourceAndArguments(values)
        guard arguments.count <= 2 else {
            throw URIError.invalidArguments("list accepts [VERSION] [PATCHSET].")
        }
        if source.kind == .http, arguments.count < 2 {
            throw URIError.unsupportedSource(
                "Static HTTP sources cannot enumerate versions or patchsets without an index. Specify VERSION and PATCHSET.",
            )
        }
        let reference = arguments.count == 2
            ? try PatchsetReference(
                upstreamVersion: arguments[0],
                patchsetVersion: arguments[1],
            )
            : nil
        let resolver = PatchsetSourceResolver()
        let resolved = try await resolver.resolve(source, reference: reference)
        defer { try? resolver.removeSnapshot(at: resolved.snapshotURL) }
        if arguments.isEmpty {
            for version in try resolved.repository.upstreamVersions() {
                terminal.output(version, machineReadable: true)
            }
        }
        else if arguments.count == 1 {
            for reference in try resolved.repository.patchsets(in: arguments[0]) {
                terminal.output(reference.patchsetVersion, machineReadable: true)
            }
        }
        else if let reference {
            for feature in try resolved.repository.resolve(reference).orderedFeatures(
                in: .includingDevelopment,
            ) {
                terminal.output(feature.id, machineReadable: true)
            }
        }
    }

    private func listEphemeral(
        _ value: String,
        terminal: Terminal,
    ) throws {
        let manager = EphemeralWorkspaceManager()
        if value == CLI.automaticEphemeralID {
            guard !path else {
                throw URIError.invalidArguments("--path requires an explicit ephemeral ID.")
            }
            let listings = try manager.list()
            if !listings.isEmpty {
                terminal.output(
                    "ID\tMODE\tVERSION\tPATCHSET\tFEATURE\tSOURCE\tPATH",
                    machineReadable: true,
                )
            }
            for listing in listings {
                let state = listing.state
                terminal.output(
                    [
                        listing.id,
                        state.mode.rawValue,
                        state.upstreamVersion,
                        state.patchsetVersion,
                        state.feature ?? "-",
                        state.source.original,
                        listing.path,
                    ].joined(separator: "\t"),
                    machineReadable: true,
                )
            }
            return
        }
        try EphemeralWorkspaceManager.validateID(value)
        let listing = try manager.list().first(where: { $0.id == value })
        guard let listing else {
            throw URIError.ephemeralNotFound(value)
        }
        if path {
            terminal.output(listing.path, machineReadable: true)
        }
        else {
            let state = listing.state
            for line in [
                "ID: \(listing.id)",
                "Mode: \(state.mode.rawValue)",
                "Version: \(state.upstreamVersion)",
                "Patchset: \(state.patchsetVersion)",
                "Feature: \(state.feature ?? "-")",
                "Source: \(state.source.original)",
                "Path: \(listing.path)",
            ] {
                terminal.output(line, machineReadable: true)
            }
        }
    }
}

struct Graph {

    enum Format: String {

        case tree

        case dot
    }

    let values: [String]

    let includeDevelopment: Bool

    let format: Format

    func run(terminal: Terminal) async throws {
        let (source, arguments) = try CLI.sourceAndArguments(values)
        guard arguments.count == 2 else {
            throw URIError.invalidArguments("graph requires VERSION PATCHSET.")
        }
        let reference = try CLI.reference(arguments[...])
        let resolver = PatchsetSourceResolver()
        let sourceRepository = try await resolver.resolve(source, reference: reference)
        defer { try? resolver.removeSnapshot(at: sourceRepository.snapshotURL) }
        let resolved = try sourceRepository.repository.resolve(reference)
        let orderedFeatureIDs = try resolved.orderedFeatures(
            in: includeDevelopment ? .includingDevelopment : .regular,
        ).map(\.id)
        switch format {
        case .tree:
            renderTree(
                resolved,
                orderedFeatureIDs: orderedFeatureIDs,
                terminal: terminal,
            )
        case .dot:
            renderDOT(
                resolved,
                orderedFeatureIDs: orderedFeatureIDs,
                terminal: terminal,
            )
        }
    }

    private func dependencies(of feature: URIModel.Feature) -> [String] {
        let regular = feature.dependencies ?? []
        return includeDevelopment ? regular + (feature.devDependencies ?? []) : regular
    }

    private func renderTree(
        _ patchset: ResolvedPatchset,
        orderedFeatureIDs: [String],
        terminal: Terminal,
    ) {
        var children = [String: [String]]()
        var hasParent = Set<String>()
        for featureID in orderedFeatureIDs {
            guard let feature = patchset.features[featureID] else {
                continue
            }
            for dependency in Set(dependencies(of: feature)).sorted()
            where dependency != featureID {
                children[dependency, default: []].append(featureID)
                hasParent.insert(featureID)
            }
        }
        var roots = orderedFeatureIDs.filter({ !hasParent.contains($0) })
        if roots.isEmpty {
            roots = orderedFeatureIDs
        }
        for root in roots {
            terminal.output(root, machineReadable: true)
            renderTreeChildren(
                root,
                prefix: "",
                children: children,
                terminal: terminal,
            )
        }
    }

    private func renderTreeChildren(
        _ featureID: String,
        prefix: String,
        children: [String: [String]],
        terminal: Terminal,
    ) {
        let values = children[featureID] ?? []
        for (index, child) in values.enumerated() {
            let isLast = index == values.count - 1
            terminal.output(
                "\(prefix)\(isLast ? "└─ " : "├─ ")\(child)",
                machineReadable: true,
            )
            renderTreeChildren(
                child,
                prefix: prefix + (isLast ? "   " : "│  "),
                children: children,
                terminal: terminal,
            )
        }
    }

    private func renderDOT(
        _ patchset: ResolvedPatchset,
        orderedFeatureIDs: [String],
        terminal: Terminal,
    ) {
        terminal.output("digraph dependencies {", machineReadable: true)
        for featureID in orderedFeatureIDs {
            terminal.output("  \(quoted(featureID));", machineReadable: true)
        }
        for featureID in orderedFeatureIDs {
            guard let feature = patchset.features[featureID] else {
                continue
            }
            for dependency in Set(dependencies(of: feature)).sorted()
            where dependency != featureID {
                terminal.output(
                    "  \(quoted(dependency)) -> \(quoted(feature.id));",
                    machineReadable: true,
                )
            }
        }
        terminal.output("}", machineReadable: true)
    }

    private func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
