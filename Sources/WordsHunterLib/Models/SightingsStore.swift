import Foundation

// MARK: - v2 Types

struct SightingEvent: Codable {
    let timestamp: String           // "2026-04-04T21:15"
    let channel: String?            // nil → omitted from JSON
    let words: [String: String]     // word → sentence ("" if no sentence captured)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(channel, forKey: .channel)
        try container.encode(words, forKey: .words)
    }
}

struct SightingsStoreData: Codable {
    let version: Int                // always 2
    var days: [String: [SightingEvent]]
}

// MARK: - v1 Types (migration only)

private struct SightingEntryV1: Codable {
    let date: String
    let sentence: String
    let channel: String?
}

private struct SightingsStoreV1: Codable {
    let version: Int
    var days: [String: [String: [SightingEntryV1]]]
}

// MARK: - Version detection

private struct VersionOnly: Codable {
    let version: Int
}

// MARK: - File I/O

/// Manages `{vault}/.wordshunter/sightings.json` — the centralized sighting store
/// shared between the macOS app, the Windows app, and the OpenClaw plugin.
enum SightingsFile {

    static func sightingsURL(vaultPath: String) -> URL {
        URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent("sightings.json")
    }

    /// Read and decode the sightings store. Transparently migrates v1 → v2.
    /// Returns nil if the file is missing or has an unknown version.
    static func read(vaultPath: String) -> SightingsStoreData? {
        let fileURL = sightingsURL(vaultPath: vaultPath)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        // Peek at version to decide how to decode
        guard let versionInfo = try? JSONDecoder().decode(VersionOnly.self, from: data) else {
            return nil
        }

        switch versionInfo.version {
        case 2:
            return try? JSONDecoder().decode(SightingsStoreData.self, from: data)
        case 1:
            guard let v1 = try? JSONDecoder().decode(SightingsStoreV1.self, from: data) else {
                return nil
            }
            return migrateV1ToV2(v1)
        default:
            return nil
        }
    }

    /// Write the store atomically via temp+rename. Auto-prunes days older than 30.
    static func write(_ store: SightingsStoreData, vaultPath: String) throws {
        var pruned = store
        pruneOldDays(&pruned)

        let fileURL = sightingsURL(vaultPath: vaultPath)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(pruned)

        let tmp = dir.appendingPathComponent(
            ".sightings-\(ProcessInfo.processInfo.globallyUniqueString).json.tmp"
        )
        try data.write(to: tmp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            _ = try? fm.removeItem(at: fileURL)
        }
        try fm.moveItem(at: tmp, to: fileURL)
    }

    /// Record a single sighting. Best-effort — failures are silently ignored.
    static func recordSighting(
        word: String, sentence: String, channel: String?,
        vaultPath: String
    ) {
        let today = todayString()
        let event = SightingEvent(
            timestamp: nowTimestamp(),
            channel: channel,
            words: [word.lowercased(): sentence]
        )

        var store = read(vaultPath: vaultPath)
            ?? SightingsStoreData(version: 2, days: [:])

        var dayEvents = store.days[today] ?? []
        dayEvents.append(event)
        store.days[today] = dayEvents

        try? write(store, vaultPath: vaultPath)
    }

    // MARK: - Migration

    /// Convert v1 store to v2 event-based format.
    /// Groups entries by (date, channel) and coalesces words into one event.
    private static func migrateV1ToV2(_ v1: SightingsStoreV1) -> SightingsStoreData {
        var v2Days: [String: [SightingEvent]] = [:]

        for (date, wordMap) in v1.days {
            // Group by channel to coalesce entries
            var channelWords: [String?: [String: String]] = [:]
            for (word, entries) in wordMap {
                for entry in entries {
                    var words = channelWords[entry.channel] ?? [:]
                    words[word] = entry.sentence
                    channelWords[entry.channel] = words
                }
            }
            var events: [SightingEvent] = []
            for (channel, words) in channelWords {
                events.append(SightingEvent(
                    timestamp: date + "T00:00",
                    channel: channel,
                    words: words
                ))
            }
            v2Days[date] = events
        }

        return SightingsStoreData(version: 2, days: v2Days)
    }

    // MARK: - Pruning

    /// Remove days older than 30 days from today.
    private static func pruneOldDays(_ store: inout SightingsStoreData) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return
        }
        let cutoffString = fmt.string(from: cutoff)
        store.days = store.days.filter { $0.key >= cutoffString }
    }

    // MARK: - Helpers

    /// Returns today's date as YYYY-MM-DD.
    internal static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date())
    }

    /// Returns current time as "YYYY-MM-DDTHH:mm".
    internal static func nowTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date())
    }
}
