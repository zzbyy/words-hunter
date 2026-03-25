// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordsHunter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "WordsHunterLib",
            path: "Sources/WordsHunterLib"
        ),
        .executableTarget(
            name: "WordsHunter",
            dependencies: ["WordsHunterLib"],
            path: "Sources/WordsHunter"
        ),
        .testTarget(
            name: "WordsHunterTests",
            dependencies: ["WordsHunterLib"],
            path: "Tests/WordsHunterTests"
        )
    ]
)
