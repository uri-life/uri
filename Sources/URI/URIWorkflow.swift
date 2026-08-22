public import Foundation
public import URIGit
import URIModel
public import URIPatchset

public enum EphemeralRequest: Equatable, Hashable, Sendable {

    case none

    case automatic

    case named(String)
}

public struct WorkflowResult: Equatable, Hashable, Sendable {

    public let targetURL: URL

    public let ephemeralID: String?

    public let branch: String?

    public init(targetURL: URL, ephemeralID: String?, branch: String?) {
        self.targetURL = targetURL
        self.ephemeralID = ephemeralID
        self.branch = branch
    }
}

public struct URIWorkflow {

    private struct PreparedTarget {

        let repository: GitRepository

        let workspace: EphemeralWorkspace?
    }

    private let git: Git

    private let paths: RuntimePaths

    private let sourceResolver: PatchsetSourceResolver

    private let ephemeralManager: EphemeralWorkspaceManager

    private let stateStore: OperationStateStore

    private let operationIndex: OperationIndex

    public init(
        git: Git = .init(),
        paths: RuntimePaths = .init(),
    ) {
        self.git = git
        self.paths = paths
        self.sourceResolver = .init(git: git, paths: paths)
        self.ephemeralManager = .init(paths: paths, git: git)
        self.stateStore = .init()
        self.operationIndex = .init(paths: paths, git: git)
    }

    public func expand(
        source: PatchsetSource,
        reference: PatchsetReference,
        featureID: String,
        targetURL: URL?,
        currentDirectoryURL: URL,
        ephemeral: EphemeralRequest,
        includeDevelopmentDependencies: Bool,
        force: Bool,
    ) async throws -> WorkflowResult {
        let resolvedSource = try await sourceResolver.resolve(
            source,
            reference: reference,
            includePatches: true,
        )
        var preparedTarget: PreparedTarget?
        do {
            let manifest = try resolvedSource.repository.rootManifest()
            let target = try await prepareTarget(
                requestedURL: targetURL,
                currentDirectoryURL: currentDirectoryURL,
                ephemeral: ephemeral,
                upstream: manifest.upstream,
                version: reference.upstreamVersion,
                sourceBaseURL: resolvedSource.repository.rootURL,
            )
            preparedTarget = target
            let resolved = try resolvedSource.repository.resolve(reference)
            let order = try resolved.dependencyOrder(
                for: featureID,
                in: includeDevelopmentDependencies ? .includingDevelopment : .regular,
            )
            let result = try await begin(
                mode: .expand,
                source: resolvedSource,
                rootManifest: manifest,
                reference: reference,
                selectedFeature: featureID,
                features: order.map(\.id),
                target: target,
                force: force,
            )
            return result
        }
        catch {
            let stateExists = (try? await hasOperationState(preparedTarget)) ?? false
            if !stateExists {
                if let preparedTarget {
                    try? operationIndex.remove(for: preparedTarget.repository)
                }
                try? sourceResolver.removeSnapshot(at: resolvedSource.snapshotURL)
                if let workspace = preparedTarget?.workspace {
                    try? ephemeralManager.removeUninitialized(workspace)
                }
            }
            throw error
        }
    }

