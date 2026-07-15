// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Scholium",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ScholiumApp", targets: ["ScholiumApp"]),
        .executable(name: "scholium", targets: ["ScholiumCLI"]),
        .library(name: "ScholiumContracts", targets: ["ScholiumContracts"]),
        .library(name: "ScholiumApplication", targets: ["ScholiumApplication"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
    ],
    targets: [
        .target(
            name: "ScholiumContracts",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "ScholiumContracts"
        ),
        .target(
            name: "ScholiumCore",
            dependencies: [
                "ScholiumContracts",
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "ScholiumCore",
            resources: [.copy("Resources/Skills")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ScholiumApplication",
            dependencies: ["ScholiumContracts", "ScholiumCore"],
            path: "ScholiumApplication",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ScholiumApp",
            dependencies: ["ScholiumContracts", "ScholiumApplication"],
            path: "Scholium",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ScholiumCLI",
            dependencies: ["ScholiumContracts", "ScholiumApplication"],
            path: "ScholiumCLI"
        ),
        .testTarget(
            name: "ScholiumContractsTests",
            dependencies: ["ScholiumContracts"],
            path: "Tests/ScholiumContractsTests"
        ),
        .testTarget(
            name: "ScholiumCoreTests",
            dependencies: [
                "ScholiumContracts",
                "ScholiumCore",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/ScholiumCoreTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "ScholiumApplicationTests",
            dependencies: ["ScholiumContracts", "ScholiumApplication"],
            path: "Tests/ScholiumApplicationTests"
        ),
        .testTarget(
            name: "ScholiumAppTests",
            dependencies: ["ScholiumApp", "ScholiumContracts", "ScholiumApplication"],
            path: "Tests/ScholiumAppTests"
        ),
    ]
)
