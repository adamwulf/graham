// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "graham",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "GrahamKit", targets: ["GrahamKit"]),
        .executable(name: "graham", targets: ["graham"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "GrahamKit"),
        .executableTarget(
            name: "graham",
            dependencies: [
                "GrahamKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "GrahamKitTests", dependencies: ["GrahamKit"]),
        .testTarget(name: "CLITests", dependencies: ["graham"]),
    ]
)