    public func apply(
        source: PatchsetSource,
        reference: PatchsetReference,
        targetURL: URL?,
        currentDirectoryURL: URL,
        ephemeral: EphemeralRequest,
        includeDevelopmentDependencies: Bool = false,
    ) async throws -> WorkflowResult {
        let resolvedSource = try await sourceResolver.resolve(
            source,
            reference: reference,
            includePatches: true,
        )
        var preparedTarget: PreparedTarget?
        do {
            let manifest = try resolvedSource.repository.rootManifest()
            let target = try await prepareTarget(
                requestedURL: targetURL,
                currentDirectoryURL: currentDirectoryURL,
                ephemeral: ephemeral,
                upstream: manifest.upstream,
                version: reference.upstreamVersion,
                sourceBaseURL: resolvedSource.repository.rootURL,
            )
            preparedTarget = target
            let resolved = try resolvedSource.repository.resolve(reference)
            let order =
                try includeDevelopmentDependencies
                ? resolved.orderedFeatures(in: .includingDevelopment)
                : resolved.applicationOrder()
            let result = try await begin(
                mode: .apply,
                source: resolvedSource,
                rootManifest: manifest,
                reference: reference,
                selectedFeature: nil,
                features: order.map(\.id),
                target: target,
                force: false,
            )
            return result
        }
        catch {
            let stateExists = (try? await hasOperationState(preparedTarget)) ?? false
            if !stateExists {
                if let preparedTarget {
                    try? operationIndex.remove(for: preparedTarget.repository)
                }
                try? sourceResolver.removeSnapshot(at: resolvedSource.snapshotURL)
                if let workspace = preparedTarget?.workspace {
                    try? ephemeralManager.removeUninitialized(workspace)
                }
            }
            throw error
        }
    }

    public func `continue`(
        mode expectedMode: OperationState.Mode,
        targetURL: URL?,
        currentDirectoryURL: URL,
        ephemeralID: String?,
    ) async throws -> WorkflowResult {
        let target = try await existingTarget(
            requestedURL: targetURL,
            currentDirectoryURL: currentDirectoryURL,
            ephemeralID: ephemeralID,
        )
        let stateURL = try await stateStore.stateURL(
            for: target.repository,
            ephemeralID: target.workspace?.id,
            paths: paths,
        )
        var state = try stateStore.load(from: stateURL)
        try validate(state: state, expectedMode: expectedMode, target: target)
        guard state.phase != .active else {
            throw URIError.operationNotFound("The saved \(state.mode.rawValue) operation is already complete.")
        }
        try operationIndex.register(state, for: target.repository)
        let patchset = try resolvedRepository(from: state)
        let reference = try PatchsetReference(
            upstreamVersion: state.upstreamVersion,
            patchsetVersion: state.patchsetVersion,
        )
        let committer = try GitIdentity(name: state.committerName, email: state.committerEmail)

        if try await target.repository.isMailboxApplyInProgress() {
            try await target.repository.continueMailboxApply(committer: committer)
        }

        let resume: (index: Int, phase: OperationState.Phase)
        switch state.phase {
        case .ante:
            resume = (state.currentIndex, .main)
        case .main:
            resume = (state.currentIndex, .post)
        case .post:
            resume = (state.currentIndex + 1, .ante)
        case .active:
            fatalError("Handled above")
        }
        state.currentIndex = resume.index
        state.phase = resume.phase
        try stateStore.save(state, to: stateURL)
        return try await applyRemaining(
            state: &state,
            stateURL: stateURL,
            sourceRepository: patchset,
            reference: reference,
            target: target,
            startingIndex: resume.index,
            startingPhase: resume.phase,
        )
    }

    public func abort(
        mode expectedMode: OperationState.Mode,
        targetURL: URL?,
        currentDirectoryURL: URL,
        ephemeralID: String?,
    ) async throws -> WorkflowResult {
        let target = try await existingTarget(
            requestedURL: targetURL,
            currentDirectoryURL: currentDirectoryURL,
            ephemeralID: ephemeralID,
        )
        let stateURL = try await stateStore.stateURL(
            for: target.repository,
            ephemeralID: target.workspace?.id,
            paths: paths,
        )
        let state = try stateStore.load(from: stateURL)
        try validate(state: state, expectedMode: expectedMode, target: target)
        try operationIndex.register(state, for: target.repository)
        let committer = try GitIdentity(name: state.committerName, email: state.committerEmail)

        if try await target.repository.isMailboxApplyInProgress() {
            try await target.repository.abortMailboxApply(committer: committer)
        }
        try await restoreStart(of: state, in: target.repository)
        try await deleteOperationBranches(state: state, repository: target.repository)

        if let workspace = target.workspace {
            try await ephemeralManager.vanish(id: workspace.id, force: true)
        }
        else {
            try stateStore.remove(at: stateURL)
            try? operationIndex.remove(for: target.repository)
            try sourceResolver.removeSnapshot(at: state.snapshotPath.map({ URL(filePath: $0) }))
        }
        return .init(
            targetURL: target.repository.rootURL,
            ephemeralID: target.workspace?.id,
            branch: state.startBranch,
        )
    }

