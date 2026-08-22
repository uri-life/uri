public import Foundation

public struct GitRepository: Sendable {

    public let rootURL: URL

    private let process: GitProcess

    internal init(
        rootURL: URL,
        process: GitProcess,
    ) {
        self.rootURL = rootURL
        self.process = process
    }

    /// Reports tracked and untracked worktree changes separately.
    public func status() async throws -> GitStatus {
        let tracked = try await run([
            "status",
            "--porcelain",
            "--untracked-files=no",
        ])
        let untracked = try await run([
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
        ])
        return .init(
            hasTrackedChanges: !tracked.standardOutput.isEmpty,
            hasUntrackedFiles: !untracked.standardOutput.isEmpty,
        )
    }

    /// Returns the repository-local or inherited Git user identity.
    public func configuredIdentity() async throws -> GitIdentity {
        let name = try await optionalConfigurationValue(for: "user.name") ?? ""
        let email = try await optionalConfigurationValue(for: "user.email") ?? ""
        return try .init(name: name, email: email)
    }

    /// Returns the checked-out local branch, or `nil` for detached HEAD.
    public func currentBranch() async throws -> String? {
        let result = try await rawRun([
            "symbolic-ref",
            "--quiet",
            "--short",
            "HEAD",
        ])
        switch result.output.exitStatus {
        case 0:
            return try string(
                from: result.output.standardOutput,
                operation: "read current branch",
            )
        case 1:
            return nil
        default:
            throw commandFailure(result)
        }
    }

    public func currentCommit() async throws -> GitCommit {
        let output = try await run([
            "rev-parse",
            "--verify",
            "HEAD^{commit}",
        ])
        let value = try string(from: output.standardOutput, operation: "read current commit")
        return try .init(rawValue: value)
    }

    public func branchExists(_ name: String) async throws -> Bool {
        try await validateBranchName(name)
        let result = try await rawRun([
            "show-ref",
            "--verify",
            "--quiet",
            "refs/heads/\(name)",
        ])
        switch result.output.exitStatus {
        case 0:
            return true
        case 1:
            return false
        default:
            throw commandFailure(result)
        }
    }

    public func remoteURL(named name: String = "origin") async throws -> String {
        try validateToken(name)
        let result = try await rawRun([
            "remote",
            "get-url",
            name,
        ])
        guard result.output.exitStatus == 0 else {
            throw GitError.missingRemote(name: name, repositoryURL: rootURL)
        }
        return try string(from: result.output.standardOutput, operation: "read remote URL")
    }

    public func validateRemote(
        named name: String = "origin",
        matches expectedURL: String,
        relativeTo baseURL: URL,
    ) async throws {
        let actualURL = try await remoteURL(named: name)
        let expected = try GitRemoteIdentity(expectedURL, relativeTo: baseURL)
        let actual = try GitRemoteIdentity(actualURL, relativeTo: baseURL)
        guard expected == actual else {
            throw GitError.remoteMismatch(
                name: name,
                expected: expected,
                actual: actual,
            )
        }
    }

    public func checkoutTag(_ name: String) async throws {
        try await validateTagName(name)
        _ = try await run([
            "checkout",
            "--detach",
            "refs/tags/\(name)",
        ])
    }

    public func checkoutDetached(at reference: GitReference) async throws {
        _ = try await run([
            "checkout",
            "--detach",
            "--force",
            reference.rawValue,
        ])
    }

    public func checkoutResetBranch(
        _ name: String,
        at reference: GitReference,
    ) async throws {
        try await validateBranchName(name)
        _ = try await run([
            "checkout",
            "-B",
            name,
            reference.rawValue,
        ])
    }

    public func createBranch(
        _ name: String,
        at reference: GitReference = .head,
    ) async throws {
        try await validateBranchName(name)
        _ = try await run([
            "branch",
            "--",
            name,
            reference.rawValue,
        ])
    }

    public func createAndCheckoutBranch(
        _ name: String,
        at reference: GitReference = .head,
    ) async throws {
        try await validateBranchName(name)
        _ = try await run([
            "checkout",
            "-b",
            name,
            reference.rawValue,
        ])
    }

    public func checkoutBranch(_ name: String) async throws {
        try await validateBranchName(name)
        _ = try await run([
            "checkout",
            name,
        ])
    }

    public func detachHead() async throws {
        _ = try await run([
            "checkout",
            "--detach",
            "HEAD",
        ])
    }

    public func deleteBranch(
        _ name: String,
        force: Bool,
    ) async throws {
        try await validateBranchName(name)
        _ = try await run([
            "branch",
            force ? "-D" : "-d",
            "--",
            name,
        ])
    }

