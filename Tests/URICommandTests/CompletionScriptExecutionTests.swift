import Foundation
import Testing
import URI
import URIModel
import URIPatchset

@testable
import URICommand

@Suite("Completion Script Execution")
struct CompletionScriptExecutionTests {

    @Test
    func `generated Bash script returns contextual values through the built executable`() async throws {
        guard let bash = executable(named: "bash") else {
            return
        }
        let fixture = try await completionFixture(for: .bash, fileName: "uri.bash")
        defer { fixture.remove() }

        let result = try run(
            bash,
            arguments: [
                "-c",
                """
                source "$1"
                complete -p uri >/dev/null || exit 10

                COMP_WORDS=(uri ap); COMP_CWORD=1; _uri
                printf 'root=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri --color al); COMP_CWORD=2; _uri
                printf 'color=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri list v2); COMP_CWORD=2; _uri
                printf 'version=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri list v1 ch); COMP_CWORD=3; _uri
                printf 'patchset=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri expand v1 open in); COMP_CWORD=4; _uri
                printf 'feature=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri add v1 open new --dependencies inherited,di); COMP_CWORD=6; _uri
                printf 'dependency=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri add v1 new --inherits v2+o); COMP_CWORD=5; _uri
                printf 'inherits=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri apply --continue --ephemeral pe); COMP_CWORD=4; _uri
                printf 'ephemeral=%s\n' "${COMPREPLY[*]}"
                COMP_WORDS=(uri apply v1 open tar); COMP_CWORD=4; _uri
                printf 'target=%s\n' "${COMPREPLY[*]}"
                """,
                "_",
                fixture.scriptURL.path,
            ],
            environment: fixture.environment,
            currentDirectoryURL: fixture.rootURL,
        )

        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
        #expect(
            result.standardOutput == """
                root=apply
                color=always
                version=v2
                patchset=child
                feature=inherited
                dependency=inherited,direct-open
                inherits=v2+other
                ephemeral=peach
                target=target-directory

                """,
        )
    }

    @Test
    func `generated Zsh script completes contextual values through the interactive system`() async throws {
        guard
            let zsh = executable(named: "zsh"),
            let expect = executable(named: "expect")
        else {
            return
        }
        let fixture = try await completionFixture(for: .zsh, fileName: "_uri")
        defer { fixture.remove() }

        let zshRC = fixture.directoryURL.appending(path: ".zshrc", directoryHint: .notDirectory)
        try Data(
            """
            PS1='URI> '
            cd -- "$URI_COMPLETION_TEST_SOURCE"
            autoload -Uz compinit
            compinit -D
            source "$URI_COMPLETION_TEST_SCRIPT"
            uri_report_buffer() {
                print -r --
                print -r -- "URI_BUFFER=$BUFFER"
                BUFFER=
                zle reset-prompt
            }
            zle -N uri_report_buffer
            bindkey '^X^R' uri_report_buffer

            """.utf8,
        ).write(to: zshRC)
        let expectScript = fixture.directoryURL.appending(
            path: "completion.exp",
            directoryHint: .notDirectory,
        )
        try Data(
            """
            set timeout 15
            spawn -noecho env ZDOTDIR=$env(URI_COMPLETION_TEST_DIRECTORY) PATH=$env(URI_COMPLETION_TEST_PATH) CFFIXED_USER_HOME=$env(URI_COMPLETION_TEST_HOME) HOME=$env(URI_COMPLETION_TEST_HOME) $env(URI_ZSH) -d
            expect "URI> "
            send "uri ap\\t\\030\\022"
            expect -exact "URI_BUFFER=uri apply "
            expect "URI> "
            send "uri list v2\\t\\030\\022"
            expect -exact "URI_BUFFER=uri list v2 "
            expect "URI> "
            send "uri list v1 ch\\t\\030\\022"
            expect -exact "URI_BUFFER=uri list v1 child "
            expect "URI> "
            send "uri expand v1 open in\\t\\030\\022"
            expect -exact "URI_BUFFER=uri expand v1 open inherited "
            expect "URI> "
            send "uri add v1 open new --dependencies inherited,di\\t\\030\\022"
            expect -exact "URI_BUFFER=uri add v1 open new --dependencies inherited,direct-open "
            expect "URI> "
            send "uri add v1 new --inherits v2+o\\t\\030\\022"
            expect -exact "URI_BUFFER=uri add v1 new --inherits v2+other "
            expect "URI> "
            send "uri apply --continue --ephemeral pe\\t\\030\\022"
            expect -exact "URI_BUFFER=uri apply --continue --ephemeral peach "
            expect "URI> "
            send "uri apply v1 open tar\\t\\030\\022"
            expect -exact "URI_BUFFER=uri apply v1 open target-directory/"
            expect "URI> "
            send "exit\\r"
            expect eof

            """.utf8,
        ).write(to: expectScript)
        let result = try run(
            expect,
            arguments: [expectScript.path],
            environment: fixture.environment.merging(
                [
                    "URI_COMPLETION_TEST_DIRECTORY": fixture.directoryURL.path,
                    "URI_COMPLETION_TEST_HOME": fixture.homeURL.path,
                    "URI_COMPLETION_TEST_PATH": fixture.environment["PATH"]!,
                    "URI_COMPLETION_TEST_SCRIPT": fixture.scriptURL.path,
                    "URI_COMPLETION_TEST_SOURCE": fixture.rootURL.path,
                    "URI_ZSH": zsh.path,
                ],
                uniquingKeysWith: { _, override in override },
            ),
        )

        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
        #expect(result.standardOutput.contains("URI_BUFFER=uri expand v1 open inherited "))
        #expect(result.standardOutput.contains("URI_BUFFER=uri apply --continue --ephemeral peach "))
        #expect(!result.standardOutput.contains("invalid argument"))
    }

    @Test
    func `generated Fish script returns contextual values through native completion`() async throws {
        guard let fish = executable(named: "fish") else {
            return
        }
        let fixture = try await completionFixture(for: .fish, fileName: "uri.fish")
        defer { fixture.remove() }

        let result = try run(
            fish,
            arguments: [
                "-c",
                """
                set -gx PATH "$argv[2]" $PATH
                set -gx CFFIXED_USER_HOME "$argv[3]"
                set -gx HOME "$argv[3]"
                cd "$argv[4]"
                source "$argv[1]"
                function uri_candidates
                    complete -C "$argv[1]" | string replace -r '\\t.*' '' | string join ' '
                end
                printf 'root=%s\\n' (uri_candidates 'uri ap')
                printf 'color=%s\\n' (uri_candidates 'uri --color al')
                printf 'version=%s\\n' (uri_candidates 'uri list v2')
                printf 'patchset=%s\\n' (uri_candidates 'uri list v1 ch')
                printf 'feature=%s\\n' (uri_candidates 'uri expand v1 open in')
                printf 'dependency=%s\\n' (uri_candidates 'uri add v1 open new --dependencies inherited,di')
                printf 'inherits=%s\\n' (uri_candidates 'uri add v1 new --inherits v2+o')
                printf 'ephemeral=%s\\n' (uri_candidates 'uri apply --continue --ephemeral pe')
                printf 'target=%s\\n' (uri_candidates 'uri apply v1 open tar')
                """,
                fixture.scriptURL.path,
                fixture.executableURL.deletingLastPathComponent().path,
                fixture.homeURL.path,
                fixture.rootURL.path,
            ],
        )

        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
        #expect(
            result.standardOutput == """
                root=apply
                color=always
                version=v2
                patchset=child
                feature=inherited
                dependency=inherited,direct-open
                inherits=v2+other
                ephemeral=peach
                target=target-directory/

                """,
        )
    }

    @Test
    func `generated scripts pass each shells native syntax check`() async throws {
        for shell in CompletionShell.allCases {
            guard let executable = executable(named: shell.rawValue) else {
                continue
            }
            let fixture = try await completionFixture(
                for: shell,
                fileName: "uri.\(shell.rawValue)",
            )
            defer { fixture.remove() }

            let result = try run(executable, arguments: ["-n", fixture.scriptURL.path])
            #expect(result.status == 0)
            #expect(result.standardError.isEmpty)
        }
    }

    @Test
    func `built executable rejects an unsupported completion shell`() throws {
        let uri = try #require(uriExecutable())

        let result = try run(
            uri,
            arguments: ["--generate-completion-script", "powershell"],
        )

        #expect(result.status == 64)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Invalid completion shell 'powershell'"))
        #expect(result.standardError.contains("usage: uri"))
    }

    private func completionFixture(
        for shell: CompletionShell,
        fileName: String,
    ) async throws -> CompletionFixture {
        let uri = try #require(uriExecutable())
        let generation = try run(
            uri,
            arguments: [
                "--color", "always", "--generate-completion-script", shell.rawValue,
            ],
        )
        #expect(generation.status == 0)
        #expect(generation.standardError.isEmpty)
        #expect(!generation.standardOutput.contains("\u{001B}["))

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "URICompletionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let root = directory.appending(path: "patchsets", directoryHint: .isDirectory)
        let home = directory.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "target-directory", directoryHint: .isDirectory),
            withIntermediateDirectories: false,
        )
        try populatePatchsets(at: root)
        try populateEphemeralWorkspace(homeURL: home, rootURL: root)

        let script = directory.appending(path: fileName, directoryHint: .notDirectory)
        try Data(generation.standardOutput.utf8).write(to: script)
        let path = [
            uri.deletingLastPathComponent().path,
            ProcessInfo.processInfo.environment["PATH"] ?? "",
        ].joined(separator: ":")
        return .init(
            directoryURL: directory,
            scriptURL: script,
            rootURL: root,
            homeURL: home,
            executableURL: uri,
            environment: [
                "CFFIXED_USER_HOME": home.path,
                "HOME": home.path,
                "PATH": path,
            ],
        )
    }

    private func populatePatchsets(at rootURL: URL) throws {
        let repository = try PatchsetRepository(rootURL: rootURL)
        try repository.initializeRoot(
            with: .init(
                upstream: "https://example.com/upstream.git",
                branchPrefix: "uri",
                committer: .repository,
            ),
        )
        try repository.createUpstreamVersion("v1")
        try repository.createUpstreamVersion("v2")

        let base = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "base")
        try repository.createPatchset(base)
        try repository.addFeature(.init(id: "inherited"), to: base)

        let child = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "child")
        try repository.createPatchset(child, inheriting: base)

        let open = try PatchsetReference(upstreamVersion: "v1", patchsetVersion: "open")
        try repository.createPatchset(open, inheriting: base)
        try repository.addFeature(.init(id: "direct-open"), to: open)

        let other = try PatchsetReference(upstreamVersion: "v2", patchsetVersion: "other")
        try repository.createPatchset(other)
    }

    private func populateEphemeralWorkspace(
        homeURL: URL,
        rootURL: URL,
    ) throws {
        let paths = RuntimePaths(homeURL: homeURL)
        let workspace = try EphemeralWorkspaceManager(paths: paths).create(requestedID: "peach")
        try FileManager.default.createDirectory(
            at: workspace.repositoryURL,
            withIntermediateDirectories: true,
        )
        try OperationStateStore().save(
            .init(
                mode: .apply,
                phase: .active,
                source: .init(
                    kind: .local,
                    original: rootURL.path,
                    localRootURL: rootURL,
                ),
                snapshotPath: nil,
                upstreamVersion: "v1",
                patchsetVersion: "open",
                feature: nil,
                featureOrder: ["inherited", "direct-open"],
                targetPath: workspace.repositoryURL.path,
                startCommit: String(repeating: "1", count: 40),
                startBranch: nil,
                baselineCommit: String(repeating: "1", count: 40),
                branchPrefix: "uri",
                committerName: "URI",
                committerEmail: "uri@uri.life",
                ephemeralID: "peach",
            ),
            to: workspace.stateURL,
        )
    }

    private func executable(named name: String) -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }
        return path.split(separator: ":").lazy.map({ directory in
            URL(filePath: String(directory)).appending(path: name, directoryHint: .notDirectory)
        }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func uriExecutable() -> URL? {
        let starts = [
            URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent(),
            Bundle(for: CompletionTestBundleMarker.self).bundleURL,
            Bundle.main.bundleURL,
        ]
        for start in starts {
            var directory = start
            for _ in 0..<8 {
                let candidate = directory.appending(path: "uri", directoryHint: .notDirectory)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }

    private func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil,
    ) throws -> ShellResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment,
            uniquingKeysWith: { _, override in override },
        )
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return .init(
            status: process.terminationStatus,
            standardOutput: String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self,
            ),
            standardError: String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self,
            ),
        )
    }
}

private final class CompletionTestBundleMarker {
}

private struct CompletionFixture {

    let directoryURL: URL

    let scriptURL: URL

    let rootURL: URL

    let homeURL: URL

    let executableURL: URL

    let environment: [String: String]

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private struct ShellResult {

    let status: Int32

    let standardOutput: String

    let standardError: String
}