    public func collapse(
        targetURL: URL?,
        currentDirectoryURL: URL,
        ephemeralID: String?,
        recursive: Bool,
        discard: Bool,
    ) async throws -> WorkflowResult {
        guard !(recursive && discard) else {
            throw URIError.invalidArguments("--recursive and --discard cannot be used together.")
        }
        let target = try await existingTarget(
            requestedURL: targetURL,
            currentDirectoryURL: currentDirectoryURL,
            ephemeralID: ephemeralID,
        )
        let stateURL = try await stateStore.stateURL(
            for: target.repository,
            ephemeralID: target.workspace?.id,
            paths: paths,
        )
        var state = try stateStore.load(from: stateURL)
        try validate(state: state, expectedMode: .expand, target: target)
        guard state.phase == .active else {
            throw URIError.invalidState(
                "The expansion has an unresolved conflict; use expand --continue or --abort first.",
            )
        }
        try operationIndex.register(state, for: target.repository)
        let status = try await target.repository.status()
        guard status.isCompletelyClean else {
            throw URIError.dirtyTarget(
                "TARGET has tracked or untracked changes. Commit the feature work before collapse.",
            )
        }

        if state.source.isRemote && !discard {
            throw URIError.remoteSourceIsReadOnly(
                "An expansion from a remote SOURCE can only be closed with collapse --discard.",
            )
        }

        if !discard {
            try await reconstructAndSave(
                state: state,
                target: target.repository,
                recursive: recursive,
            )
        }

        try await cleanupExpandedBranches(state: state, repository: target.repository)
        state.expectedCommit = try await target.repository.currentCommit().rawValue
        try stateStore.save(state, to: stateURL)

        if let workspace = target.workspace {
            try await ephemeralManager.vanish(id: workspace.id, force: true)
        }
        else {
            try stateStore.remove(at: stateURL)
            try? operationIndex.remove(for: target.repository)
            try sourceResolver.removeSnapshot(at: state.snapshotPath.map({ URL(filePath: $0) }))
        }
        return .init(
            targetURL: target.repository.rootURL,
            ephemeralID: target.workspace?.id,
            branch: nil,
        )
    }

