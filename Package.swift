// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShiftHappens",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShiftHappens",
            path: "Sources/ShiftHappens",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
