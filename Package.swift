// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexSkillManager",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "CodexSkillManager",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/CodexSkillManager",
            swiftSettings: [
                .define("ENABLE_SPARKLE"),
                .unsafeFlags(["-default-isolation", "MainActor"]),
                .unsafeFlags(["-strict-concurrency=complete"]),
                .unsafeFlags(["-warn-concurrency"]),
            ])
    ]
)
