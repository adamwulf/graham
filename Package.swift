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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/adamwulf/FellerBuncher.git", branch: "main"),
    ],
    targets: [
        // The library stays dependency-free and print-free: it logs through the
        // GrahamLog seam. Only the executable links a logging backend.
        .target(name: "GrahamKit"),
        .executableTarget(
            name: "graham",
            dependencies: [
                "GrahamKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "FellerBuncher", package: "FellerBuncher"),
            ]
        ),
        .testTarget(name: "GrahamKitTests", dependencies: ["GrahamKit"]),
        .testTarget(name: "CLITests", dependencies: ["graham"]),
    ]
)
