// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeBarMonitor",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "ClaudeBarMonitor",
            path: "Sources/ClaudeBarMonitor",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
