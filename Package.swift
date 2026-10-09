// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spyre",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpyreCore", targets: ["SpyreCore"]),
    ],
    targets: [
        .target(name: "SpyreCore"),
        .testTarget(
            name: "SpyreCoreTests",
            dependencies: ["SpyreCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
