// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FestiveLights",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FestiveLights", targets: ["FestiveLights"])
    ],
    targets: [
        .executableTarget(
            name: "FestiveLights",
            path: "Sources/FestiveLights"
        )
    ],
    swiftLanguageModes: [.v5]
)