    private func begin(
        mode: OperationState.Mode,
        source: ResolvedPatchsetSource,
        rootManifest: RootManifest,
        reference: PatchsetReference,
        selectedFeature: String?,
        features: [String],
        target: PreparedTarget,
        force: Bool,
    ) async throws -> WorkflowResult {
        let repository = target.repository
        let stateURL = try await stateStore.stateURL(
            for: repository,
            ephemeralID: target.workspace?.id,
            paths: paths,
        )
        if try stateStore.loadIfPresent(from: stateURL) != nil {
            throw URIError.operationAlreadyExists(
                "A URI operation already exists for TARGET: \(repository.rootURL.path)",
            )
        }
        let status = try await repository.status()
        guard status.isCompletelyClean else {
            throw URIError.dirtyTarget(
                "TARGET must have no tracked or untracked changes: \(repository.rootURL.path)",
            )
        }
        try await repository.validateRemote(
            matches: rootManifest.upstream,
            relativeTo: source.repository.rootURL,
        )
        if target.workspace == nil {
            try operationIndex.register(for: repository)
        }

        let startCommit = try await repository.currentCommit()
        let startBranch = try await repository.currentBranch()
        let branchPrefix = rootManifest.branchPrefix ?? RootManifest.legacyBranchPrefix
        let committer = try await committer(from: rootManifest, target: repository)

        if mode == .expand {
            let versionBranch = patchsetBranchName(prefix: branchPrefix, reference: reference)
            if try await repository.branchExists(versionBranch) {
                guard force else {
                    throw URIError.invalidArguments(
                        "Branch \(versionBranch) already exists; use --force to replace it.",
                    )
                }
                if try await repository.currentBranch() == versionBranch {
                    try await repository.detachHead()
                }
                try await repository.deleteBranch(versionBranch, force: true)
            }
            for feature in features {
                let branch = featureBranchName(
                    prefix: branchPrefix,
                    reference: reference,
                    featureID: feature,
                )
                if try await repository.branchExists(branch) {
                    throw URIError.invalidArguments(
                        "Branch \(branch) already exists; collapse or remove the earlier expansion first.",
                    )
                }
            }
        }

        if target.workspace == nil {
            try await repository.fetchTag(reference.upstreamVersion)
        }
        let tagReference = try GitReference(
            rawValue: "refs/tags/\(reference.upstreamVersion)",
        )
        let baselineCommit = try await repository.commit(at: tagReference)

        var state = OperationState(
            mode: mode,
            source: source.source,
            snapshotPath: source.snapshotURL?.path,
            upstreamVersion: reference.upstreamVersion,
            patchsetVersion: reference.patchsetVersion,
            feature: selectedFeature,
            featureOrder: features,
            targetPath: repository.rootURL.path,
            startCommit: startCommit.rawValue,
            startBranch: startBranch,
            baselineCommit: baselineCommit.rawValue,
            expectedCommit: baselineCommit.rawValue,
            branchPrefix: branchPrefix,
            committerName: committer.name,
            committerEmail: committer.email,
            ephemeralID: target.workspace?.id,
        )
        try stateStore.save(state, to: stateURL)
        try await repository.checkoutTag(reference.upstreamVersion)

        return try await applyRemaining(
            state: &state,
            stateURL: stateURL,
            sourceRepository: source.repository,
            reference: reference,
            target: target,
            startingIndex: 0,
            startingPhase: .ante,
        )
    }

