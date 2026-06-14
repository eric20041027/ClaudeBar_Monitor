// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeBarMonitor",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "ClaudeBarMonitor",
            path: "Sources/ClaudeBarMonitor",
            resources: [
                // Animated token frames for the Touch Bar gauge centre.
                // Drop frame PNGs (e.g. token-00.png, token-01.png, …) here.
                .copy("Resources/token-frames"),
                // Pixel engineer animation for the session-cost item.
                // Drop `engineer.gif` here; until then the cost item reuses
                // the token GIF as a placeholder.
                .copy("Resources/cost-frames")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
