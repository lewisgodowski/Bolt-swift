// swift-tools-version:5.2

import PackageDescription

var targets: [PackageDescription.Target] = [
    .target(
        name: "Bolt",
        dependencies: [
            "PackStream",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
        ],
        path: "Sources"),
    .testTarget(name: "BoltTests", dependencies: ["Bolt"]),
]

let package = Package(
    name: "Bolt",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "Bolt", targets: ["Bolt"]),
    ],
    dependencies: [
        .package(name: "PackStream", url: "https://github.com/Neo4j-Swift/PackStream-swift.git", from: "1.1.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.56.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.24.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.17.0")
    ],
    targets: targets
)