    private func applyRemaining(
        state: inout OperationState,
        stateURL: URL,
        sourceRepository: PatchsetRepository,
        reference: PatchsetReference,
        target: PreparedTarget,
        startingIndex: Int,
        startingPhase: OperationState.Phase,
    ) async throws -> WorkflowResult {
        let committer = try GitIdentity(name: state.committerName, email: state.committerEmail)
        if startingIndex < state.featureOrder.count {
            for index in startingIndex..<state.featureOrder.count {
                let featureID = state.featureOrder[index]
                var phase: OperationState.Phase = index == startingIndex ? startingPhase : .ante

                if phase == .ante {
                    try await apply(
                        patch: sourceRepository.antePatch(
                            for: featureID,
                            inheritedBy: reference,
                        ),
                        sourceRepository: sourceRepository,
                        reference: reference,
                        phase: .ante,
                        featureID: featureID,
                        index: index,
                        state: &state,
                        stateURL: stateURL,
                        repository: target.repository,
                        committer: committer,
                    )
                    phase = .main
                }
                if phase == .main {
                    try await applyMainPatch(
                        sourceRepository.patch(for: featureID, inheritedBy: reference),
                        featureID: featureID,
                        index: index,
                        reference: reference,
                        sourceRepository: sourceRepository,
                        state: &state,
                        stateURL: stateURL,
                        repository: target.repository,
                        committer: committer,
                    )
                    phase = .post
                }
                if phase == .post {
                    try await apply(
                        patch: sourceRepository.postPatch(
                            for: featureID,
                            inheritedBy: reference,
                        ),
                        sourceRepository: sourceRepository,
                        reference: reference,
                        phase: .post,
                        featureID: featureID,
                        index: index,
                        state: &state,
                        stateURL: stateURL,
                        repository: target.repository,
                        committer: committer,
                    )
                }

                if state.mode == .expand {
                    let branch = featureBranchName(
                        prefix: state.branchPrefix,
                        reference: reference,
                        featureID: featureID,
                    )
                    if try await target.repository.branchExists(branch) {
                        try await target.repository.deleteBranch(branch, force: true)
                    }
                    try await target.repository.createBranch(branch)
                }
            }
        }

        let branch: String?
        if state.mode == .expand {
            if let last = state.featureOrder.last {
                let lastBranch = featureBranchName(
                    prefix: state.branchPrefix,
                    reference: reference,
                    featureID: last,
                )
                try await target.repository.checkoutBranch(lastBranch)
                branch = lastBranch
            }
            else {
                branch = nil
            }
        }
        else {
            let finalBranch = patchsetBranchName(prefix: state.branchPrefix, reference: reference)
            if try await target.repository.branchExists(finalBranch) {
                if try await target.repository.currentBranch() == finalBranch {
                    try await target.repository.detachHead()
                }
                try await target.repository.deleteBranch(finalBranch, force: true)
            }
            try await target.repository.createAndCheckoutBranch(finalBranch)
            branch = finalBranch
        }

        state.phase = .active
        state.currentIndex = state.featureOrder.count
        state.expectedCommit = try await target.repository.currentCommit().rawValue
        if state.mode == .expand || target.workspace != nil {
            try stateStore.save(state, to: stateURL)
        }
        else {
            try stateStore.remove(at: stateURL)
            try? operationIndex.remove(for: target.repository)
            try sourceResolver.removeSnapshot(at: state.snapshotPath.map({ URL(filePath: $0) }))
        }
        return .init(
            targetURL: target.repository.rootURL,
            ephemeralID: target.workspace?.id,
            branch: branch,
        )
    }

    private func apply(
        patch: PatchFile?,
        sourceRepository: PatchsetRepository,
        reference: PatchsetReference,
        phase: OperationState.Phase,
        featureID: String,
        index: Int,
        state: inout OperationState,
        stateURL: URL,
        repository: GitRepository,
        committer: GitIdentity,
    ) async throws {
        state.currentIndex = index
        state.phase = phase
        try stateStore.save(state, to: stateURL)
        let result = try await PatchApplicator(
            sourceRepository: sourceRepository,
            reference: reference,
            repository: repository,
            committer: committer,
        ).apply(patch)
        guard result == .applied else {
            throw URIError.conflict(
                "Conflict while applying \(featureID) \(phase.rawValue) patch. Resolve it, stage the files, then continue.",
            )
        }
    }

    private func applyMainPatch(
        _ patch: PatchFile?,
        featureID: String,
        index: Int,
        reference: PatchsetReference,
        sourceRepository: PatchsetRepository,
        state: inout OperationState,
        stateURL: URL,
        repository: GitRepository,
        committer: GitIdentity,
    ) async throws {
        state.currentIndex = index
        state.phase = .main
        try stateStore.save(state, to: stateURL)
        let completed = Array(state.featureOrder.prefix(index))
        let result = try await PatchApplicator(
            sourceRepository: sourceRepository,
            reference: reference,
            repository: repository,
            committer: committer,
        ).applyMain(
            patch,
            featureID: featureID,
            completedFeatureIDs: completed,
        )
        guard result == .conflicted else {
            return
        }
        throw URIError.conflict(
            "Conflict while applying \(featureID). Resolve it, stage the files, then continue.",
        )
    }

