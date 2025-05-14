// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "whooshing.toolbox-websocket-vapor",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v14),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        .library(name: "WhooshingWebSocket", targets: ["WhooshingWebSocket"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.78.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.24.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0"),
        .package(url: "https://github.com/SJJC-Team/whooshing-vapor.git", from: "1.0.0"),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-client-vapor.git", .upToNextMajor(from: "1.0.3"))
    ],
    targets: [
        .target(
            name: "WhooshingWebSocket",
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
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client-vapor"),
                .product(name: "Vapor", package: "whooshing-vapor")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "toolbox-websocket-Tests",
            dependencies: [
                .target(name: "WhooshingWebSocket"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
    .define("WHOOSHING_VAPOR")
] }
