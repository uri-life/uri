import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import URI
import URIModel
import URIPatchset

enum CLI {

    static let automaticEphemeralID = "__URI_AUTOMATIC_EPHEMERAL_ID__"

    static var currentDirectoryURL: URL {
        URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
    }

    static func splitSource(_ values: [String]) -> (source: String?, rest: [String]) {
        guard let first = values.first, PatchsetSourceLocator.recognizesExplicitSource(first) else {
            return (nil, values)
        }
        return (first, Array(values.dropFirst()))
    }

    static func sourceAndArguments(
        _ values: [String],
    ) throws -> (PatchsetSource, [String]) {
        let split = splitSource(values)
        return (
            try PatchsetSourceLocator.locate(
                split.source,
                currentDirectoryURL: currentDirectoryURL,
            ),
            split.rest
        )
    }

    static func localRepository(
        from values: [String],
    ) throws -> (PatchsetRepository, [String]) {
        let (source, arguments) = try sourceAndArguments(values)
        guard source.kind == .local, let rootURL = source.localRootURL else {
            throw URIError.remoteSourceIsReadOnly(
                "This command writes the patchset and requires a local SOURCE.",
            )
        }
        let repository = try PatchsetRepository(rootURL: rootURL)
        _ = try repository.rootManifest()
        return (repository, arguments)
    }

    static func reference(_ values: ArraySlice<String>) throws -> PatchsetReference {
        guard values.count >= 2 else {
            throw URIError.invalidArguments("VERSION and PATCHSET are required.")
        }
        return try .init(
            upstreamVersion: values[values.startIndex],
            patchsetVersion: values[values.index(after: values.startIndex)],
        )
    }

    static func targetURL(_ value: String?) -> URL? {
        value.map({ URL(filePath: expandTilde($0), relativeTo: currentDirectoryURL).standardizedFileURL })
    }

    static func ephemeralRequest(_ value: String?) throws -> EphemeralRequest {
        guard let value else {
            return .none
        }
        if value == automaticEphemeralID {
            return .automatic
        }
        try EphemeralWorkspaceManager.validateID(value)
        return .named(value)
    }

    static func selectedExistingEphemeralID(_ value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        if value != automaticEphemeralID {
            try EphemeralWorkspaceManager.validateID(value)
            return value
        }
        return try selectEphemeralID()
    }

    static func selectEphemeralID() throws -> String {
        let listings = try EphemeralWorkspaceManager().list()
        if listings.isEmpty {
            throw URIError.operationNotFound("No ephemeral workspaces exist.")
        }
        if listings.count == 1 {
            return listings[0].id
        }
        guard isatty(STDIN_FILENO) == 1 else {
            throw URIError.invalidArguments(
                "Multiple ephemeral workspaces exist; specify an ID in non-interactive use.",
            )
        }
        for (index, listing) in listings.enumerated() {
            print("\(index + 1)) \(listing.id)\t\(listing.state.mode.rawValue)\t\(listing.path)")
        }
        print("Select an ephemeral workspace: ", terminator: "")
        unsafe fflush(stdout)
        guard let line = readLine(), let selection = Int(line), listings.indices.contains(selection - 1) else {
            throw URIError.invalidArguments("Invalid ephemeral workspace selection.")
        }
        return listings[selection - 1].id
    }

    static func requireConfirmation(_ prompt: String, forced: Bool) throws {
        guard !forced else {
            return
        }
        print("\(prompt) [y/N] ", terminator: "")
        unsafe fflush(stdout)
        let answer = readLine()?.lowercased()
        guard answer == "y" || answer == "yes" else {
            throw URIError.invalidArguments("Canceled.")
        }
    }

    static func csv(_ value: String?) -> [String]? {
        value.map({ csv in
            csv.split(separator: ",")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .filter({ !$0.isEmpty })
        })
    }

    static func preflightEphemeralPosition(arguments: [String]) throws {
        guard let command = arguments.first,
            ["expand", "apply", "collapse"].contains(command),
            let index = arguments.firstIndex(where: {
                $0 == "--ephemeral" || $0.hasPrefix("--ephemeral=")
            })
        else {
            return
        }
        let option = arguments[index]
        let suffixCount = arguments.distance(from: index, to: arguments.endIndex)
        if option.hasPrefix("--ephemeral=") {
            guard suffixCount == 1 else {
                throw URIError.invalidArguments(
                    "--ephemeral [ID] must be the final TARGET selector in the command.",
                )
            }
            return
        }
        guard suffixCount == 1 || suffixCount == 2 else {
            throw URIError.invalidArguments(
                "--ephemeral [ID] must be the final TARGET selector in the command.",
            )
        }
        if suffixCount == 2, arguments[arguments.index(after: index)].hasPrefix("-") {
            throw URIError.invalidArguments(
                "--ephemeral [ID] must be the final TARGET selector in the command.",
            )
        }
    }

    static func report(_ result: WorkflowResult, verb: String) {
        print("\(verb): \(result.targetURL.path)")
        if let id = result.ephemeralID {
            print("Ephemeral ID: \(id)")
        }
        if let branch = result.branch {
            print("Branch: \(branch)")
        }
    }

    static func userFacing<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        }
        catch {
            throw ValidationError(String(describing: error))
        }
    }

    static func userFacing<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        }
        catch {
            throw ValidationError(String(describing: error))
        }
    }

    private static func expandTilde(_ value: String) -> String {
        guard value == "~" || value.hasPrefix("~/") else {
            return value
        }
        let suffix = value.dropFirst(value == "~" ? 1 : 2)
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: String(suffix)).path
    }
}

struct EphemeralTargetOption: ParsableArguments {

    @Option(
        name: .long,
        defaultAsFlag: CLI.automaticEphemeralID,
        parsing: .next,
        help: "Use an ephemeral TARGET, optionally with ID. This selector must be last.",
    )
    var ephemeral: String?
}
