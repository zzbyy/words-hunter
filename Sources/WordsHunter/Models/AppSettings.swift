import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let vaultPath = "vaultPath"
        static let wordFolder = "wordFolder"
        static let isSetupComplete = "isSetupComplete"
    }

    var vaultPath: String {
        get { defaults.string(forKey: Key.vaultPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.vaultPath) }
    }

    var wordFolder: String {
        get { defaults.string(forKey: Key.wordFolder) ?? "Words" }
        set { defaults.set(newValue, forKey: Key.wordFolder) }
    }

    var isSetupComplete: Bool {
        get { defaults.bool(forKey: Key.isSetupComplete) }
        set { defaults.set(newValue, forKey: Key.isSetupComplete) }
    }

    var wordsFolderURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(wordFolder)
    }

    private init() {}
}
