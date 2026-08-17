import Foundation
import URI
import URIModel
import URIPatchset

struct Init {

    let values: [String]

    let upstream: String?

    let branchPrefix: String?

    let committerName: String?

    let committerEmail: String?

    func run(terminal: Terminal) async throws {
        let split = CLI.splitSource(values)
        if let source = split.source,
            source.contains("://") || source.contains("@") && source.contains(":")
        {
            throw URIError.remoteSourceIsReadOnly("init requires a local SOURCE directory.")
        }
        guard split.rest.count <= 1 else {
            throw URIError.invalidArguments("init accepts at most SOURCE and VERSION.")
        }
        guard (committerName == nil) == (committerEmail == nil) else {
            throw URIError.invalidArguments(
                "--committer-name and --committer-email must be specified together.",
            )
        }
        let rootURL: URL
        if let source = split.source {
            rootURL = CLI.targetURL(source)!
        }
        else if let discovered = try? PatchsetSourceLocator.discoverLocalRoot(
            from: CLI.currentDirectoryURL,
        ) {
            rootURL = discovered
        }
        else {
            rootURL = CLI.currentDirectoryURL
        }
        guard (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw URIError.sourceNotFound(
                "init requires an existing directory and does not create SOURCE: \(rootURL.path)",
            )
        }
        let repository = try PatchsetRepository(rootURL: rootURL)
        if FileManager.default.fileExists(atPath: rootURL.appending(path: "manifest.yaml").path) {
            let existing = try repository.rootManifest()
            if let upstream, upstream != existing.upstream {
                throw URIError.invalidArguments("The existing upstream setting cannot be changed.")
            }
            if let branchPrefix,
                branchPrefix != (existing.branchPrefix ?? RootManifest.legacyBranchPrefix)
            {
                throw URIError.invalidArguments(
                    "The existing branch-prefix setting cannot be changed.",
                )
            }
            if let committerName, let committerEmail,
                existing.committer
                    != .explicit(.init(name: committerName, email: committerEmail))
            {
                throw URIError.invalidArguments("The existing committer setting cannot be changed.")
            }
            guard !split.rest.isEmpty else {
                throw URIError.invalidArguments(
                    "Already initialized: \(rootURL.path)/manifest.yaml",
                )
            }
        }
        else {
            guard let upstream, !upstream.isEmpty else {
                throw URIError.invalidArguments("A new patchset root requires --upstream URL.")
            }
            let committer: RootManifest.Committer
            if let committerName, let committerEmail {
                committer = .explicit(.init(name: committerName, email: committerEmail))
            }
            else {
                committer = .repository
            }
            try repository.initializeRoot(
                with: .init(
                    upstream: upstream,
                    branchPrefix: branchPrefix ?? RootManifest.legacyBranchPrefix,
                    committer: committer,
                ),
            )
            terminal.success(
                "Initialized",
                value: rootURL.appending(path: "manifest.yaml").path,
            )
        }
        if let version = split.rest.first {
            try repository.createUpstreamVersion(version)
            terminal.success("Created upstream version", value: version)
        }
    }
}

struct Add {

    let values: [String]

    let name: String?

    let featureDescription: String?

    let dependencies: String?

    let devDependencies: String?

    let inherits: String?

    let inheritsUpstream: String?

    func run(terminal: Terminal) async throws {
        let (repository, arguments) = try CLI.localRepository(from: values)
        guard arguments.count == 2 || arguments.count == 3 else {
            throw URIError.invalidArguments("add requires VERSION PATCHSET [FEATURE].")
        }
        let reference = try CLI.reference(arguments[...])
        if arguments.count == 2 {
            guard name == nil,
                featureDescription == nil,
                dependencies == nil,
                devDependencies == nil
            else {
                throw URIError.invalidArguments("Feature options require FEATURE.")
            }
            let parent: PatchsetReference?
            if let inherits {
                if let separator = inherits.firstIndex(of: "+") {
                    parent = try .init(
                        upstreamVersion: String(inherits[..<separator]),
                        patchsetVersion: String(inherits[inherits.index(after: separator)...]),
                    )
                }
                else {
                    parent = try .init(
                        upstreamVersion: inheritsUpstream ?? reference.upstreamVersion,
                        patchsetVersion: inherits,
                    )
                }
            }
            else {
                guard inheritsUpstream == nil else {
                    throw URIError.invalidArguments("--inherits-upstream requires --inherits.")
                }
                parent = nil
            }
            try repository.createPatchset(reference, inheriting: parent)
            terminal.success("Added patchset", value: reference.description)
        }
        else {
            guard inherits == nil, inheritsUpstream == nil else {
                throw URIError.invalidArguments(
                    "Inheritance options cannot be used with FEATURE.",
                )
            }
            let featureID = arguments[2]
            try repository.addFeature(
                .init(
                    id: featureID,
                    name: name ?? featureID,
                    description: featureDescription ?? "",
                    dependencies: CLI.csv(dependencies) ?? [],
                    devDependencies: CLI.csv(devDependencies) ?? [],
                ),
                to: reference,
            )
            terminal.success("Added feature", value: featureID)
        }
    }
}

struct Remove {

    let values: [String]

    let force: Bool

    func run(terminal: Terminal) async throws {
        let (repository, arguments) = try CLI.localRepository(from: values)
        guard (1...3).contains(arguments.count) else {
            throw URIError.invalidArguments("remove requires VERSION [PATCHSET] [FEATURE].")
        }
        if arguments.count == 1 {
            try CLI.requireConfirmation(
                "Delete upstream version '\(arguments[0])'?",
                forced: force,
                terminal: terminal,
            )
            try repository.removeUpstreamVersion(arguments[0])
        }
        else {
            let reference = try CLI.reference(arguments[...])
            if arguments.count == 2 {
                try CLI.requireConfirmation(
                    "Delete patchset '\(reference)'?",
                    forced: force,
                    terminal: terminal,
                )
                try repository.removePatchset(reference)
            }
            else {
                try CLI.requireConfirmation(
                    "Delete feature '\(arguments[2])'?",
                    forced: force,
                    terminal: terminal,
                )
                try repository.removeFeature(arguments[2], from: reference, force: force)
            }
        }
        terminal.success("Removed.")
    }
}

struct Exclude {

    let values: [String]

    func run(terminal: Terminal) async throws {
        let (repository, arguments) = try CLI.localRepository(from: values)
        guard arguments.count == 3 else {
            throw URIError.invalidArguments("exclude requires VERSION PATCHSET FEATURE.")
        }
        try repository.excludeFeature(arguments[2], from: CLI.reference(arguments[...]))
        terminal.success("Excluded feature", value: arguments[2])
    }
}

struct Include {

    let values: [String]

    func run(terminal: Terminal) async throws {
        let (repository, arguments) = try CLI.localRepository(from: values)
        guard arguments.count == 3 else {
            throw URIError.invalidArguments("include requires VERSION PATCHSET FEATURE.")
        }
        try repository.includeFeature(arguments[2], in: CLI.reference(arguments[...]))
        terminal.success("Included feature", value: arguments[2])
    }
}
