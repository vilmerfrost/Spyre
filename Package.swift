// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spyre",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpyreCore", targets: ["SpyreCore"]),
        .executable(name: "Spyre", targets: ["Spyre"]),
    ],
    targets: [
        .target(
            name: "SpyreCore",
            resources: [.copy("Resources/Themes")]
        ),
        .executableTarget(
            name: "Spyre",
            dependencies: ["SpyreCore"]
        ),
        .testTarget(
            name: "SpyreCoreTests",
            dependencies: ["SpyreCore"]
        ),
        .testTarget(name: "SpyreLintTests"),
    ],
    swiftLanguageModes: [.v6]
)
