// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Scholium",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ScholiumApp", targets: ["ScholiumApp"]),
        .executable(name: "scholium", targets: ["ScholiumCLI"]),
        .library(name: "ScholiumCore", targets: ["ScholiumCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
    ],
    targets: [
        .target(
            name: "ScholiumCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "ScholiumCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ScholiumApp",
            dependencies: ["ScholiumCore"],
            path: "Scholium",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ScholiumCLI",
            dependencies: ["ScholiumCore"],
            path: "ScholiumCLI"
        ),
        .testTarget(
            name: "ScholiumCoreTests",
            dependencies: ["ScholiumCore"],
            path: "Tests/ScholiumCoreTests",
            exclude: ["Fixtures"]
        ),
    ]
)
