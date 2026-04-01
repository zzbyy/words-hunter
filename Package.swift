// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordsHunter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.11.3")
    ],
    targets: [
        .target(
            name: "WordsHunterLib",
            dependencies: ["SwiftSoup"],
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
