import Foundation
import Testing
import URIPatchset

@Suite("Patch Lookup")
struct PatchLookupTests {

    @Test
    func `every patch kind is found from the nearest inheritance generation`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let parent = try fixture.reference("v1.2.3", "patch1.0")
        let child = try fixture.reference("v1.2.4", "patch1.1")
        try fixture.writeManifest("features: {base: {}, search: {}}", for: parent)
        try fixture.writeManifest(
            """
            inherits:
              upstream-version: v1.2.3
              patchset-version: patch1.0
            features: {}
            """,
            for: child,
        )
        try fixture.writePatch("parent base", identifiedBy: .feature("base"), in: parent)
        try fixture.writePatch("child base", identifiedBy: .feature("base"), in: child)
        try fixture.writePatch(identifiedBy: .ante("search"), in: parent)
        try fixture.writePatch(identifiedBy: .post("search"), in: child)
        try fixture.writePatch(
            identifiedBy: .pair(current: "search", completed: "base"),
            in: parent,
        )

        let feature = try fixture.repository.patch(for: "base", inheritedBy: child)
        let ante = try fixture.repository.antePatch(for: "search", inheritedBy: child)
        let post = try fixture.repository.postPatch(for: "search", inheritedBy: child)
        let pair = try fixture.repository.pairResolutionPatch(
            for: "search",
            completedFeatureID: "base",
            inheritedBy: child,
        )
        let childFeatureURL = try fixture.patchURL(for: .feature("base"), in: child)

        #expect(feature?.source == child)
        #expect(feature?.url == childFeatureURL)
        #expect(ante?.source == parent)
        #expect(post?.source == child)
        #expect(pair?.source == parent)
        #expect(try fixture.repository.patch(for: "missing", inheritedBy: child) == nil)
    }

    @Test
    func `applicable pair lookup prefers the most recently completed feature`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest(
            "features: {current: {}, older: {}, newer: {}}",
            for: reference,
        )
        try fixture.writePatch(
            identifiedBy: .pair(current: "current", completed: "older"),
            in: reference,
        )
        try fixture.writePatch(
            identifiedBy: .pair(current: "current", completed: "newer"),
            in: reference,
        )

        let patch = try fixture.repository.applicablePairResolutionPatch(
            for: "current",
            completedFeatureIDs: ["older", "newer"],
            inheritedBy: reference,
        )

        #expect(patch?.identifier == .pair(current: "current", completed: "newer"))
    }

    @Test
    func `patch lookup and deletion ignore directories named like patches`() throws {
        let fixture = try PatchsetTestFixture()
        defer { fixture.remove() }
        let reference = try fixture.reference("patch1.0")
        try fixture.writeManifest("features: {base: {}}", for: reference)
        let patchURL = try fixture.patchURL(for: .feature("base"), in: reference)
        try FileManager.default.createDirectory(
            at: patchURL,
            withIntermediateDirectories: false,
        )

        #expect(try fixture.repository.patch(for: "base", inheritedBy: reference) == nil)
        #expect(
            capturedPatchsetError({
                try fixture.repository.removePatch(
                    identifiedBy: .feature("base"),
                    in: reference,
                )
            }) == .patchNotFound(patchURL),
        )
        #expect(FileManager.default.fileExists(atPath: patchURL.path))
    }
}
