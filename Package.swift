// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pause",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pause",
            path: "Sources/Pause"
        )
    ]
)