    public func fetch(_ scope: GitFetchScope) async throws {
        switch scope {
        case .allRemotesAndTags:
            _ = try await run([
                "fetch",
                "--all",
                "--tags",
            ])
        case .tags:
            _ = try await run([
                "fetch",
                "--tags",
            ])
        }
    }

    public func fetchTag(
        _ name: String,
        depth: Int? = nil,
    ) async throws {
        try await validateTagName(name)
        var arguments = [
            "fetch",
            "--no-tags",
        ]
        if let depth {
            guard depth > 0 else {
                throw GitError.invalidReference(String(depth))
            }
            arguments += ["--depth", String(depth)]
        }
        arguments += [
            "origin",
            "refs/tags/\(name):refs/tags/\(name)",
        ]
        _ = try await run(arguments)
    }

    public func gitPath(_ component: String) async throws -> URL {
        try validateToken(component)
        let output = try await run([
            "rev-parse",
            "--git-path",
            component,
        ])
        let path = try string(from: output.standardOutput, operation: "resolve Git path")
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return rootURL.appending(path: path).standardizedFileURL
    }

    public func commit(at reference: GitReference) async throws -> GitCommit {
        let output = try await run([
            "rev-parse",
            "--verify",
            "\(reference.rawValue)^{commit}",
        ])
        return try .init(
            rawValue: string(from: output.standardOutput, operation: "resolve Git reference"),
        )
    }

    public func referenceExists(_ reference: GitReference) async throws -> Bool {
        let result = try await rawRun([
            "rev-parse",
            "--verify",
            "--quiet",
            "\(reference.rawValue)^{commit}",
        ])
        switch result.output.exitStatus {
        case 0:
            return true
        case 1:
            return false
        default:
            throw commandFailure(result)
        }
    }

    public func mergeBase(
        _ first: GitReference,
        _ second: GitReference,
    ) async throws -> GitCommit {
        let output = try await run([
            "merge-base",
            first.rawValue,
            second.rawValue,
        ])
        return try .init(
            rawValue: string(from: output.standardOutput, operation: "find merge base"),
        )
    }

    public func rebase(
        branch: String,
        fromExclusive upstream: GitReference,
        onto destination: GitReference,
        committer: GitIdentity,
    ) async throws {
        try await validateBranchName(branch)
        _ = try await run(
            [
                "rebase",
                "--onto",
                destination.rawValue,
                upstream.rawValue,
                branch,
            ],
            environment: committerEnvironment(committer),
        )
    }

    public func abortRebase() async throws {
        _ = try await run(["rebase", "--abort"])
    }

    public func hardReset(to reference: GitReference) async throws {
        _ = try await run([
            "reset",
            "--hard",
            reference.rawValue,
        ])
    }

    public func cleanUntrackedFiles() async throws {
        _ = try await run(["clean", "-df"])
    }

    public func configureIdentity(_ identity: GitIdentity) async throws {
        _ = try await run(["config", "user.name", identity.name])
        _ = try await run(["config", "user.email", identity.email])
        _ = try await run(["config", "commit.gpgSign", "false"])
    }

    public func commitCount(
        fromExclusive base: GitReference,
        through head: GitReference,
    ) async throws -> Int {
        let output = try await run([
            "rev-list",
            "--count",
            "\(base.rawValue)..\(head.rawValue)",
        ])
        let value = try string(from: output.standardOutput, operation: "count commits")
        guard let count = Int(value) else {
            throw GitError.malformedOutput(
                operation: "count commits",
                output: output.standardOutput,
            )
        }
        return count
    }

    public func isAncestor(
        _ ancestor: GitReference,
        of descendant: GitReference,
    ) async throws -> Bool {
        let result = try await rawRun([
            "merge-base",
            "--is-ancestor",
            ancestor.rawValue,
            descendant.rawValue,
        ])
        switch result.output.exitStatus {
        case 0:
            return true
        case 1:
            return false
        default:
            throw commandFailure(result)
        }
    }

    public func hasDiff(
        between first: GitReference,
        and second: GitReference,
    ) async throws -> Bool {
        let result = try await rawRun([
            "diff",
            "--quiet",
            first.rawValue,
            second.rawValue,
            "--",
        ])
        switch result.output.exitStatus {
        case 0:
            return false
        case 1:
            return true
        default:
            throw commandFailure(result)
        }
    }

    /// Returns the binary-capable tree diff between two references.
    public func diff(
        from first: GitReference,
        to second: GitReference,
    ) async throws -> Data {
        try await run([
            "diff",
            "--binary",
            "--no-ext-diff",
            "--no-textconv",
            "--no-renames",
            "--unified=3",
            first.rawValue,
            second.rawValue,
            "--",
        ]).standardOutput
    }

