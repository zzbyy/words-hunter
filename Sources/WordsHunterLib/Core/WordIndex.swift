import Foundation

/// Regenerates `__index__.md` at vault root — a glanceable vocabulary dashboard.
///
/// Format: Obsidian callout with emoji stats + status-grouped word lists with [[wiki-links]].
/// Produces identical output to the TypeScript plugin's `word-index.ts`.
/// Called after word capture and on app launch. Errors are silently swallowed (non-critical).
enum WordIndex {

    /// Convenience: reads paths from AppSettings.shared.
    static func regenerate() {
        guard let folderURL = AppSettings.shared.wordsFolderURL else { return }
        let vaultPath = AppSettings.shared.vaultPath
        guard !vaultPath.isEmpty else { return }
        regenerate(folderURL: folderURL, vaultPath: vaultPath)
    }

    /// Core implementation — testable without AppSettings.
    static func regenerate(folderURL: URL, vaultPath: String) {
        // 1. Read mastery.json (read-only — treat as empty if missing/corrupt)
        let mastery = loadMastery(vaultPath: vaultPath)

        // 2. Scan .md files in words folder
        let mdFiles: [URL]
        do {
            mdFiles = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "md" }
        } catch {
            return
        }

        let today = todayString()
        var mastered: [String] = []
        var reviewing: [String] = []
        var learning: [String] = []
        var dueCount = 0

        for file in mdFiles {
            let word = file.deletingPathExtension().lastPathComponent.lowercased()
            guard !word.isEmpty else { continue }

            if let entry = mastery[word] {
                switch entry.status {
                case "mastered": mastered.append(word)
                case "reviewing": reviewing.append(word)
                default: learning.append(word)
                }
                if entry.next_review <= today {
                    dueCount += 1
                }
            } else {
                // No mastery entry — newly captured, treat as learning
                learning.append(word)
            }
        }

        mastered.sort()
        reviewing.sort()
        learning.sort()

        let total = mastered.count + reviewing.count + learning.count
        var lines: [String] = []

        lines.append("> [!summary] 📚 Vocabulary Dashboard")
        lines.append("> **\(total)** words · ✅ **\(mastered.count)** mastered · 🔄 **\(reviewing.count)** reviewing · 🌱 **\(learning.count)** learning · 📋 **\(dueCount)** due today")
        lines.append("")

        if !mastered.isEmpty {
            lines.append("## ✅ Mastered (\(mastered.count))")
            lines.append(mastered.map { "[[\($0)]]" }.joined(separator: " · "))
            lines.append("")
        }

        if !reviewing.isEmpty {
            lines.append("## 🔄 Reviewing (\(reviewing.count))")
            lines.append(reviewing.map { "[[\($0)]]" }.joined(separator: " · "))
            lines.append("")
        }

        if !learning.isEmpty {
            lines.append("## 🌱 Learning (\(learning.count))")
            lines.append(learning.map { "[[\($0)]]" }.joined(separator: " · "))
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        // Write __index__.md at vault root, not inside the words folder
        let vaultURL = URL(fileURLWithPath: vaultPath)
        let indexURL = vaultURL.appendingPathComponent("__index__.md")

        // Atomic write: temp file + move
        let tmpURL = vaultURL.appendingPathComponent(".wh-index-\(UUID().uuidString).tmp")
        do {
            try content.write(to: tmpURL, atomically: false, encoding: .utf8)
            try? FileManager.default.removeItem(at: indexURL)
            try FileManager.default.moveItem(at: tmpURL, to: indexURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    // MARK: - Private

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: Date())
    }

    private static func loadMastery(vaultPath: String) -> [String: MasteryEntry] {
        let url = URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent("mastery.json")
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(MasteryStore.self, from: data)
        else { return [:] }
        return store.words
    }

    private struct MasteryStore: Codable {
        let version: Int
        let words: [String: MasteryEntry]
    }

    struct MasteryEntry: Codable {
        let word: String
        let box: Int
        let status: String
        let next_review: String
        var coaching_mode: String? = nil
        var synonyms: [String]? = nil
        var short_definition: String? = nil
    }
}
