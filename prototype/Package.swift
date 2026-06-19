// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlansGarden",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "GardenCore"
        ),
        .executableTarget(
            name: "garden",
            dependencies: ["GardenCore"]
        ),
        .executableTarget(
            name: "GardenApp",
            dependencies: ["GardenCore"]
        ),
        .testTarget(
            name: "GardenCoreTests",
            dependencies: ["GardenCore"]
        ),
    ]
)
