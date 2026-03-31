import Foundation

/// Reads an existing word page, locates lookup-time template variables, fills them with
/// dictionary data, and writes back atomically.
///
/// **Template variables filled here:**
/// - `{{syllables}}` — syllable breakdown (e.g. "po·sit")
/// - `{{pronunciation}}` — IPA string (e.g. "/ˈpɒz.ɪt/")
/// - `{{meanings}}` — numbered meaning blocks from the MW API response
/// - `{{see-also}}` — `[[wikilink]]` lines for related words found in the vault
///
/// Safety checks:
/// - File not found → abort silently (deleted between create and lookup)
/// - No lookup-time variables present → abort silently (old format or user opted out)
/// - Uses FileManager.replaceItem for atomic write (no partial state visible to Obsidian)
enum WordPageUpdater {

    /// Update a word page at `path` with looked-up `content`.
    /// `lemma` is the root form of the word (e.g. "posit"), used for VaultScanner self-exclusion.
    /// Silently aborts if the file is gone or contains no lookup-time variables.
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

        // Guard: abort if no lookup-time variables are present (old format or user opted out)
        let hasLookupVars = text.contains("{{syllables}}") || text.contains("{{pronunciation}}")
            || text.contains("{{meanings}}") || text.contains("{{see-also}}")
        guard hasLookupVars else { return }

        // Scan vault for related words (needed for {{see-also}})
        let scanText = content.definitions.joined(separator: " ")
            + " " + content.examples.joined(separator: " ")
        let relatedWords = VaultScanner.scan(
            definitionText: scanText,
            wordsFolderURL: AppSettings.shared.wordsFolderURL,
            excluding: lemma
        )

        var updated = text

        // Fill {{syllables}} and {{pronunciation}}
        let syllableDisplay = content.headword?
            .replacingOccurrences(of: "*", with: "·") ?? lemma
        let pronunciationDisplay = content.pronunciation.map { "/\($0)/" } ?? ""
        updated = updated.replacingOccurrences(of: "{{syllables}}", with: syllableDisplay)
        updated = updated.replacingOccurrences(of: "{{pronunciation}}", with: pronunciationDisplay)

        // Fill {{meanings}} with numbered blocks (only when definitions are available)
        if updated.contains("{{meanings}}"), let meaningsBlock = buildMeaningsBlock(content: content) {
            updated = updated.replacingOccurrences(of: "{{meanings}}", with: meaningsBlock)
        }

        // Fill {{see-also}} with vault links
        if updated.contains("{{see-also}}") {
            let seeAlsoBlock = relatedWords.isEmpty
                ? "*(no related words found yet)*"
                : relatedWords.map { "- [[\($0)]]" }.joined(separator: "\n")
            updated = updated.replacingOccurrences(of: "{{see-also}}", with: seeAlsoBlock)
        }

        // Atomic write via temp file + replaceItem
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try updated.write(to: tempURL, atomically: false, encoding: .utf8)
        do {
            try FileManager.default.replaceItem(
                at: fileURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly,
                resultingItemURL: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - Private helpers

    /// Builds the numbered meaning blocks from dictionary content.
    /// Returns nil when `content.definitions` is empty (no data to fill).
    private static func buildMeaningsBlock(content: DictionaryContent) -> String? {
        guard !content.definitions.isEmpty else { return nil }
        let pos = content.pos ?? ""
        var blocks: [String] = []
        for (index, def) in content.definitions.enumerated() {
            let num = index + 1
            let example = index < content.examples.count ? content.examples[index] : ""
            var block = "\n### \(num). (\(pos)) *(\(def))*\n"
            block += "\n> *(\(example))*\n"
            block += "\n**My sentence:**\n- \n"
            block += "\n**Patterns:**\n- *(common word combinations and grammar patterns)*"
            blocks.append(block)
        }
        return blocks.joined(separator: "\n\n") + "\n\n---\n"
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
