extension Versions {

    static nonisolated var current: String {
        if let release = releaseVersion(from: tag) {
            return release
        }
        guard !commit.isEmpty else {
            return "dev"
        }
        return "dev+\(commit.prefix(7))"
    }

    private static nonisolated func releaseVersion(from value: String) -> String? {
        let components = value.hasPrefix("v") ? value.dropFirst() : value[...]
        let fields = components.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3,
            fields.allSatisfy({ field in
                !field.isEmpty && field.allSatisfy(\.isNumber)
            })
        else {
            return nil
        }
        return String(components)
    }
}
