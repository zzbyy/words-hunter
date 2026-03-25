// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordsHunter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WordsHunter",
            path: "Sources/WordsHunter"
        )
    ]
)
