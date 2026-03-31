import Foundation

/// Reads an existing word page, locates lookup-time template variables, fills them with
/// dictionary data, and writes back atomically.
///
/// **Template variables filled here:**
/// - `{{pronunciation-bre}}` — British English IPA (e.g. "/ˈdelɪɡət/")
/// - `{{pronunciation-ame}}` — American English IPA (e.g. "/ˈdelɪɡət/")
/// - `{{cefr}}` — CEFR level badge (e.g. "B2")
/// - `{{meanings}}` — numbered meaning blocks with CEFR per sense and extra examples
/// - `{{collocations}}` — collocation groups (adjective, verb +, etc.)
/// - `{{nearby-words}}` — nearby dictionary words with POS
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

        // Guard: abort if no lookup-time variables are present
        let hasLookupVars = WordPageCreator.allLookupVariables.contains { text.contains($0) }
        guard hasLookupVars else { return }

        // Scan vault for related words (needed for {{see-also}})
        let allDefinitions = content.entries.flatMap { $0.senses.map { $0.definition } }
        let allExamples = content.entries.flatMap { $0.senses.flatMap { $0.examples } }
        let scanText = (allDefinitions + allExamples).joined(separator: " ")
        let relatedWords = VaultScanner.scan(
            definitionText: scanText,
            wordsFolderURL: AppSettings.shared.wordsFolderURL,
            excluding: lemma
        )

        var updated = text

        // Fill {{pronunciation-bre}} and {{pronunciation-ame}}
        let brePron = content.pronunciationBrE ?? ""
        let amePron = content.pronunciationAmE ?? ""
        updated = updated.replacingOccurrences(of: "{{pronunciation-bre}}", with: brePron)
        updated = updated.replacingOccurrences(of: "{{pronunciation-ame}}", with: amePron)

        // Fill {{cefr}} — use the highest-level CEFR from entries
        if updated.contains("{{cefr}}") {
            let cefrLevel = extractBestCEFR(from: content)
            updated = updated.replacingOccurrences(of: "{{cefr}}", with: cefrLevel)
        }

        // Fill {{meanings}} with numbered blocks (grouped by POS)
        if updated.contains("{{meanings}}"), let meaningsBlock = buildMeaningsBlock(content: content) {
            updated = updated.replacingOccurrences(of: "{{meanings}}", with: meaningsBlock)
        }

        // Fill {{collocations}}
        if updated.contains("{{collocations}}") {
            let collocBlock = buildCollocationsBlock(content: content)
            updated = updated.replacingOccurrences(of: "{{collocations}}", with: collocBlock)
        }

        // Fill {{nearby-words}}
        if updated.contains("{{nearby-words}}") {
            let nearbyBlock = buildNearbyWordsBlock(content: content)
            updated = updated.replacingOccurrences(of: "{{nearby-words}}", with: nearbyBlock)
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

    // MARK: - Meanings block builder

    /// Builds the numbered meaning blocks from dictionary content, grouped by POS.
    /// Each sense includes CEFR level, definition, examples, and extra examples.
    /// Returns nil when no definitions are found.
    private static func buildMeaningsBlock(content: DictionaryContent) -> String? {
        let allSenses = content.entries.flatMap { entry in
            entry.senses.map { (entry.pos, $0) }
        }
        guard !allSenses.isEmpty else { return nil }

        var blocks: [String] = []
        for (index, (pos, sense)) in allSenses.enumerated() {
            let num = index + 1
            let posLabel = pos ?? ""
            let cefrBadge = sense.cefrLevel.map { " `\($0)`" } ?? ""

            var block = "\n### \(num). (\(posLabel)) *(\(sense.definition))*\(cefrBadge)\n"

            // Inline examples
            if !sense.examples.isEmpty {
                for example in sense.examples {
                    block += "\n> *\(example)*\n"
                }
            } else {
                block += "\n> *()*\n"
            }

            // Extra examples
            if !sense.extraExamples.isEmpty {
                block += "\n**Extra examples:**\n"
                for extra in sense.extraExamples {
                    block += "- *\(extra)*\n"
                }
            }

            block += "\n**My sentence:**\n- \n"
            block += "\n**Patterns:**\n- *(common word combinations and grammar patterns)*"
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n") + "\n\n---\n"
    }

    // MARK: - Collocations block builder

    /// Builds the collocations section from grouped collocation data.
    private static func buildCollocationsBlock(content: DictionaryContent) -> String {
        let allCollocations = content.entries.flatMap { $0.collocations }
        guard !allCollocations.isEmpty else {
            return "*(no collocations available)*"
        }

        var lines: [String] = []
        for group in allCollocations {
            lines.append("**\(group.label):**")
            let itemList = group.items.map { "· \($0)" }.joined(separator: " ")
            lines.append(itemList)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Nearby words block builder

    /// Builds the nearby words section from nearby word data.
    private static func buildNearbyWordsBlock(content: DictionaryContent) -> String {
        guard !content.nearbyWords.isEmpty else {
            return "*(no nearby words available)*"
        }

        return content.nearbyWords.map { nearby in
            let posLabel = nearby.pos.map { " *\($0)*" } ?? ""
            return "- \(nearby.word)\(posLabel)"
        }.joined(separator: "\n")
    }

    // MARK: - CEFR helpers

    /// Extract the best (most common) CEFR level from the content.
    /// Prefers word-level CEFR from entries, falls back to sense-level.
    private static func extractBestCEFR(from content: DictionaryContent) -> String {
        // Try entry-level CEFR first
        for entry in content.entries {
            if let level = entry.cefrLevel { return level }
        }
        // Fall back to first sense-level CEFR
        for entry in content.entries {
            for sense in entry.senses {
                if let level = sense.cefrLevel { return level }
            }
        }
        return "—"
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