    public func applyMailboxPatch(
        at patchURL: URL,
        committer: GitIdentity,
    ) async throws -> GitApplyResult {
        try requireRegularFile(at: patchURL)
        let result = try await rawRun(
            [
                "am",
                "--3way",
                "--no-gpg-sign",
            ],
            input: .file(patchURL),
            environment: committerEnvironment(committer),
        )
        if result.output.exitStatus == 0 {
            return .applied
        }
        if try await isMailboxApplyInProgress() {
            return .conflicted
        }
        throw commandFailure(result)
    }

    public func continueMailboxApply(committer: GitIdentity) async throws {
        _ = try await run(
            [
                "am",
                "--continue",
                "--no-gpg-sign",
            ],
            environment: committerEnvironment(committer),
        )
    }

    public func abortMailboxApply(committer: GitIdentity? = nil) async throws {
        _ = try await run(
            [
                "am",
                "--abort",
            ],
            environment: committer.map(committerEnvironment) ?? [:],
        )
    }

    public func isMailboxApplyInProgress() async throws -> Bool {
        let output = try await run([
            "rev-parse",
            "--git-path",
            "rebase-apply",
        ])
        let path = try string(
            from: output.standardOutput,
            operation: "locate mailbox apply state",
        )
        let stateURL = path.hasPrefix("/")
            ? URL(filePath: path)
            : rootURL.appending(path: path)
        return (try? stateURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Applies a resolution patch and stages only unresolved and patch-affected paths.
    @discardableResult
    public func applyResolutionPatch(at patchURL: URL) async throws -> [String] {
        try requireRegularFile(at: patchURL)
        let unresolvedOutput = try await run([
            "diff",
            "--name-only",
            "-z",
            "--diff-filter=U",
        ])
        let affectedOutput = try await run([
            "apply",
            "--numstat",
            "-z",
            "--",
            patchURL.path,
        ])
        var paths = try nulSeparatedPaths(
            in: unresolvedOutput.standardOutput,
            operation: "read unresolved paths",
        )
        paths.formUnion(
            try numstatPaths(
                in: affectedOutput.standardOutput,
                operation: "read resolution patch paths",
            ),
        )

        _ = try await run([
            "apply",
            "--whitespace=nowarn",
            "--",
            patchURL.path,
        ])

        let sortedPaths = paths.sorted()
        for path in sortedPaths {
            _ = try await run([
                "add",
                "--all",
                "--",
                path,
            ])
        }
        return sortedPaths
    }

    public func writeFormatPatch(
        fromExclusive base: GitReference,
        through head: GitReference,
        to outputURL: URL,
    ) async throws {
        let output = try await run([
            "format-patch",
            "--binary",
            "--no-signature",
            "--no-stat",
            "--stdout",
            "\(base.rawValue)..\(head.rawValue)",
        ])
        let normalized = try normalizedFormatPatch(output.standardOutput)
        do {
            try normalized.write(to: outputURL, options: .atomic)
        }
        catch {
            throw GitError.fileSystem(
                operation: "write format patch to",
                url: outputURL,
                reason: String(describing: error),
            )
        }
    }

    private func run(
        _ arguments: [String],
        input: GitStandardInput? = nil,
        environment: [String: String] = [:],
    ) async throws -> GitCommandOutput {
        let result = try await rawRun(
            arguments,
            input: input,
            environment: environment,
        )
        guard result.output.exitStatus == 0 else {
            throw commandFailure(result)
        }
        return result.output
    }

    private func rawRun(
        _ arguments: [String],
        input: GitStandardInput? = nil,
        environment: [String: String] = [:],
    ) async throws -> (arguments: [String], output: GitCommandOutput) {
        let completeArguments = [
            "-C",
            rootURL.path,
        ] + arguments
        let output = try await process.run(
            arguments: completeArguments,
            input: input,
            environment: environment,
        )
        return (completeArguments, output)
    }

    private func commandFailure(
        _ result: (arguments: [String], output: GitCommandOutput),
    ) -> GitError {
        .commandFailed(
            arguments: result.arguments,
            exitStatus: result.output.exitStatus,
            standardOutput: result.output.standardOutput,
            standardError: result.output.standardError,
        )
    }

    private func string(
        from data: Data,
        operation: String,
    ) throws -> String {
        guard var value = String(data: data, encoding: .utf8) else {
            throw GitError.malformedOutput(operation: operation, output: data)
        }
        while value.last == "\n" || value.last == "\r" {
            value.removeLast()
        }
        return value
    }

    private func optionalConfigurationValue(for key: String) async throws -> String? {
        let result = try await rawRun([
            "config",
            "--get",
            key,
        ])
        switch result.output.exitStatus {
        case 0:
            return try string(
                from: result.output.standardOutput,
                operation: "read Git configuration \(key)",
            )
        case 1:
            return nil
        default:
            throw commandFailure(result)
        }
    }

    private func validateBranchName(_ name: String) async throws {
        try validateToken(name)
        let result = try await rawRun([
            "check-ref-format",
            "--branch",
            name,
        ])
        guard result.output.exitStatus == 0 else {
            throw GitError.invalidReference(name)
        }
    }

    private func validateTagName(_ name: String) async throws {
        try validateToken(name)
        let result = try await rawRun([
            "check-ref-format",
            "refs/tags/\(name)",
        ])
        guard result.output.exitStatus == 0 else {
            throw GitError.invalidReference(name)
        }
    }

    private func validateToken(_ value: String) throws {
        guard
            !value.isEmpty,
            !value.hasPrefix("-"),
            !value.contains("\0"),
            !value.contains(where: { $0.isNewline })
        else {
            throw GitError.invalidReference(value)
        }
    }

    private func requireRegularFile(at url: URL) throws {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw GitError.fileSystem(
                operation: "read patch at",
                url: url,
                reason: "The patch is not a regular file.",
            )
        }
    }

    private func committerEnvironment(_ committer: GitIdentity) -> [String: String] {
        [
            "GIT_COMMITTER_EMAIL": committer.email,
            "GIT_COMMITTER_NAME": committer.name,
        ]
    }

    private func nulSeparatedPaths(
        in data: Data,
        operation: String,
    ) throws -> Set<String> {
        var paths = Set<String>()
        for field in data.split(separator: 0, omittingEmptySubsequences: true) {
            guard let path = String(data: Data(field), encoding: .utf8) else {
                throw GitError.malformedOutput(operation: operation, output: data)
            }
            paths.insert(path)
        }
        return paths
    }

    private func numstatPaths(
        in data: Data,
        operation: String,
    ) throws -> Set<String> {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var paths = Set<String>()
        var index = 0
        while index < fields.count {
            let field = fields[index]
            if field.isEmpty {
                index += 1
                continue
            }
            guard let record = String(data: Data(field), encoding: .utf8) else {
                throw GitError.malformedOutput(operation: operation, output: data)
            }
            let columns = record.split(
                separator: "\t",
                maxSplits: 2,
                omittingEmptySubsequences: false,
            )
            guard columns.count == 3 else {
                throw GitError.malformedOutput(operation: operation, output: data)
            }

            if !columns[2].isEmpty {
                paths.insert(String(columns[2]))
            }
            else {
                guard index + 2 < fields.count else {
                    throw GitError.malformedOutput(operation: operation, output: data)
                }
                for renamedField in fields[(index + 1)...(index + 2)] {
                    guard let path = String(data: Data(renamedField), encoding: .utf8) else {
                        throw GitError.malformedOutput(operation: operation, output: data)
                    }
                    paths.insert(path)
                }
                index += 2
            }
            index += 1
        }
        return paths
    }

    private func normalizedFormatPatch(_ data: Data) throws -> Data {
        guard !data.isEmpty else {
            return data
        }

        let prefix = Array("From ".utf8)
        let suffix = Array(" Mon Sep 17 00:00:00 2001".utf8)
        var bytes = Array(data)
        var lineStart = 0
        var normalizedHeaders = 0

        while lineStart < bytes.count {
            let newline = bytes[lineStart...].firstIndex(of: 10) ?? bytes.endIndex
            let lineEnd = newline > lineStart && bytes[newline - 1] == 13 ? newline - 1 : newline
            let lineLength = lineEnd - lineStart
            if lineLength > prefix.count + suffix.count {
                let prefixEnd = lineStart + prefix.count
                let suffixStart = lineEnd - suffix.count
                if
                    Array(bytes[lineStart..<prefixEnd]) == prefix,
                    Array(bytes[suffixStart..<lineEnd]) == suffix,
                    bytes[prefixEnd..<suffixStart].allSatisfy({ byte in
                        (48...57).contains(byte)
                            || (65...70).contains(byte)
                            || (97...102).contains(byte)
                    })
                {
                    for index in prefixEnd..<suffixStart {
                        bytes[index] = 48
                    }
                    normalizedHeaders += 1
                }
            }
            lineStart = newline == bytes.endIndex ? bytes.endIndex : newline + 1
        }

        guard normalizedHeaders > 0 else {
            throw GitError.malformedOutput(operation: "normalize format patch", output: data)
        }
        return Data(bytes)
    }
}
