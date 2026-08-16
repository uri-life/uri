import ArgumentParser
import Foundation
import URI

struct Expand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Expand one feature and its dependencies into editable branches.",
    )

    @Argument(help: "[SOURCE] VERSION PATCHSET FEATURE [TARGET], or [TARGET] with recovery flags.")
    var values: [String] = []

    @Flag(name: .customLong("continue")) var continueOperation = false
    @Flag(name: .customLong("abort")) var abortOperation = false
    @Flag var force = false
    @Flag(name: .customLong("no-dev")) var noDevelopmentDependencies = false
    @OptionGroup var ephemeralTarget: EphemeralTargetOption

    mutating func run() async throws {
        try await CLI.userFacing {
            guard !(continueOperation && abortOperation) else {
                throw URIError.invalidArguments("--continue and --abort cannot be used together.")
            }
            let workflow = URIWorkflow()
            if continueOperation || abortOperation {
                guard values.count <= 1 else {
                    throw URIError.invalidArguments("Recovery accepts at most TARGET.")
                }
                guard !force, !noDevelopmentDependencies else {
                    throw URIError.invalidArguments("Start-only options cannot be used for recovery.")
                }
                let ephemeralID = try CLI.selectedExistingEphemeralID(ephemeralTarget.ephemeral)
                let result: WorkflowResult
                if continueOperation {
                    result = try await workflow.continue(
                        mode: .expand,
                        targetURL: CLI.targetURL(values.first),
                        currentDirectoryURL: CLI.currentDirectoryURL,
                        ephemeralID: ephemeralID,
                    )
                    CLI.report(result, verb: "Expansion continued")
                }
                else {
                    result = try await workflow.abort(
                        mode: .expand,
                        targetURL: CLI.targetURL(values.first),
                        currentDirectoryURL: CLI.currentDirectoryURL,
                        ephemeralID: ephemeralID,
                    )
                    CLI.report(result, verb: "Expansion aborted")
                }
                return
            }

            let (source, arguments) = try CLI.sourceAndArguments(values)
            guard arguments.count == 3 || arguments.count == 4 else {
                throw URIError.invalidArguments(
                    "expand requires [SOURCE] VERSION PATCHSET FEATURE [TARGET].",
                )
            }
            let result = try await workflow.expand(
                source: source,
                reference: try CLI.reference(arguments[...]),
                featureID: arguments[2],
                targetURL: CLI.targetURL(arguments.count == 4 ? arguments[3] : nil),
                currentDirectoryURL: CLI.currentDirectoryURL,
                ephemeral: try CLI.ephemeralRequest(ephemeralTarget.ephemeral),
                includeDevelopmentDependencies: !noDevelopmentDependencies,
                force: force,
            )
            CLI.report(result, verb: "Expanded")
        }
    }
}

struct Apply: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Apply the complete regular dependency graph.",
    )

    @Argument(help: "[SOURCE] VERSION PATCHSET [TARGET], or [TARGET] with recovery flags.")
    var values: [String] = []

    @Flag(name: .customLong("continue")) var continueOperation = false
    @Flag(name: .customLong("abort")) var abortOperation = false
    @OptionGroup var ephemeralTarget: EphemeralTargetOption

    mutating func run() async throws {
        try await CLI.userFacing {
            guard !(continueOperation && abortOperation) else {
                throw URIError.invalidArguments("--continue and --abort cannot be used together.")
            }
            let workflow = URIWorkflow()
            if continueOperation || abortOperation {
                guard values.count <= 1 else {
                    throw URIError.invalidArguments("Recovery accepts at most TARGET.")
                }
                let ephemeralID = try CLI.selectedExistingEphemeralID(ephemeralTarget.ephemeral)
                let result: WorkflowResult
                if continueOperation {
                    result = try await workflow.continue(
                        mode: .apply,
                        targetURL: CLI.targetURL(values.first),
                        currentDirectoryURL: CLI.currentDirectoryURL,
                        ephemeralID: ephemeralID,
                    )
                    CLI.report(result, verb: "Apply continued")
                }
                else {
                    result = try await workflow.abort(
                        mode: .apply,
                        targetURL: CLI.targetURL(values.first),
                        currentDirectoryURL: CLI.currentDirectoryURL,
                        ephemeralID: ephemeralID,
                    )
                    CLI.report(result, verb: "Apply aborted")
                }
                return
            }

            let (source, arguments) = try CLI.sourceAndArguments(values)
            guard arguments.count == 2 || arguments.count == 3 else {
                throw URIError.invalidArguments(
                    "apply requires [SOURCE] VERSION PATCHSET [TARGET].",
                )
            }
            let result = try await workflow.apply(
                source: source,
                reference: try CLI.reference(arguments[...]),
                targetURL: CLI.targetURL(arguments.count == 3 ? arguments[2] : nil),
                currentDirectoryURL: CLI.currentDirectoryURL,
                ephemeral: try CLI.ephemeralRequest(ephemeralTarget.ephemeral),
            )
            CLI.report(result, verb: "Applied")
        }
    }
}

struct Collapse: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Reconstruct patches from a completed expansion.",
    )

    @Argument(help: "Optional TARGET. Expansion metadata supplies SOURCE, VERSION, PATCHSET, and FEATURE.")
    var target: String?

    @Flag var recursive = false
    @Flag var discard = false
    @OptionGroup var ephemeralTarget: EphemeralTargetOption

    mutating func run() async throws {
        try await CLI.userFacing {
            let ephemeralID = try CLI.selectedExistingEphemeralID(ephemeralTarget.ephemeral)
            let result = try await URIWorkflow().collapse(
                targetURL: CLI.targetURL(target),
                currentDirectoryURL: CLI.currentDirectoryURL,
                ephemeralID: ephemeralID,
                recursive: recursive,
                discard: discard,
            )
            CLI.report(result, verb: discard ? "Expansion discarded" : "Collapsed")
        }
    }
}

struct Vanish: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Safely remove an ephemeral workspace.",
    )

    @Argument(help: "Ephemeral ID. Omit to auto-select one workspace or prompt on a TTY.")
    var id: String?

    @Flag var force = false

    mutating func run() async throws {
        try await CLI.userFacing {
            let selected = try id.map({ value in
                try EphemeralWorkspaceManager.validateID(value)
                return value
            }) ?? CLI.selectEphemeralID()
            try await EphemeralWorkspaceManager().vanish(id: selected, force: force)
            print("Vanished: \(selected)")
        }
    }
}
