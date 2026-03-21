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
                // bundle.sh copies Sparkle into Contents/Frameworks; dyld must search there at launch.
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
    ]
)
