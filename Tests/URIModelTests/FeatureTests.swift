import Testing
import URIModel

@Suite("Feature")
struct FeatureTests {

    @Test
    func `Feature initialization preserves every field`() {
        let feature =
            Feature(
                id: "search",
                name: "Search",
                description: "Adds search",
                dependencies: ["core"],
                devDependencies: ["fixtures"],
            )

        #expect(feature.id == "search")
        #expect(feature.name == "Search")
        #expect(feature.description == "Adds search\n")
        #expect(feature.dependencies == ["core"])
        #expect(feature.devDependencies == ["fixtures"])
    }

    @Test
    func `Feature initialization defaults optional fields to nil`() {
        let feature = Feature(id: "core")

        #expect(feature.name == nil)
        #expect(feature.description == nil)
        #expect(feature.dependencies == nil)
        #expect(feature.devDependencies == nil)
    }

    @Test
    func `Feature normalizes description line endings and trailing newlines`() {
        var feature = Feature(
            id: "search",
            description: "First\r\nSecond\r\r\n\n",
        )

        #expect(feature.description == "First\nSecond\n")

        feature.description = ""
        #expect(feature.description == "\n")

        feature.description = nil
        #expect(feature.description == nil)
    }

    @Test
    func `Feature identity, equality, and hashing depend only on the ID`() {
        let original = Feature(id: "search", name: "Search")
        let renamed = Feature(id: "search", name: "Renamed")
        let other = Feature(id: "core", name: "Search")

        #expect(original.id == "search")
        #expect(original == renamed)
        #expect(original != other)
        #expect(Set([original, renamed, other]).count == 2)
    }
}
