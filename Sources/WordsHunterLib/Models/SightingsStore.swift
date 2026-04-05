import Foundation

// MARK: - Types

struct SightingEntry: Codable {
    let date: String        // YYYY-MM-DD
    let sentence: String
    let channel: String?    // omitted from JSON when nil

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(sentence, forKey: .sentence)
        try container.encodeIfPresent(channel, forKey: .channel)
    }
}

struct SightingsStore: Codable {
    let version: Int        // always 1
    var days: [String: [String: [SightingEntry]]]
    // days["2026-04-04"]["deliberate"] = [SightingEntry]
}

// MARK: - File I/O

/// Manages `{vault}/.wordshunter/sightings.json` — the centralized sighting store
/// shared between the macOS app, the Windows app, and the OpenClaw plugin.
///
/// Locking uses mkdir-based mutual exclusion, compatible with the npm `proper-lockfile`
/// package used by the TypeScript plugin.
enum SightingsFile {

    static func url(vaultPath: String) -> URL {
        URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent("sightings.json")
    }

    static func lockURL(vaultPath: String) -> URL {
        URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent(".sightings.lock")
    }

    /// Read and decode the sightings store. Returns nil if the file is missing or
    /// has an unknown version.
    static func read(vaultPath: String) -> SightingsStore? {
        let fileURL = url(vaultPath: vaultPath)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let store = try? JSONDecoder().decode(SightingsStore.self, from: data),
              store.version == 1
        else { return nil }
        return store
    }

    /// Write the store atomically via temp+rename.
    static func write(_ store: SightingsStore, vaultPath: String) throws {
        let fileURL = url(vaultPath: vaultPath)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(store)

        let tmp = dir.appendingPathComponent(
            ".sightings-\(ProcessInfo.processInfo.globallyUniqueString).json.tmp"
        )
        try data.write(to: tmp, options: .atomic)
        // Atomic rename — if the target already exists, remove it first (POSIX rename
        // replaces atomically, but Foundation's moveItem may not on all versions).
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            _ = try? fm.removeItem(at: fileURL)
        }
        try fm.moveItem(at: tmp, to: fileURL)
    }

    /// Record a single sighting with lock protection.
    /// Best-effort: failures are silently ignored by the caller.
    static func recordSighting(
        word: String, sentence: String, channel: String?,
        vaultPath: String
    ) {
        guard acquireLock(vaultPath: vaultPath) else { return }
        defer { releaseLock(vaultPath: vaultPath) }

        let today = Self.todayString()
        let entry = SightingEntry(date: today, sentence: sentence, channel: channel)

        var store = read(vaultPath: vaultPath)
            ?? SightingsStore(version: 1, days: [:])

        let key = word.lowercased()
        var dayBucket = store.days[today] ?? [:]
        var entries = dayBucket[key] ?? []
        entries.append(entry)
        dayBucket[key] = entries
        store.days[today] = dayBucket

        try? write(store, vaultPath: vaultPath)
    }

    // MARK: - Locking (mkdir-based, compatible with proper-lockfile)

    /// Acquire a lock by creating a directory. `mkdir` is atomic on POSIX — if the
    /// directory already exists, `createDirectory(withIntermediateDirectories: false)`
    /// throws, which we treat as "lock held by another process".
    private static func acquireLock(vaultPath: String) -> Bool {
        let lockDir = lockURL(vaultPath: vaultPath)
        let fm = FileManager.default

        for attempt in 0..<10 {
            do {
                try fm.createDirectory(at: lockDir, withIntermediateDirectories: false)
                return true // acquired
            } catch {
                // Check for stale lock (mtime > 10s ago)
                if let attrs = try? fm.attributesOfItem(atPath: lockDir.path),
                   let mtime = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(mtime) > 10
                {
                    try? fm.removeItem(at: lockDir)
                    continue // retry immediately after stale removal
                }
                // Exponential backoff: 100ms * 2^attempt, capped at ~1.6s
                let delay = min(0.1 * pow(2.0, Double(attempt)), 1.6)
                Thread.sleep(forTimeInterval: delay)
            }
        }
        return false
    }

    private static func releaseLock(vaultPath: String) {
        try? FileManager.default.removeItem(at: lockURL(vaultPath: vaultPath))
    }

    // MARK: - Helpers

    /// Returns today's date as YYYY-MM-DD.
    internal static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date())
    }
}
