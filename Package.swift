// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Lumesent",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lumesent",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Lumesent",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
