// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyBindingApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyBindingApp",
            path: "Sources/KeyBindingApp",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
