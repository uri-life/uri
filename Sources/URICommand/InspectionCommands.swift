import Foundation
import URI
import URIModel
import URIPatchset

struct List {

    enum Mode: Equatable {

        case hierarchy([String])

        case ephemeral(source: String?)
    }

    let mode: Mode

    private let currentDirectoryURL: URL

    private let ephemeralInspections: () throws -> [EphemeralWorkspaceInspection]

    init(
        mode: Mode,
        currentDirectoryURL: URL = CLI.currentDirectoryURL,
        ephemeralInspections: @escaping () throws -> [EphemeralWorkspaceInspection] = {
            try EphemeralWorkspaceManager().activeWorkspaceInspections()
        },
    ) {
        self.mode = mode
        self.currentDirectoryURL = currentDirectoryURL.standardizedFileURL
        self.ephemeralInspections = ephemeralInspections
    }

    func run(terminal: Terminal) async throws {
        let values: [String]
        switch mode {
        case .ephemeral(let source):
            try listEphemeral(source: source, terminal: terminal)
            return
        case .hierarchy(let hierarchyValues):
            values = hierarchyValues
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
        let reference =
            arguments.count == 2
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
        source sourceValue: String?,
        terminal: Terminal,
    ) throws {
        let source = try sourceValue.map({ value in
            try PatchsetSourceLocator.locate(
                value,
                currentDirectoryURL: currentDirectoryURL,
            )
        })
        let inspections = try ephemeralInspections()
        for inspection in inspections where inspection.location == .active {
            switch inspection.status {
            case .initializing:
                terminal.warning(
                    "warning: Ephemeral workspace \(inspection.id) is still initializing and was omitted.",
                )
            case .interruptedInitialization, .legacyIncomplete:
                terminal.warning(
                    "warning: Ephemeral workspace \(inspection.id) is incomplete and was omitted.",
                )
            case .valid, .deferredRemoval:
                break
            }
        }
        let listings = inspections.compactMap({ inspection -> EphemeralListing? in
            guard case .valid(let listing) = inspection.status else {
                return nil
            }
            return listing
        }).filter({ listing in
            guard let source else {
                return true
            }
            return sameRoot(listing.state.source, source)
        })
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
    }

    private func sameRoot(
        _ first: PatchsetSource,
        _ second: PatchsetSource,
    ) -> Bool {
        guard first.kind == second.kind else {
            return false
        }
        switch first.kind {
        case .local:
            guard let firstRoot = first.localRootURL, let secondRoot = second.localRootURL else {
                return false
            }
            return canonicalPath(firstRoot) == canonicalPath(secondRoot)
        case .http, .git:
            return first.original == second.original
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
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