    private func prepareTarget(
        requestedURL: URL?,
        currentDirectoryURL: URL,
        ephemeral: EphemeralRequest,
        upstream: String,
        version: String,
        sourceBaseURL: URL,
    ) async throws -> PreparedTarget {
        switch ephemeral {
        case .none:
            let candidate = requestedURL ?? currentDirectoryURL
            do {
                return .init(
                    repository: try await git.openRepository(at: candidate),
                    workspace: nil,
                )
            }
            catch where requestedURL == nil {
                throw URIError.targetRequired
            }
        case .automatic, .named:
            guard requestedURL == nil else {
                throw URIError.invalidArguments("TARGET and --ephemeral cannot be used together.")
            }
            let requestedID: String?
            switch ephemeral {
            case .named(let id):
                requestedID = id
            case .automatic:
                requestedID = nil
            case .none:
                fatalError("Handled above")
            }
            let remoteIdentity = try GitRemoteIdentity(upstream, relativeTo: sourceBaseURL)
            guard let repositoryName = remoteIdentity.repositoryName else {
                throw GitError.invalidReference(upstream)
            }
            let workspace = try ephemeralManager.create(
                requestedID: requestedID,
                repositoryName: repositoryName,
            )
            do {
                let repository = try await git.cloneRepository(
                    from: upstream,
                    to: workspace.repositoryURL,
                    options: .init(branch: version, depth: 1, singleBranch: true),
                )
                try await repository.validateRemote(matches: upstream, relativeTo: sourceBaseURL)
                return .init(repository: repository, workspace: workspace)
            }
            catch {
                try? ephemeralManager.removeUninitialized(workspace)
                throw error
            }
        }
    }

    private func existingTarget(
        requestedURL: URL?,
        currentDirectoryURL: URL,
        ephemeralID: String?,
    ) async throws -> PreparedTarget {
        if let ephemeralID {
            guard requestedURL == nil else {
                throw URIError.invalidArguments("TARGET and --ephemeral cannot be used together.")
            }
            let workspace = try ephemeralManager.workspace(id: ephemeralID)
            return .init(
                repository: try await git.openRepository(at: workspace.repositoryURL),
                workspace: workspace,
            )
        }
        let candidate = requestedURL ?? currentDirectoryURL
        do {
            return .init(repository: try await git.openRepository(at: candidate), workspace: nil)
        }
        catch where requestedURL == nil {
            throw URIError.targetRequired
        }
    }

