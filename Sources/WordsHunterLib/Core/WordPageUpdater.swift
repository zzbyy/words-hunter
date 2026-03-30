import Foundation

/// Reads an existing word page, checks that the Meanings section is still unedited,
/// fills in callout (headword + pronunciation), numbered meaning blocks, and See Also links,
/// then writes back atomically.
///
/// Safety checks:
/// - File not found → abort silently (deleted between create and lookup)
/// - Old format (no `> [!info]` callout) → abort silently (no migration)
/// - Meanings placeholder already edited → abort silently (no clobbering)
/// - Uses FileManager.replaceItem for atomic write (no partial state visible to Obsidian)
enum WordPageUpdater {

    /// Update a word page at `path` with looked-up `content`.
    /// `lemma` is the root form of the word (e.g. "posit"), used for VaultScanner self-exclusion.
    /// Silently aborts if the file is gone, uses the old template format, or the user has already edited Meanings.
    static func update(at path: String, with content: DictionaryContent, lemma: String) throws {
        let fileURL = URL(fileURLWithPath: path)

        // Guard: file may have been deleted between createPage and this call
        guard FileManager.default.fileExists(atPath: path) else { return }

        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return  // unreadable — abort silently
        }

        // Guard: page must have the Syllables/Pronunciation header line
        guard text.contains("**Syllables:**") else { return }

        // Guard: abort if user has already edited the first meaning placeholder
        guard text.contains("### 1. () *()*") else { return }

        // Scan vault for related words
        let scanText = content.definitions.joined(separator: " ")
            + " " + content.examples.joined(separator: " ")
        let relatedWords = VaultScanner.scan(
            definitionText: scanText,
            wordsFolderURL: AppSettings.shared.wordsFolderURL,
            excluding: lemma
        )

        var updated = text

        // Fill Syllables/Pronunciation header line
        let syllableDisplay = content.headword?
            .replacingOccurrences(of: "*", with: "·") ?? lemma
        let pronunciationDisplay = content.pronunciation.map { "/\($0)/" } ?? ""
        var lines = updated.components(separatedBy: "\n")
        if let idx = lines.firstIndex(where: { $0.hasPrefix("**Syllables:**") }) {
            lines[idx] = "**Syllables:** \(syllableDisplay) · **Pronunciation:** \(pronunciationDisplay)"
        }
        updated = lines.joined(separator: "\n")

        // Build numbered meaning blocks from all definitions
        let pos = content.pos ?? ""
        var meaningBlocks: [String] = []
        for (index, def) in content.definitions.enumerated() {
            let num = index + 1
            let example = index < content.examples.count ? content.examples[index] : ""
            var block = "### \(num). (\(pos)) *(\(def))*\n"
            block += "\n> *(\(example))*\n"
            block += "\n**My sentence:**\n- \n"
            block += "\n**Patterns:**\n- *(common word combinations and grammar patterns)*"
            meaningBlocks.append(block)
        }
        let meaningsReplacement = "\n" + meaningBlocks.joined(separator: "\n\n") + "\n\n---\n"
        if let afterMeanings = replaceSection(named: "Meanings", in: updated, with: meaningsReplacement) {
            updated = afterMeanings
        }

        // Fill See Also with related words from vault scan
        if !relatedWords.isEmpty {
            let linkedText = relatedWords.map { "- [[\($0)]]" }.joined(separator: "\n")
            if let afterLinked = replaceSection(named: "See Also", in: updated, with: "\n\(linkedText)\n\n---\n") {
                updated = afterLinked
            }
        }

        // Atomic write via temp file + replaceItem
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try updated.write(to: tempURL, atomically: false, encoding: .utf8)
        try FileManager.default.replaceItem(
            at: fileURL,
            withItemAt: tempURL,
            backupItemName: nil,
            options: .usingNewMetadataOnly,
            resultingItemURL: nil
        )
    }

    // MARK: - Generic section helpers

    /// Returns the body text between `## {name}\n` and the next `## ` heading (or end of file).
    /// Returns nil if the section header is not found.
    static func extractSectionBody(named name: String, from text: String) -> String? {
        guard let headerRange = text.range(of: "## \(name)\n") else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            return String(afterHeader[..<nextHeadingRange.lowerBound])
        } else {
            return String(afterHeader)
        }
    }

    /// Replaces the body of section `## {name}` (up to the next `## ` heading) with `replacement`.
    /// `replacement` should include leading and trailing newlines as needed.
    /// Returns nil if the section header is not found.
    static func replaceSection(named name: String, in text: String, with replacement: String) -> String? {
        guard let headerRange = text.range(of: "## \(name)\n") else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        let newContent = "## \(name)\n\(replacement)"
        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            let before = text[..<headerRange.lowerBound]
            let after = text[nextHeadingRange.lowerBound...]
            return String(before) + newContent + String(after)
        } else {
            let before = text[..<headerRange.lowerBound]
            return String(before) + newContent
        }
    }
}
