// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sergey",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SergeyKit", targets: ["SergeyKit"]),
        .executable(name: "sergey", targets: ["sergey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "SergeyKit"),
        .executableTarget(
            name: "sergey",
            dependencies: [
                "SergeyKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "SergeyKitTests", dependencies: ["SergeyKit"]),
        .testTarget(name: "CLITests", dependencies: ["sergey"]),
    ]
)
