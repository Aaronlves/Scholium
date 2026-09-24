// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Scholium",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ScholiumApp", targets: ["ScholiumApp"]),
        .executable(name: "ScholiumAgentHelper", targets: ["ScholiumAgentHelper"]),
        .library(name: "ScholiumContracts", targets: ["ScholiumContracts"]),
        .library(name: "ScholiumApplication", targets: ["ScholiumApplication"]),
    ],
    dependencies: [
        .package(url: "https://github.com/haplollc/ThinkingOrbs.git", from: "1.1.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0"),
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
            dependencies: [
                "ScholiumContracts", "ScholiumCore",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            path: "ScholiumApplication"
        ),
        .executableTarget(
            name: "ScholiumApp",
            dependencies: [
                "ScholiumContracts",
                "ScholiumApplication",
                .product(name: "ThinkingOrbs", package: "ThinkingOrbs"),
            ],
            path: "Scholium",
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "ScholiumAgentHelper", dependencies: ["ScholiumApplication"], path: "ScholiumAgentHelper"),
        .testTarget(
            name: "ScholiumContractsTests",
            dependencies: ["ScholiumContracts"],
            path: "Tests/ScholiumContractsTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ScholiumCoreTests",
            dependencies: [
                "ScholiumContracts",
                "ScholiumCore",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/ScholiumCoreTests"
        ),
        .testTarget(
            name: "ScholiumPerformanceTests",
            dependencies: [
                "ScholiumContracts",
                "ScholiumCore",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Tests/ScholiumPerformanceTests"
        ),
        .testTarget(
            name: "ScholiumApplicationTests",
            dependencies: ["ScholiumContracts", "ScholiumApplication"],
            path: "Tests/ScholiumApplicationTests"
        ),
        .testTarget(
            name: "ScholiumAppTests",
            dependencies: [
                "ScholiumApp",
                "ScholiumContracts",
                "ScholiumApplication",
            ],
            path: "Tests/ScholiumAppTests"
        ),
    ]
)
