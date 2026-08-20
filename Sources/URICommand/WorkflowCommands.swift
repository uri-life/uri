import Foundation
import URI

struct Expand {

    let values: [String]

    let continueOperation: Bool

    let abortOperation: Bool

    let force: Bool

    let noDevelopmentDependencies: Bool

    let target: TargetArgumentValue

    func run(terminal: Terminal) async throws {
        guard !(continueOperation && abortOperation) else {
            throw URIError.invalidArguments("--continue and --abort cannot be used together.")
        }
        let workflow = URIWorkflow()
        if continueOperation || abortOperation {
            guard !force, !noDevelopmentDependencies else {
                throw URIError.invalidArguments("Start-only options cannot be used for recovery.")
            }
            let ephemeralID = try CLI.selectedExistingEphemeralID(
                target,
                terminal: terminal,
            )
            let result: WorkflowResult
            if continueOperation {
                result = try await workflow.continue(
                    mode: .expand,
                    targetURL: CLI.targetURL(target),
                    currentDirectoryURL: CLI.currentDirectoryURL,
                    ephemeralID: ephemeralID,
                )
                CLI.report(result, verb: "Expansion continued", terminal: terminal)
            }
            else {
                result = try await workflow.abort(
                    mode: .expand,
                    targetURL: CLI.targetURL(target),
                    currentDirectoryURL: CLI.currentDirectoryURL,
                    ephemeralID: ephemeralID,
                )
                CLI.report(result, verb: "Expansion aborted", terminal: terminal)
            }
            return
        }

        let (source, arguments) = try CLI.sourceAndArguments(values)
        guard arguments.count == 3 else {
            throw URIError.invalidArguments(
                "expand requires [SOURCE] VERSION PATCHSET FEATURE [TARGET].",
            )
        }
        let result = try await workflow.expand(
            source: source,
            reference: try CLI.reference(arguments[...]),
            featureID: arguments[2],
            targetURL: CLI.targetURL(target),
            currentDirectoryURL: CLI.currentDirectoryURL,
            ephemeral: try CLI.ephemeralRequest(target),
            includeDevelopmentDependencies: !noDevelopmentDependencies,
            force: force,
        )
        CLI.report(result, verb: "Expanded", terminal: terminal)
    }
}

struct Apply {

    let values: [String]

    let continueOperation: Bool

    let abortOperation: Bool

    let includeDevelopmentDependencies: Bool

    let target: TargetArgumentValue

    func run(terminal: Terminal) async throws {
        guard !(continueOperation && abortOperation) else {
            throw URIError.invalidArguments("--continue and --abort cannot be used together.")
        }
        let workflow = URIWorkflow()
        if continueOperation || abortOperation {
            let ephemeralID = try CLI.selectedExistingEphemeralID(
                target,
                terminal: terminal,
            )
            let result: WorkflowResult
            if continueOperation {
                result = try await workflow.continue(
                    mode: .apply,
                    targetURL: CLI.targetURL(target),
                    currentDirectoryURL: CLI.currentDirectoryURL,
                    ephemeralID: ephemeralID,
                )
                CLI.report(result, verb: "Apply continued", terminal: terminal)
            }
            else {
                result = try await workflow.abort(
                    mode: .apply,
                    targetURL: CLI.targetURL(target),
                    currentDirectoryURL: CLI.currentDirectoryURL,
                    ephemeralID: ephemeralID,
                )
                CLI.report(result, verb: "Apply aborted", terminal: terminal)
            }
            return
        }

        let (source, arguments) = try CLI.sourceAndArguments(values)
        guard arguments.count == 2 else {
            throw URIError.invalidArguments(
                "apply requires [SOURCE] VERSION PATCHSET [TARGET].",
            )
        }
        let result = try await workflow.apply(
            source: source,
            reference: try CLI.reference(arguments[...]),
            targetURL: CLI.targetURL(target),
            currentDirectoryURL: CLI.currentDirectoryURL,
            ephemeral: try CLI.ephemeralRequest(target),
            includeDevelopmentDependencies: includeDevelopmentDependencies,
        )
        CLI.report(result, verb: "Applied", terminal: terminal)
    }
}

struct Collapse {

    let target: TargetArgumentValue

    let recursive: Bool

    let discard: Bool

    func run(terminal: Terminal) async throws {
        let ephemeralID = try CLI.selectedExistingEphemeralID(
            target,
            terminal: terminal,
        )
        let result = try await URIWorkflow().collapse(
            targetURL: CLI.targetURL(target),
            currentDirectoryURL: CLI.currentDirectoryURL,
            ephemeralID: ephemeralID,
            recursive: recursive,
            discard: discard,
        )
        CLI.report(
            result,
            verb: discard ? "Expansion discarded" : "Collapsed",
            terminal: terminal,
        )
    }
}

struct Vanish {

    let id: String?

    let force: Bool

    func run(terminal: Terminal) async throws {
        let selected =
            try id.map({ value in
                try EphemeralWorkspaceManager.validateID(value)
                return value
            }) ?? CLI.selectEphemeralID(terminal: terminal)
        try await EphemeralWorkspaceManager().vanish(id: selected, force: force)
        terminal.success("Vanished", value: selected)
    }
}
