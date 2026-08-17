// swift-tools-version: 6.3

import PackageDescription

// MARK: - (Swift settings)

enum UpcomingFeature: String, CaseIterable {

    case approachableConcurrency = "ApproachableConcurrency"

    case existentialAny = "ExistentialAny"

    case immutableWeakCaptures = "ImmutableWeakCaptures"

    case inferIsolatedConformances = "InferIsolatedConformances"

    case internalImportsByDefault = "InternalImportsByDefault"

    case memberImportVisibility = "MemberImportVisibility"

    case nonisolatedNonsendingByDefault = "NonisolatedNonsendingByDefault"
}

func swiftSettings(
    defaultIsolation: MainActor.Type? = MainActor.self,
    strictMemorySafety: Bool = true,
    enabledUpcomingFeatures: [UpcomingFeature] = UpcomingFeature.allCases
) -> [SwiftSetting] {
    var settings = [SwiftSetting]()
    if let isolation = defaultIsolation {
        settings.append(.defaultIsolation(isolation))
    }
    if strictMemorySafety {
        settings.append(.strictMemorySafety())
    }
    settings.append(
        contentsOf:
            enabledUpcomingFeatures.map({.enableUpcomingFeature($0.rawValue)}),
    )
    return settings
}

// MARK: - (Package)

let package: Package = .init(
    name: "uri",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "uri",
            targets: ["URICommand"],
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-server/async-http-client",
            .upToNextMajor(from: "1.36.0"),
        ),
        .package(
            url: "https://github.com/apple/swift-nio",
            .upToNextMajor(from: "2.100.0"),
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            .upToNextMajor(from: "1.8.2"),
        ),
        .package(
            url: "https://github.com/uri-life/uritsort",
            from: "0.1.0",
        ),
        .package(
            url: "https://github.com/jpsim/Yams",
            .upToNextMajor(from: "6.2.2"),
        ),
    ],
    targets: [
        // URICommand
        .executableTarget(
            name: "URICommand",
            dependencies: [
                "URI",
                "URIModel",
                "URIPatchset",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser",
                ),
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
            plugins: ["URIVersionsGeneratorPlugin"],
        ),
        .testTarget(
            name: "URICommandTests",
            dependencies: [
                "URICommand",
                "URI",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser",
                ),
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        // URI
        .target(
            name: "URI",
            dependencies: [
                "URIGit",
                "URIModel",
                "URIPatchset",
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                ),
                .product(
                    name: "NIOCore",
                    package: "swift-nio",
                ),
                .product(
                    name: "NIOHTTP1",
                    package: "swift-nio",
                ),
                .product(
                    name: "Yams",
                    package: "Yams",
                ),
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        .testTarget(
            name: "URITests",
            dependencies: [
                "URI",
                "URIModel",
                "URIPatchset",
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                ),
                .product(
                    name: "NIOCore",
                    package: "swift-nio",
                ),
                .product(
                    name: "NIOHTTP1",
                    package: "swift-nio",
                ),
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        // URIGit
        .target(
            name: "URIGit",
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        .testTarget(
            name: "URIGitTests",
            dependencies: ["URIGit"],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        // URIPatchset
        .target(
            name: "URIPatchset",
            dependencies: [
                "URIModel",
                .product(
                    name: "TopologicalSort",
                    package: "uritsort",
                ),
                .product(
                    name: "Yams",
                    package: "Yams",
                ),
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        .testTarget(
            name: "URIPatchsetTests",
            dependencies: [
                "URIModel",
                "URIPatchset",
            ],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        // URIModel
        .target(
            name: "URIModel",
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        .testTarget(
            name: "URIModelTests",
            dependencies: ["URIModel"],
            swiftSettings: swiftSettings(defaultIsolation: nil),
        ),
        .plugin(
            name: "URIVersionsGeneratorPlugin",
            capability: .buildTool(),
            path: "Plugins/VersionsGeneratorPlugin",
        ),
    ]
)
