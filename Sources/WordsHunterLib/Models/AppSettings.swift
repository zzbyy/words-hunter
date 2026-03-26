import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    private enum Key {
        static let vaultPath = "vaultPath"
        static let wordFolder = "wordFolder"
        static let isSetupComplete = "isSetupComplete"
        static let useWordFolder = "useWordFolder"
        static let lookupEnabled = "lookupEnabled"
        static let lookupRetries = "lookupRetries"
        static let mwApiKey = "mwApiKey"
    }

    // MARK: - Vault

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

    // MARK: - Subfolder toggle

    /// Whether word pages are saved inside a subfolder (e.g. Words/) within the vault.
    /// Existing installs default true (preserve behavior); new installs default false (vault root).
    var useWordFolder: Bool {
        get { defaults.bool(forKey: Key.useWordFolder) }
        set { defaults.set(newValue, forKey: Key.useWordFolder) }
    }

    /// URL where word pages are written.
    /// When useWordFolder is false: vault root. When true: vault/wordFolder.
    var wordsFolderURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        let vaultURL = URL(fileURLWithPath: vaultPath)
        return useWordFolder ? vaultURL.appendingPathComponent(wordFolder) : vaultURL
    }

    // MARK: - Dictionary lookup

    /// Whether auto-lookup is enabled. Off by default.
    /// The toggle lets users disable lookup without losing their API key — intentional redundancy.
    var lookupEnabled: Bool {
        get { defaults.bool(forKey: Key.lookupEnabled) }
        set { defaults.set(newValue, forKey: Key.lookupEnabled) }
    }

    /// Number of *additional* retry attempts after the first. Default 3 → 4 total attempts.
    /// Range 1–5. Backoff: immediate → 1s → 2s → 4s → …
    var lookupRetries: Int {
        get {
            let stored = defaults.integer(forKey: Key.lookupRetries)
            return stored == 0 ? 3 : stored   // 0 means key absent; treat as default 3
        }
        set { defaults.set(max(1, min(5, newValue)), forKey: Key.lookupRetries) }
    }

    /// Merriam-Webster API key, stored in UserDefaults.
    var mwApiKey: String {
        get { defaults.string(forKey: Key.mwApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.mwApiKey) }
    }

    // MARK: - Init

    /// Designated init. Uses UserDefaults.standard in production.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        runMigrationIfNeeded()
    }

    // MARK: - Migration guard
    //
    // Existing installs: isSetupComplete=true AND useWordFolder key is absent.
    // We preserve their behavior by defaulting useWordFolder to true.
    // New installs: isSetupComplete=false, so useWordFolder stays false (vault root).
    // After migration the key is present and this never re-runs.
    private func runMigrationIfNeeded() {
        guard isSetupComplete,
              defaults.object(forKey: Key.useWordFolder) == nil
        else { return }
        defaults.set(true, forKey: Key.useWordFolder)
    }
}
