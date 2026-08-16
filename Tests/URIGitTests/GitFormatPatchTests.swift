import Foundation
import Testing
import URIGit

@Suite("Git Format Patch")
struct GitFormatPatchTests {

    @Test
    func `format patch zeroes every envelope hash and retains binary changes`() async throws {
        let source = try GitTestFixture()
        defer { source.remove() }
        let target = try GitTestFixture(cloning: source.rootURL)
        defer { target.remove() }
        let sourceRepository = try await source.repository()
        let targetRepository = try await target.repository()
        let base = GitReference(try await sourceRepository.currentCommit())
        _ = try source.commit("first\n", to: "first.txt", message: "first change")
        let binary = Data([0, 1, 2, 3, 255, 0, 128])
        try source.write(binary, to: "binary.dat")
        try source.git([
            "add",
            "binary.dat",
        ])
        try source.git([
            "commit",
            "-m",
            "binary change",
        ])
        let patchURL = source.rootURL.appending(path: "series.patch")

        try await sourceRepository.writeFormatPatch(
            fromExclusive: base,
            through: .head,
            to: patchURL,
        )

        let patch = try String(contentsOf: patchURL, encoding: .utf8)
        let envelopeLines = patch.split(separator: "\n").filter({
            $0.hasPrefix("From ") && $0.hasSuffix(" Mon Sep 17 00:00:00 2001")
        })
        #expect(envelopeLines.count == 2)
        #expect(
            envelopeLines.allSatisfy({ line in
                line.split(separator: " ")[1].allSatisfy({ $0 == "0" })
            }),
        )
        #expect(patch.contains("GIT binary patch"))

        #expect(
            try await targetRepository.applyMailboxPatch(
                at: patchURL,
                committer: .test,
            ) == .applied,
        )
        #expect(try Data(contentsOf: target.rootURL.appending(path: "binary.dat")) == binary)
        #expect(try String(contentsOf: target.rootURL.appending(path: "first.txt"), encoding: .utf8) == "first\n")
    }

    @Test
    func `empty commit range writes an empty patch`() async throws {
        let fixture = try GitTestFixture()
        defer { fixture.remove() }
        let repository = try await fixture.repository()
        let outputURL = fixture.rootURL.appending(path: "empty.patch")

        try await repository.writeFormatPatch(
            fromExclusive: .head,
            through: .head,
            to: outputURL,
        )

        #expect(try Data(contentsOf: outputURL).isEmpty)
    }
}
