// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "whooshing.toolbox-websocket",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        .library(name: "WhooshingWebsocket", targets: ["WhooshingWebsocket"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.78.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.24.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-client.git", .upToNextMajor(from: "1.0.3"))
    ],
    targets: [
        .target(
            name: "WhooshingWebsocket",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "toolbox-websocket-Tests",
            dependencies: [
                .target(name: "WhooshingWebsocket"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableExperimentalFeature("StrictConcurrency=complete")
] }
