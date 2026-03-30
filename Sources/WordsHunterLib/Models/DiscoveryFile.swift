import Foundation

/// Shared discovery config between the macOS app and the OpenClaw plugin.
/// Both sides read and write this file atomically.
struct DiscoveryConfig: Codable {
    var version: Int
    var words_directory: String
    var words_folder: String
    var updated_by: String
    var updated_at: String
}

/// Manages ~/Library/Application Support/WordsHunter/discovery.json.
///
/// This file is the bridge between the Words Hunter macOS app and the OpenClaw
/// TypeScript plugin. Whichever is configured first writes the discovery file;
/// the other reads it on startup and auto-fills its configuration.
enum DiscoveryFile {

    /// ~/Library/Application Support/WordsHunter/discovery.json
    static var url: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport
            .appendingPathComponent("WordsHunter")
            .appendingPathComponent("discovery.json")
    }

    /// Write the discovery file atomically (temp+rename).
    /// Called each time the user saves settings in SetupWindow.
    static func write(wordsDirectory: String, wordsFolder: String) {
        guard !wordsDirectory.isEmpty else { return }
        let config = DiscoveryConfig(
            version: 1,
            words_directory: wordsDirectory,
            words_folder: wordsFolder,
            updated_by: "app",
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        guard let data = try? JSONEncoder().encode(config) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(
            ".discovery-\(ProcessInfo.processInfo.globallyUniqueString).json.tmp"
        )
        guard (try? data.write(to: tmp, options: .atomic)) != nil else { return }
        try? FileManager.default.moveItem(at: tmp, to: url)
    }

    /// Read the discovery file.
    /// Returns nil if the file is missing, has an unknown version, or the
    /// words_directory no longer exists on disk.
    static func read() -> DiscoveryConfig? {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(DiscoveryConfig.self, from: data),
              config.version == 1,
              !config.words_directory.isEmpty
        else { return nil }

        // Validate the directory still exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
                atPath: config.words_directory, isDirectory: &isDir),
              isDir.boolValue
        else { return nil }

        return config
    }
}
