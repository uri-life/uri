import ArgumentParser
import Foundation
import URI

@main
struct URICommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "uri",
        abstract: "Reconstruct, apply, and author portable Git patchsets.",
        version: Versions.current,
        subcommands: [
            Init.self,
            Add.self,
            Remove.self,
            Exclude.self,
            Include.self,
            List.self,
            Graph.self,
            Expand.self,
            Apply.self,
            Collapse.self,
            Vanish.self,
        ],
    )

    static func main() async {
        do {
            try CLI.preflightEphemeralPosition(arguments: Array(CommandLine.arguments.dropFirst()))
        }
        catch {
            exit(withError: ValidationError(String(describing: error)))
        }
        await main(nil)
    }
}
