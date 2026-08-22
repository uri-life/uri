import Foundation
import URI
import URIModel
import URIPatchset

enum CompletionRecord: Equatable {

    case candidate(value: String, description: String)

    case directories

    var encoded: String {
        switch self {
        case .candidate(let value, let description):
            return "candidate\t\(value)\t\(description)"
        case .directories:
            return "directive\tdirectories"
        }
    }
}

struct CompletionEngine {

    private struct PendingOption {

        let definition: OptionDefinition

        let values: [String]
    }

    private struct CommandScan {

        var positionals = [PositionalToken]()

        var options = [OptionID: ParsedOption]()

        var seen = Set<OptionID>()

        var parsesOptions = true

        var pendingOption: PendingOption?

        var pendingEphemeralTarget = false
    }

    private struct FormProgress {

        let form: CommandForm

        let values: [ArgumentID: String]

        let nextArguments: [ArgumentDefinition]
    }

    private let currentDirectoryURL: URL

    private let paths: RuntimePaths

    init(
        currentDirectoryURL: URL = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory,
        ),
        paths: RuntimePaths = .init(),
    ) {
        self.currentDirectoryURL = currentDirectoryURL.standardizedFileURL
        self.paths = paths
    }

    func complete(_ words: [String]) -> [CompletionRecord] {
        guard let current = words.last else {
            return []
        }

        let records = rootRecords(
            committed: Array(words.dropLast()),
            current: current,
        )
        return normalized(records)
    }

    private func rootRecords(
        committed: [String],
        current: String,
    ) -> [CompletionRecord] {
        var parsesOptions = true
        var index = 0

        while index < committed.count {
            let token = committed[index]
            if parsesOptions, token == "--" {
                parsesOptions = false
                index += 1
                continue
            }
            if token == "help" {
                return helpRecords(
                    committed: Array(committed.dropFirst(index + 1)),
                    current: current,
                )
            }
            if let command = CommandCatalog.command(named: token) {
                return commandRecords(
                    command,
                    committed: Array(committed.dropFirst(index + 1)),
                    current: current,
                )
            }
            guard parsesOptions, let optionMatch = rootOption(matching: token) else {
                return []
            }
            let option = optionMatch.definition
            switch option.valueKind {
            case .flag:
                guard optionMatch.attachedValue == nil else {
                    return []
                }
                index += 1
                if option.id == .help || option.id == .version {
                    return []
                }
            case .value:
                if optionMatch.attachedValue != nil {
                    index += 1
                }
                else if committed.indices.contains(index + 1) {
                    index += 2
                }
                else {
                    return optionValueRecords(
                        option,
                        prefix: current,
                        attachedPrefix: nil,
                        scan: .init(),
                        progresses: [],
                    )
                }
                if option.id == .completion {
                    return []
                }
            case .values:
                return []
            }
        }

        if parsesOptions, let attached = attachedRootOption(in: current) {
            return optionValueRecords(
                attached.definition,
                prefix: attached.value,
                attachedPrefix: "--\(attached.definition.longName)=",
                scan: .init(),
                progresses: [],
            )
        }
        if parsesOptions, current.hasPrefix("-") {
            return optionRecords(
                CommandCatalog.rootOptions,
                prefix: current,
            )
        }

        let commands =
            CommandCatalog.commands.map({ command in
                CompletionRecord.candidate(
                    value: command.name,
                    description: command.abstract,
                )
            }) + [
                .candidate(
                    value: "help",
                    description: "Show help information for a command.",
                )
            ]
        return commands.filter({ $0.value?.hasPrefix(current) == true })
    }

    private func helpRecords(
        committed: [String],
        current: String,
    ) -> [CompletionRecord] {
        let names = committed.filter({ !$0.hasPrefix("-") })
        guard names.isEmpty else {
            return []
        }
        if current.hasPrefix("-") {
            return optionRecords(
                [CommandCatalog.colorOption, CommandCatalog.helpOption],
                prefix: current,
            )
        }
        return CommandCatalog.commands.compactMap({ command in
            guard command.name.hasPrefix(current) else {
                return nil
            }
            return .candidate(value: command.name, description: command.abstract)
        })
    }

    private func commandRecords(
        _ command: CommandDefinition,
        committed: [String],
        current: String,
    ) -> [CompletionRecord] {
        guard let scan = scan(command, committed: committed) else {
            return []
        }
        let progresses = progresses(command, scan: scan)
        guard !progresses.isEmpty else {
            return []
        }

        if let pendingOption = scan.pendingOption {
            return optionValueRecords(
                pendingOption.definition,
                prefix: current,
                attachedPrefix: nil,
                partialValues: pendingOption.values,
                scan: scan,
                progresses: progresses,
            )
        }
        if scan.pendingEphemeralTarget, !current.hasPrefix("-") {
            return ephemeralIDRecords(
                prefix: current,
                attachedPrefix: nil,
                command: command,
                progresses: progresses,
            )
        }
        if scan.parsesOptions,
            let attached = attachedOption(in: current, command: command)
        {
            return optionValueRecords(
                attached.definition,
                prefix: attached.value,
                attachedPrefix: "--\(attached.definition.longName)=",
                partialValues: [],
                scan: scan,
                progresses: progresses,
            )
        }
        if scan.parsesOptions,
            let ephemeral = command.ephemeralTarget,
            current.hasPrefix("\(ephemeral.token)=")
        {
            let prefix = String(current.dropFirst(ephemeral.token.count + 1))
            let targetProgresses = progresses.filter({ progress in
                progress.nextArguments.contains(where: { $0.id == .target })
            })
            return ephemeralIDRecords(
                prefix: prefix,
                attachedPrefix: "\(ephemeral.token)=",
                command: command,
                progresses: targetProgresses,
            )
        }
        if scan.parsesOptions, current.hasPrefix("-") {
            return commandOptionRecords(
                command,
                scan: scan,
                progresses: progresses,
                prefix: current,
            )
        }

        var records = progresses.flatMap({ progress in
            progress.nextArguments.flatMap({ argument in
                argumentRecords(
                    argument,
                    command: command,
                    progress: progress,
                    prefix: current,
                    allowsEphemeralToken: scan.parsesOptions,
                )
            })
        })
        if scan.parsesOptions, current.isEmpty {
            records += commandOptionRecords(
                command,
                scan: scan,
                progresses: progresses,
                prefix: current,
            )
        }
        return records
    }

    private func scan(
        _ command: CommandDefinition,
        committed: [String],
    ) -> CommandScan? {
        let definitions = command.options + CommandCatalog.globalCommandOptions
        let longOptions = Dictionary(
            definitions.map({ ($0.longName, $0) }),
            uniquingKeysWith: { first, _ in first },
        )
        let shortOptions = Dictionary(
            definitions.compactMap({ option in
                option.shortName.map({ ($0, option) })
            }),
            uniquingKeysWith: { first, _ in first },
        )
        var scan = CommandScan()
        var sawEphemeralTarget = false
        var index = 0

        while index < committed.count {
            let token = committed[index]
            if scan.parsesOptions, token == "--" {
                guard !sawEphemeralTarget else {
                    return nil
                }
                scan.parsesOptions = false
                index += 1
                continue
            }
            if scan.parsesOptions,
                let ephemeral = command.ephemeralTarget,
                token == ephemeral.token || token.hasPrefix("\(ephemeral.token)=")
            {
                guard !sawEphemeralTarget else {
                    return nil
                }
                if token.hasPrefix("\(ephemeral.token)=") {
                    let id = String(token.dropFirst(ephemeral.token.count + 1))
                    guard !id.isEmpty, (try? EphemeralWorkspaceManager.validateID(id)) != nil else {
                        return nil
                    }
                    scan.positionals.append(.ephemeralTarget(id: id))
                    index += 1
                }
                else if committed.indices.contains(index + 1),
                    committed[index + 1] != "--",
                    !committed[index + 1].hasPrefix("-")
                {
                    let id = committed[index + 1]
                    guard (try? EphemeralWorkspaceManager.validateID(id)) != nil else {
                        return nil
                    }
                    scan.positionals.append(.ephemeralTarget(id: id))
                    index += 2
                }
                else {
                    scan.positionals.append(.ephemeralTarget(id: nil))
                    scan.pendingEphemeralTarget = !committed.indices.contains(index + 1)
                    index += 1
                }
                sawEphemeralTarget = true
                continue
            }
            guard scan.parsesOptions, token.hasPrefix("-"), token != "-" else {
                scan.positionals.append(.value(token))
                index += 1
                continue
            }

            guard
                let match = option(
                    matching: token,
                    longOptions: longOptions,
                    shortOptions: shortOptions,
                ),
                scan.seen.insert(match.definition.id).inserted
            else {
                return nil
            }
            switch match.definition.valueKind {
            case .flag:
                guard match.attachedValue == nil else {
                    return nil
                }
                scan.options[match.definition.id] = .flag
                index += 1
            case .value:
                if let value = match.attachedValue {
                    guard !value.isEmpty else {
                        return nil
                    }
                    scan.options[match.definition.id] = .value(value)
                    index += 1
                }
                else if committed.indices.contains(index + 1),
                    committed[index + 1] != "--",
                    !committed[index + 1].hasPrefix("-")
                {
                    scan.options[match.definition.id] = .value(committed[index + 1])
                    index += 2
                }
                else if index == committed.count - 1 {
                    scan.options[match.definition.id] = .value("")
                    scan.pendingOption = .init(definition: match.definition, values: [])
                    index += 1
                }
                else {
                    return nil
                }
            case .values(let names):
                guard match.attachedValue == nil else {
                    return nil
                }
                var values = [String]()
                var valueIndex = index + 1
                while values.count < names.count,
                    committed.indices.contains(valueIndex),
                    committed[valueIndex] != "--",
                    !committed[valueIndex].hasPrefix("-")
                {
                    values.append(committed[valueIndex])
                    valueIndex += 1
                }
                scan.options[match.definition.id] = .values(values)
                if values.count == names.count {
                    index = valueIndex
                }
                else if valueIndex == committed.count {
                    scan.pendingOption = .init(definition: match.definition, values: values)
                    index = valueIndex
                }
                else {
                    return nil
                }
            }
        }

        if command.id == .collapse,
            scan.seen.contains(.recursive),
            scan.seen.contains(.discard)
        {
            return nil
        }
        return scan
    }

    private func progresses(
        _ command: CommandDefinition,
        scan: CommandScan,
    ) -> [FormProgress] {
        let globalOptions = Set(CommandCatalog.globalCommandOptions.map(\.id))
        let commandOptions = scan.seen.subtracting(globalOptions)
        return command.forms.compactMap({ form in
            guard commandOptions.isSubset(of: form.allowedOptions) else {
                return nil
            }
            for element in form.elements {
                if case .oneOf(let options) = element,
                    options.filter(scan.seen.contains).count > 1
                {
                    return nil
                }
            }
            return progress(form, positionals: scan.positionals)
        })
    }

    private func progress(
        _ form: CommandForm,
        positionals: [PositionalToken],
    ) -> FormProgress? {
        let arguments = form.arguments
        var values = [ArgumentID: String]()
        var tokenIndex = 0
        var argumentIndex = 0

        while argumentIndex < arguments.count, tokenIndex < positionals.count {
            let argument = arguments[argumentIndex]
            let token = positionals[tokenIndex]
            switch argument.valueKind {
            case .source:
                if case .value(let value) = token,
                    PatchsetSourceLocator.recognizesExplicitSource(value)
                {
                    values[argument.id] = value
                    tokenIndex += 1
                }
                else if !argument.optional {
                    return nil
                }
            case .scalar:
                guard case .value(let value) = token else {
                    return nil
                }
                values[argument.id] = value
                tokenIndex += 1
            case .target(let target):
                switch token {
                case .value(let value):
                    values[argument.id] = value
                    tokenIndex += 1
                case .ephemeralTarget where target.ephemeral != nil:
                    tokenIndex += 1
                default:
                    return nil
                }
            }
            argumentIndex += 1
        }
        guard tokenIndex == positionals.count else {
            return nil
        }

        var nextArguments = [ArgumentDefinition]()
        while argumentIndex < arguments.count {
            let argument = arguments[argumentIndex]
            nextArguments.append(argument)
            argumentIndex += 1
            if !argument.optional {
                break
            }
        }
        return .init(
            form: form,
            values: values,
            nextArguments: nextArguments,
        )
    }

    private func commandOptionRecords(
        _ command: CommandDefinition,
        scan: CommandScan,
        progresses: [FormProgress],
        prefix: String,
    ) -> [CompletionRecord] {
        let commandOptions = command.options.filter({ option in
            guard !scan.seen.contains(option.id) else {
                return false
            }
            if command.id == .collapse {
                if option.id == .recursive, scan.seen.contains(.discard) {
                    return false
                }
                if option.id == .discard, scan.seen.contains(.recursive) {
                    return false
                }
            }
            return progresses.contains(where: { progress in
                guard progress.form.allowedOptions.contains(option.id) else {
                    return false
                }
                for element in progress.form.elements {
                    if case .oneOf(let options) = element,
                        options.contains(option.id),
                        options.contains(where: scan.seen.contains)
                    {
                        return false
                    }
                }
                return true
            })
        })
        let globalOptions = CommandCatalog.globalCommandOptions.filter({
            !scan.seen.contains($0.id)
        })
        var records = optionRecords(commandOptions + globalOptions, prefix: prefix)
        if let ephemeral = command.ephemeralTarget,
            progresses.contains(where: { progress in
                progress.nextArguments.contains(where: { $0.id == .target })
            }),
            ephemeral.token.hasPrefix(prefix)
        {
            records.append(.candidate(value: ephemeral.token, description: ephemeral.help))
        }
        return records
    }

    private func optionRecords(
        _ options: [OptionDefinition],
        prefix: String,
    ) -> [CompletionRecord] {
        options.flatMap({ option in
            var tokens = ["--\(option.longName)"]
            if let shortName = option.shortName {
                tokens.append("-\(shortName)")
            }
            return tokens.compactMap({ token -> CompletionRecord? in
                guard token.hasPrefix(prefix) else {
                    return nil
                }
                return CompletionRecord.candidate(value: token, description: option.help)
            })
        })
    }

    private func optionValueRecords(
        _ option: OptionDefinition,
        prefix: String,
        attachedPrefix: String?,
        partialValues: [String] = [],
        scan: CommandScan,
        progresses: [FormProgress],
    ) -> [CompletionRecord] {
        let values: [(String, String)]
        switch option.valueKind {
        case .flag:
            return []
        case .value(_, let allowedValues) where !allowedValues.isEmpty:
            values = allowedValues.map({ ($0, "Allowed value.") })
        case .value:
            switch option.id {
            case .dependencies, .developmentDependencies:
                values = dependencyValues(prefix: prefix, progresses: progresses)
            case .inherits:
                values = inheritanceValues(scan: scan, progresses: progresses)
            case .inheritsUpstream:
                values = repositoryValues(progresses: progresses, value: { repository, _ in
                    try repository.upstreamVersions().map({ ($0, "Upstream version.") })
                })
            default:
                values = []
            }
        case .values:
            values = featureDiffValues(
                partialValues: partialValues,
                progresses: progresses,
            )
        }

        return values.compactMap({ value, description in
            let candidate = (attachedPrefix ?? "") + value
            let completePrefix = (attachedPrefix ?? "") + prefix
            guard candidate.hasPrefix(completePrefix) else {
                return nil
            }
            return .candidate(value: candidate, description: description)
        })
    }

    private func featureDiffValues(
        partialValues: [String],
        progresses: [FormProgress],
    ) -> [(String, String)] {
        switch partialValues.count {
        case 0:
            return repositoryValues(progresses: progresses, value: { repository, _ in
                try repository.upstreamVersions().map({ ($0, "Upstream version.") })
            })
        case 1:
            return repositoryValues(progresses: progresses, value: { repository, _ in
                try repository.patchsets(in: partialValues[0]).map({
                    ($0.patchsetVersion, "Patchset version.")
                })
            })
        case 2:
            guard let reference = try? PatchsetReference(
                upstreamVersion: partialValues[0],
                patchsetVersion: partialValues[1],
            ) else {
                return []
            }
            return repositoryValues(progresses: progresses, value: { repository, _ in
                try repository.resolve(reference).features.keys.map({
                    ($0, "Active feature.")
                })
            })
        default:
            return []
        }
    }

    private func dependencyValues(
        prefix: String,
        progresses: [FormProgress],
    ) -> [(String, String)] {
        let separator = prefix.lastIndex(of: ",")
        let head = separator.map({ String(prefix[...$0]) }) ?? ""
        let selected: Set<String>
        if let separator {
            selected = Set(
                prefix[..<separator]
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map(String.init),
            )
        }
        else {
            selected = []
        }
        let active = Set(
            repositoryValues(progresses: progresses, value: { repository, progress in
                guard let reference = reference(progress.values) else {
                    return []
                }
                return try repository.resolve(reference).features.keys.map({
                    ($0, "Active feature.")
                })
            }).map(\.0),
        )
        return active.subtracting(selected).map({ (head + $0, "Active feature.") })
    }

    private func inheritanceValues(
        scan: CommandScan,
        progresses: [FormProgress],
    ) -> [(String, String)] {
        repositoryValues(progresses: progresses, value: { repository, progress in
            if case .value(let selectedUpstream) = scan.options[.inheritsUpstream],
                !selectedUpstream.isEmpty
            {
                return try repository.patchsets(in: selectedUpstream).map({
                    ($0.patchsetVersion, "Patchset in \(selectedUpstream).")
                })
            }

            let currentVersion = progress.values[.version]
            var values = [(String, String)]()
            for version in try repository.upstreamVersions() {
                for patchset in try repository.patchsets(in: version) {
                    if version == currentVersion {
                        values.append((patchset.patchsetVersion, "Patchset in \(version)."))
                    }
                    else {
                        values.append((patchset.description, "Patchset in \(version)."))
                    }
                }
            }
            return values
        })
    }

    private func argumentRecords(
        _ argument: ArgumentDefinition,
        command: CommandDefinition,
        progress: FormProgress,
        prefix: String,
        allowsEphemeralToken: Bool,
    ) -> [CompletionRecord] {
        switch argument.valueKind {
        case .source:
            return isExplicitLocalPrefix(prefix) ? [.directories] : []
        case .target:
            var records = [CompletionRecord.directories]
            if allowsEphemeralToken,
                let ephemeral = argument.ephemeralTarget,
                ephemeral.token.hasPrefix(prefix)
            {
                records.append(.candidate(value: ephemeral.token, description: ephemeral.help))
            }
            return records
        case .scalar:
            break
        }

        switch argument.id {
        case .version:
            guard command.id != .initialize else {
                return []
            }
            return repositoryCandidates(
                progress: progress,
                prefix: prefix,
                values: { repository in
                    try repository.upstreamVersions().map({ ($0, "Upstream version.") })
                },
            )
        case .patchset:
            guard let version = progress.values[.version] else {
                return []
            }
            return repositoryCandidates(
                progress: progress,
                prefix: prefix,
                values: { repository in
                    try repository.patchsets(in: version).map({
                        ($0.patchsetVersion, "Patchset version.")
                    })
                },
            )
        case .feature:
            return featureRecords(command: command, progress: progress, prefix: prefix)
        case .id:
            return existingEphemeralRecords(prefix: prefix, attachedPrefix: nil)
        case .source, .target:
            return []
        }
    }

    private func featureRecords(
        command: CommandDefinition,
        progress: FormProgress,
        prefix: String,
    ) -> [CompletionRecord] {
        guard command.id != .add, let reference = reference(progress.values) else {
            return []
        }
        return repositoryCandidates(
            progress: progress,
            prefix: prefix,
            values: { repository in
                let manifest = try repository.manifest(for: reference)
                let direct = Set((manifest.features ?? []).map(\.id))
                let values: [String]
                let description: String
                switch command.id {
                case .remove:
                    values = Array(direct)
                    description = "Direct feature."
                case .exclude:
                    values = Array(Set(try repository.resolve(reference).features.keys).subtracting(direct))
                    description = "Active inherited feature."
                case .include:
                    values = manifest.excludes ?? []
                    description = "Excluded feature."
                case .expand:
                    values = Array(try repository.resolve(reference).features.keys)
                    description = "Active feature."
                default:
                    return []
                }
                return values.map({ ($0, description) })
            },
        )
    }

    private func ephemeralIDRecords(
        prefix: String,
        attachedPrefix: String?,
        command: CommandDefinition,
        progresses: [FormProgress],
    ) -> [CompletionRecord] {
        let selectsExisting = command.id == .collapse
            || progresses.contains(where: { $0.form.id == .recovery })
        guard selectsExisting else {
            return []
        }
        return existingEphemeralRecords(prefix: prefix, attachedPrefix: attachedPrefix)
    }

    private func existingEphemeralRecords(
        prefix: String,
        attachedPrefix: String?,
    ) -> [CompletionRecord] {
        guard let listings = try? EphemeralWorkspaceManager(paths: paths).list() else {
            return []
        }
        let completePrefix = (attachedPrefix ?? "") + prefix
        return listings.compactMap({ listing in
            let candidate = (attachedPrefix ?? "") + listing.id
            guard candidate.hasPrefix(completePrefix) else {
                return nil
            }
            return .candidate(value: candidate, description: "Ephemeral workspace.")
        })
    }

    private func repositoryCandidates(
        progress: FormProgress,
        prefix: String,
        values: (PatchsetRepository) throws -> [(String, String)],
    ) -> [CompletionRecord] {
        guard let repository = repository(progress.values),
            let candidates = try? values(repository)
        else {
            return []
        }
        return candidates.compactMap({ value, description in
            guard value.hasPrefix(prefix) else {
                return nil
            }
            return .candidate(value: value, description: description)
        })
    }

    private func repositoryValues(
        progresses: [FormProgress],
        value: (PatchsetRepository, FormProgress) throws -> [(String, String)],
    ) -> [(String, String)] {
        var results = [(String, String)]()
        for progress in progresses {
            guard let repository = repository(progress.values) else {
                continue
            }
            results += (try? value(repository, progress)) ?? []
        }
        return results
    }

    private func repository(_ values: [ArgumentID: String]) -> PatchsetRepository? {
        let sourceValue = values[.source]
        if let sourceValue,
            PatchsetSourceLocator.recognizesExplicitSource(sourceValue),
            !isExplicitLocalPrefix(sourceValue)
        {
            return nil
        }
        guard
            let source = try? PatchsetSourceLocator.locate(
                sourceValue,
                currentDirectoryURL: currentDirectoryURL,
            ),
            source.kind == .local,
            let rootURL = source.localRootURL,
            let repository = try? PatchsetRepository(rootURL: rootURL),
            (try? repository.rootManifest()) != nil
        else {
            return nil
        }
        return repository
    }

    private func reference(_ values: [ArgumentID: String]) -> PatchsetReference? {
        guard let version = values[.version], let patchset = values[.patchset] else {
            return nil
        }
        return try? .init(upstreamVersion: version, patchsetVersion: patchset)
    }

    private func rootOption(
        matching token: String,
    ) -> (definition: OptionDefinition, attachedValue: String?)? {
        option(
            matching: token,
            longOptions: Dictionary(
                CommandCatalog.rootOptions.map({ ($0.longName, $0) }),
                uniquingKeysWith: { first, _ in first },
            ),
            shortOptions: Dictionary(
                CommandCatalog.rootOptions.compactMap({ option in
                    option.shortName.map({ ($0, option) })
                }),
                uniquingKeysWith: { first, _ in first },
            ),
        )
    }

    private func attachedRootOption(
        in token: String,
    ) -> (definition: OptionDefinition, value: String)? {
        attachedOption(in: token, definitions: CommandCatalog.rootOptions)
    }

    private func attachedOption(
        in token: String,
        command: CommandDefinition,
    ) -> (definition: OptionDefinition, value: String)? {
        attachedOption(
            in: token,
            definitions: command.options + CommandCatalog.globalCommandOptions,
        )
    }

    private func attachedOption(
        in token: String,
        definitions: [OptionDefinition],
    ) -> (definition: OptionDefinition, value: String)? {
        guard token.hasPrefix("--"), let separator = token.firstIndex(of: "=") else {
            return nil
        }
        let name = String(token[token.index(token.startIndex, offsetBy: 2)..<separator])
        guard
            let definition = definitions.first(where: { $0.longName == name }),
            case .value = definition.valueKind
        else {
            return nil
        }
        return (definition, String(token[token.index(after: separator)...]))
    }

    private func option(
        matching token: String,
        longOptions: [String: OptionDefinition],
        shortOptions: [Character: OptionDefinition],
    ) -> (definition: OptionDefinition, attachedValue: String?)? {
        if token.hasPrefix("--") {
            let pieces = token.dropFirst(2).split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false,
            )
            guard let definition = longOptions[String(pieces[0])] else {
                return nil
            }
            return (definition, pieces.count == 2 ? String(pieces[1]) : nil)
        }
        guard token.count == 2,
            let name = token.last,
            let definition = shortOptions[name]
        else {
            return nil
        }
        return (definition, nil)
    }

    private func isExplicitLocalPrefix(_ value: String) -> Bool {
        value == "." || value == "~" || value.contains("/")
    }

    private func normalized(_ records: [CompletionRecord]) -> [CompletionRecord] {
        var candidates = [String: CompletionRecord]()
        var includesDirectories = false
        for record in records {
            switch record {
            case .candidate(let value, _):
                candidates[value] = candidates[value] ?? record
            case .directories:
                includesDirectories = true
            }
        }
        var result = candidates.keys.sorted().compactMap({ candidates[$0] })
        if includesDirectories {
            result.append(.directories)
        }
        return result
    }
}

private extension CompletionRecord {

    var value: String? {
        guard case .candidate(let value, _) = self else {
            return nil
        }
        return value
    }
}
