import Foundation
import Testing
import URIModel

@Suite("Root Manifest")
struct RootManifestTests {

    @Test
    func `RootManifest initialization defaults optional fields to nil`() {
        let manifest = RootManifest(upstream: "https://example.com/upstream.git")

        #expect(manifest.upstream == "https://example.com/upstream.git")
        #expect(manifest.branchPrefix == nil)
        #expect(manifest.committer == nil)
    }

    @Test
    func `a repository committer round-trips through Codable`() throws {
        let manifest =
            RootManifest(
                upstream: "https://example.com/upstream.git",
                branchPrefix: "uri/",
                committer: .repository,
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(RootManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"branch-prefix":"uri\/","committer":{"mode":"repository"},"upstream":"https:\/\/example.com\/upstream.git"}"#,
        )
    }

    @Test
    func `an explicit committer round-trips through Codable`() throws {
        let manifest =
            RootManifest(
                upstream: "git@example.com:upstream/repository.git",
                committer: .explicit(
                    .init(
                        name: "URI Bot",
                        email: "uri@example.com",
                    ),
                ),
            )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(RootManifest.self, from: data)

        #expect(decoded == manifest)
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"committer":{"email":"uri@example.com","mode":"explicit","name":"URI Bot"},"upstream":"git@example.com:upstream\/repository.git"}"#,
        )
    }

    @Test
    func `an unknown committer mode fails decoding`() {
        let data = Data(#"{"mode":"automatic"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(RootManifest.Committer.self, from: data)
        }
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