    private func hasOperationState(_ target: PreparedTarget?) async throws -> Bool {
        guard let target else {
            return false
        }
        let url = try await stateStore.stateURL(
            for: target.repository,
            ephemeralID: target.workspace?.id,
            paths: paths,
        )
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func resolvedRepository(from state: OperationState) throws -> PatchsetRepository {
        if state.source.kind == .local {
            guard let rootURL = state.source.localRootURL else {
                throw URIError.invalidState("Saved local SOURCE has no path.")
            }
            return try PatchsetRepository(rootURL: rootURL)
        }
        guard let snapshotPath = state.snapshotPath else {
            throw URIError.invalidState("Saved remote SOURCE has no snapshot.")
        }
        var rootURL = URL(filePath: snapshotPath)
        if state.source.kind == .git {
            rootURL.append(path: "source", directoryHint: .isDirectory)
        }
        return try PatchsetRepository(rootURL: rootURL)
    }

    private func validate(
        state: OperationState,
        expectedMode: OperationState.Mode,
        target: PreparedTarget,
    ) throws {
        guard state.mode == expectedMode else {
            throw URIError.operationModeMismatch(
                expected: expectedMode.rawValue,
                actual: state.mode.rawValue,
            )
        }
        guard state.targetPath == target.repository.rootURL.path else {
            throw URIError.invalidState("Saved TARGET path does not match the selected repository.")
        }
        guard state.ephemeralID == target.workspace?.id else {
            throw URIError.invalidState("Saved ephemeral ID does not match the selected TARGET.")
        }
    }

    private func committer(
        from manifest: RootManifest,
        target: GitRepository,
    ) async throws -> GitIdentity {
        switch manifest.committer {
        case .repository:
            return try await target.configuredIdentity()
        case .explicit(let identity):
            return try .init(name: identity.name, email: identity.email)
        case nil:
            return try .init(
                name: RootManifest.legacyCommitterName,
                email: RootManifest.legacyCommitterEmail,
            )
        }
    }

    private func restoreStart(
        of state: OperationState,
        in repository: GitRepository,
    ) async throws {
        let start = try GitReference(rawValue: state.startCommit)
        if let branch = state.startBranch, try await repository.branchExists(branch) {
            try await repository.checkoutBranch(branch)
            try await repository.hardReset(to: start)
        }
        else {
            try await repository.checkoutDetached(at: start)
        }
    }

    private func deleteOperationBranches(
        state: OperationState,
        repository: GitRepository,
    ) async throws {
        let reference = try PatchsetReference(
            upstreamVersion: state.upstreamVersion,
            patchsetVersion: state.patchsetVersion,
        )
        for featureID in state.featureOrder.reversed() {
            let branch = featureBranchName(
                prefix: state.branchPrefix,
                reference: reference,
                featureID: featureID,
            )
            if try await repository.branchExists(branch) {
                try await repository.deleteBranch(branch, force: true)
            }
        }
        let branch = patchsetBranchName(prefix: state.branchPrefix, reference: reference)
        if try await repository.branchExists(branch), branch != state.startBranch {
            try await repository.deleteBranch(branch, force: true)
        }
    }

    private func cleanupExpandedBranches(
        state: OperationState,
        repository: GitRepository,
    ) async throws {
        let reference = try PatchsetReference(
            upstreamVersion: state.upstreamVersion,
            patchsetVersion: state.patchsetVersion,
        )
        try await repository.checkoutTag(state.upstreamVersion)
        for featureID in state.featureOrder.reversed() {
            let branch = featureBranchName(
                prefix: state.branchPrefix,
                reference: reference,
                featureID: featureID,
            )
            if try await repository.branchExists(branch) {
                try await repository.deleteBranch(branch, force: true)
            }
        }
    }

    private func reconstructAndSave(
        state: OperationState,
        target: GitRepository,
        recursive: Bool,
    ) async throws {
        guard let selectedFeature = state.feature else {
            throw URIError.invalidState("Expansion state does not record a selected feature.")
        }
        let sourceRepository = try resolvedRepository(from: state)
        guard state.source.kind == .local else {
            throw URIError.remoteSourceIsReadOnly("Remote SOURCE snapshots are read-only.")
        }
        let reference = try PatchsetReference(
            upstreamVersion: state.upstreamVersion,
            patchsetVersion: state.patchsetVersion,
        )
        let resolved = try sourceRepository.resolve(reference)
        let committer = try GitIdentity(name: state.committerName, email: state.committerEmail)
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "uri-collapse-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let cloneURL = temporaryRoot.appending(path: "repository", directoryHint: .isDirectory)
        let candidatesURL = temporaryRoot.appending(path: "patches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: candidatesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let clone = try await git.cloneRepository(
            from: target.rootURL.path,
            to: cloneURL,
            options: .init(noCheckout: true, shared: true),
        )
        try await clone.configureIdentity(committer)
        let baseline = try GitReference(rawValue: state.baselineCommit)
        var previousSourceReference: GitReference?
        var candidateData = [String: Data]()

        for (index, featureID) in state.featureOrder.enumerated() {
            let branch = featureBranchName(
                prefix: state.branchPrefix,
                reference: reference,
                featureID: featureID,
            )
            let sourceReference = try GitReference(rawValue: "refs/remotes/origin/\(branch)")
            guard try await clone.referenceExists(sourceReference) else {
                throw URIError.invalidState("Could not find feature branch during collapse: \(branch)")
            }
            guard try await clone.isAncestor(baseline, of: sourceReference) else {
                throw URIError.invalidState("Feature branch does not descend from the version baseline: \(branch)")
            }
            let originalBase: GitReference
            if let previousSourceReference {
                originalBase = GitReference(
                    try await clone.mergeBase(previousSourceReference, sourceReference),
                )
            }
            else {
                originalBase = baseline
            }

            try await clone.checkoutDetached(at: baseline)
            let dependencies = try resolved.dependencyOrder(
                for: featureID,
                in: .includingDevelopment,
            ).map(\.id).filter({ $0 != featureID && state.featureOrder.contains($0) })
            for dependency in dependencies {
                guard let data = candidateData[dependency] else {
                    throw URIError.invalidState(
                        "No reconstructed candidate exists for dependency \(dependency).",
                    )
                }
                if !data.isEmpty {
                    let patchURL = candidatesURL.appending(path: "\(dependency).patch")
                    let result = try await clone.applyMailboxPatch(at: patchURL, committer: committer)
                    guard result == .applied else {
                        try? await clone.abortMailboxApply()
                        throw URIError.conflict(
                            "Reconstructed dependency \(dependency) conflicts while collapsing \(featureID).",
                        )
                    }
                }
            }
            let dependencyBase = GitReference(try await clone.currentCommit())
            let count = try await clone.commitCount(
                fromExclusive: originalBase,
                through: sourceReference,
            )
            let candidateURL = candidatesURL.appending(path: "\(featureID).patch")
            if count == 0 {
                try Data().write(to: candidateURL, options: .atomic)
            }
            else {
                let temporaryBranch = "uri-collapse-candidate-\(index)"
                try await clone.checkoutResetBranch(temporaryBranch, at: sourceReference)
                do {
                    try await clone.rebase(
                        branch: temporaryBranch,
                        fromExclusive: originalBase,
                        onto: dependencyBase,
                        committer: committer,
                    )
                }
                catch {
                    try? await clone.abortRebase()
                    throw error
                }
                try await clone.writeFormatPatch(
                    fromExclusive: dependencyBase,
                    through: try GitReference(rawValue: temporaryBranch),
                    to: candidateURL,
                )
            }
            candidateData[featureID] = try Data(contentsOf: candidateURL)
            previousSourceReference = sourceReference
        }

        if !recursive {
            for dependency in state.featureOrder where dependency != selectedFeature {
                let existing = try sourceRepository.patch(
                    for: dependency,
                    inheritedBy: reference,
                ).map({ try Data(contentsOf: $0.url) })
                guard patchesAreEquivalent(candidateData[dependency] ?? Data(), existing ?? Data()) else {
                    throw URIError.invalidState(
                        "Dependency \(dependency) changed; rerun collapse with --recursive.",
                    )
                }
            }
        }

        let featuresToSave = recursive ? state.featureOrder : [selectedFeature]
        let replacements: [String: Data] = Dictionary(
            uniqueKeysWithValues: featuresToSave.compactMap { featureID -> (String, Data)? in
                guard let data = candidateData[featureID], !data.isEmpty else {
                    return nil
                }
                return (featureID, data)
            },
        )
        try sourceRepository.replaceFeaturePatchesTransactionally(replacements, in: reference)
    }

    private func patchesAreEquivalent(_ first: Data, _ second: Data) -> Bool {
        canonicalPatch(first) == canonicalPatch(second)
    }

    private func canonicalPatch(_ data: Data) -> [Substring] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { line in
                !line.hasPrefix("From ")
                    && !line.hasPrefix("From:")
                    && !line.hasPrefix("Date:")
                    && !line.hasPrefix("Subject:")
                    && !line.hasPrefix("index ")
            }
    }

    private func featureBranchName(
        prefix: String,
        reference: PatchsetReference,
        featureID: String,
    ) -> String {
        "\(prefix)/\(reference.upstreamVersion)/\(reference.patchsetVersion)/\(featureID)"
    }

    private func patchsetBranchName(
        prefix: String,
        reference: PatchsetReference,
    ) -> String {
        "\(prefix)/\(reference.upstreamVersion)/\(reference.patchsetVersion)"
    }
}
