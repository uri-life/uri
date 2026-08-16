import ArgumentParser
import Foundation
import URI
import URIModel
import URIPatchset

struct List: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "List patchset versions, patchsets, features, or ephemeral workspaces.",
    )

    @Argument(help: "[SOURCE] [VERSION] [PATCHSET]")
    var values: [String] = []

    @Option(
        name: .long,
        defaultAsFlag: CLI.automaticEphemeralID,
        help: "List ephemeral workspaces, or inspect one ID.",
    )
    var ephemeral: String?

    @Flag(help: "With --ephemeral ID, print only its repository path.")
    var path = false

    mutating func run() async throws {
        try await CLI.userFacing {
            if let ephemeral {
                guard values.isEmpty else {
                    throw URIError.invalidArguments(
                        "Patchset SOURCE arguments cannot be combined with --ephemeral.",
                    )
                }
                try listEphemeral(ephemeral)
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
                    print(version)
                }
            }
            else if arguments.count == 1 {
                for reference in try resolved.repository.patchsets(in: arguments[0]) {
                    print(reference.patchsetVersion)
                }
            }
            else if let reference {
                for feature in try resolved.repository.resolve(reference).orderedFeatures(
                    in: .includingDevelopment,
                ) {
                    print(feature.id)
                }
            }
        }
    }

    private func listEphemeral(_ value: String) throws {
        let manager = EphemeralWorkspaceManager()
        if value == CLI.automaticEphemeralID {
            guard !path else {
                throw URIError.invalidArguments("--path requires an explicit ephemeral ID.")
            }
            let listings = try manager.list()
            if !listings.isEmpty {
                print("ID\tMODE\tVERSION\tPATCHSET\tFEATURE\tSOURCE\tPATH")
            }
            for listing in listings {
                let state = listing.state
                print(
                    [
                        listing.id,
                        state.mode.rawValue,
                        state.upstreamVersion,
                        state.patchsetVersion,
                        state.feature ?? "-",
                        state.source.original,
                        listing.path,
                    ].joined(separator: "\t"),
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
            print(listing.path)
        }
        else {
            let state = listing.state
            print("ID: \(listing.id)")
            print("Mode: \(state.mode.rawValue)")
            print("Version: \(state.upstreamVersion)")
            print("Patchset: \(state.patchsetVersion)")
            print("Feature: \(state.feature ?? "-")")
            print("Source: \(state.source.original)")
            print("Path: \(listing.path)")
        }
    }
}

struct Graph: AsyncParsableCommand {

    enum Format: String, ExpressibleByArgument {
        case tree
        case dot
    }

    static let configuration = CommandConfiguration(abstract: "Print a feature dependency graph.")

    @Argument(help: "[SOURCE] VERSION PATCHSET")
    var values: [String] = []

    @Flag(name: .customLong("include-dev"))
    var includeDevelopment = false

    @Option
    var format: Format = .tree

    mutating func run() async throws {
        try await CLI.userFacing {
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
                renderTree(resolved, orderedFeatureIDs: orderedFeatureIDs)
            case .dot:
                renderDOT(resolved, orderedFeatureIDs: orderedFeatureIDs)
            }
        }
    }

    private func dependencies(of feature: URIModel.Feature) -> [String] {
        let regular = feature.dependencies ?? []
        return includeDevelopment ? regular + (feature.devDependencies ?? []) : regular
    }

    private func renderTree(
        _ patchset: ResolvedPatchset,
        orderedFeatureIDs: [String],
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
            print(root)
            renderTreeChildren(root, prefix: "", children: children)
        }
    }

    private func renderTreeChildren(
        _ featureID: String,
        prefix: String,
        children: [String: [String]],
    ) {
        let values = children[featureID] ?? []
        for (index, child) in values.enumerated() {
            let isLast = index == values.count - 1
            print("\(prefix)\(isLast ? "└─ " : "├─ ")\(child)")
            renderTreeChildren(
                child,
                prefix: prefix + (isLast ? "   " : "│  "),
                children: children,
            )
        }
    }

    private func renderDOT(
        _ patchset: ResolvedPatchset,
        orderedFeatureIDs: [String],
    ) {
        print("digraph dependencies {")
        for featureID in orderedFeatureIDs {
            print("  \(quoted(featureID));")
        }
        for featureID in orderedFeatureIDs {
            guard let feature = patchset.features[featureID] else {
                continue
            }
            for dependency in Set(dependencies(of: feature)).sorted()
            where dependency != featureID {
                print("  \(quoted(dependency)) -> \(quoted(feature.id));")
            }
        }
        print("}")
    }

    private func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
