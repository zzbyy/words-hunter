import Foundation

/// Scans a words folder for .md files whose lemma appears as a whole word
/// in a given definition text. Used by WordPageUpdater to auto-populate
/// the Linked words section at page creation time.
enum VaultScanner {

    /// Returns sorted lemmas from `wordsFolderURL` whose filenames appear as
    /// whole words in `definitionText`, excluding `excluding` (the word being created).
    /// Returns [] on any error, including nil `wordsFolderURL`.
    static func scan(definitionText: String, wordsFolderURL: URL?, excluding: String) -> [String] {
        guard let folderURL = wordsFolderURL else { return [] }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let excludedLemma = excluding.lowercased()
        var matches: [String] = []

        for file in files {
            guard file.pathExtension == "md" else { continue }
            let lemma = file.deletingPathExtension().lastPathComponent.lowercased()
            guard !lemma.isEmpty, lemma != excludedLemma, lemma != "index" else { continue }

            // Whole-word match: \b{lemma}\b, case-insensitive
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: lemma))\\b",
                options: .caseInsensitive
            ) else { continue }

            let range = NSRange(definitionText.startIndex..., in: definitionText)
            if regex.firstMatch(in: definitionText, range: range) != nil {
                matches.append(lemma)
            }
        }

        return matches.sorted()
    }
}
