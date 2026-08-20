// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoPauseMacApps",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AutoPauseMacApps",
            path: "Sources/AutoPauseMacApps"
        )
    ]
)
