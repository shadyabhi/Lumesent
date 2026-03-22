// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Lumesent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lumesent",
            path: "Sources/Lumesent",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
