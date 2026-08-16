import Testing
import URIPatchset

@Suite("Patchset Reference")
struct PatchsetReferenceTests {

    @Test
    func `identifiers allow neutral names and plus metadata`() throws {
        let reference = try PatchsetReference(
            upstreamVersion: "release+meta",
            patchsetVersion: "patch+base_1.0",
        )

        #expect(reference.upstreamVersion == "release+meta")
        #expect(reference.patchsetVersion == "patch+base_1.0")
        #expect(reference.description == "release+meta+patch+base_1.0")
    }

    @Test
    func `identifiers reject unsafe path and Git ref components`() {
        for value in ["", ".hidden", "a/b", "a..b", "topic.lock", "topic.", "한글"] {
            let error = capturedPatchsetError({
                try PatchsetReference(
                    upstreamVersion: value,
                    patchsetVersion: "patch1.0",
                )
            })

            guard case .invalidIdentifier(_, let rejected)? = error else {
                Issue.record("Expected invalidIdentifier for \(value).")
                continue
            }
            #expect(rejected == value)
        }
    }

    @Test
    func `patch identifiers produce every supported filename`() throws {
        #expect(try PatchIdentifier.feature("base").filename == "base.patch")
        #expect(try PatchIdentifier.ante("base").filename == "base~ANTE.patch")
        #expect(try PatchIdentifier.post("base").filename == "base~POST.patch")
        #expect(
            try PatchIdentifier.pair(current: "search", completed: "base").filename
                == "search~base.patch",
        )
    }
}
