import Foundation

/// Reads an existing word page, locates lookup-time template variables, fills them with
/// dictionary data, and writes back atomically.
///
/// **Template variables filled here:**
/// - `{{pronunciation-bre}}` — British English IPA (e.g. "/ˈdelɪɡət/")
/// - `{{pronunciation-ame}}` — American English IPA (e.g. "/ˈdelɪɡət/")
/// - `{{cefr}}` — CEFR level badge (e.g. "B2")
/// - `{{meanings}}` — numbered meaning blocks with CEFR per sense and extra examples
/// - `{{corpus-examples}}` — real-world usage from the Cambridge English Corpus
/// - `{{when-to-use}}` — register/domain labels per sense (formal, informal, specialized…)
/// - `{{word-family}}` — related word forms from the Cambridge word family box
/// - `{{collocations}}` — collocation groups (adjective, verb +, etc.) [legacy]
/// - `{{nearby-words}}` — nearby dictionary words with POS [legacy]
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

        // Fill {{meanings}} — Cambridge-style: definition as heading, patterns, bolded examples
        if updated.contains("{{meanings}}"), let meaningsBlock = buildMeaningsBlock(content: content, lemma: lemma) {
            updated = updated.replacingOccurrences(of: "{{meanings}}", with: meaningsBlock)
        }

        // Fill {{corpus-examples}}
        if updated.contains("{{corpus-examples}}") {
            let corpusBlock = buildCorpusExamplesBlock(content: content, lemma: lemma)
            updated = updated.replacingOccurrences(of: "{{corpus-examples}}", with: corpusBlock)
        }

        // Fill legacy {{collocations}} (Oxford/MW fallback — empty for Cambridge)
        if updated.contains("{{collocations}}") {
            let collocBlock = buildCollocationsBlock(content: content)
            updated = updated.replacingOccurrences(of: "{{collocations}}", with: collocBlock)
        }

        // Fill legacy {{nearby-words}} (Oxford fallback — empty for Cambridge)
        if updated.contains("{{nearby-words}}") {
            let nearbyBlock = buildNearbyWordsBlock(content: content)
            updated = updated.replacingOccurrences(of: "{{nearby-words}}", with: nearbyBlock)
        }

        // Fill {{when-to-use}}
        if updated.contains("{{when-to-use}}") {
            updated = updated.replacingOccurrences(of: "{{when-to-use}}", with: buildWhenToUseBlock(content: content))
        }

        // Fill {{word-family}}
        if updated.contains("{{word-family}}") {
            updated = updated.replacingOccurrences(of: "{{word-family}}", with: buildWordFamilyBlock(content: content))
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

    /// Builds definition blocks in the Cambridge learner format:
    ///   ### Definition text · [grammar] · CEFR
    ///   - **Patterns**: `pattern`
    ///   - example with **word** bolded
    private static func buildMeaningsBlock(content: DictionaryContent, lemma: String) -> String? {
        let allSenses = content.entries.flatMap { entry in
            entry.senses.map { (entry.pos, $0) }
        }
        guard !allSenses.isEmpty else { return nil }

        var blocks: [String] = []
        for (_, sense) in allSenses {
            var heading = sense.definition

            // Append grammar and CEFR to heading
            if let grammar = sense.grammar, !grammar.isEmpty {
                heading += " · \(grammar)"
            }
            if let cefr = sense.cefrLevel {
                heading += " · \(cefr)"
            }

            var block = "\n### \(heading)\n\n"

            // Patterns
            if !sense.patterns.isEmpty {
                block += "- **Patterns**:\n"
                for pattern in sense.patterns {
                    block += "  - `\(pattern)`\n"
                }
            }

            // Examples with bolded lemma forms
            for example in sense.examples {
                block += "- \(boldLemma(example, lemma: lemma))\n"
            }

            // Extra examples (Oxford / accordion)
            for extra in sense.extraExamples {
                block += "- \(boldLemma(extra, lemma: lemma))\n"
            }

            blocks.append(block)
        }

        return blocks.joined(separator: "\n---\n") + "\n\n---\n"
    }

    // MARK: - Corpus examples block builder

    private static func buildCorpusExamplesBlock(content: DictionaryContent, lemma: String) -> String {
        guard !content.corpusExamples.isEmpty else {
            return "*(no corpus examples available)*"
        }
        return content.corpusExamples
            .map { "- \(boldLemma($0, lemma: lemma))" }
            .joined(separator: "\n")
    }

    // MARK: - Bold lemma helper

    /// Bolds all surface forms of `lemma` in `text` (e.g. delegate → delegates, delegated).
    private static func boldLemma(_ text: String, lemma: String) -> String {
        guard !lemma.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: lemma)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\(escaped)\\w*)",
            options: .caseInsensitive
        ) else { return text }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text
        // Reverse order so replacement offsets stay valid
        let matches = regex.matches(in: text, range: range).reversed()
        for match in matches {
            guard let swiftRange = Range(match.range(at: 1), in: result) else { continue }
            let word = String(result[swiftRange])
            result.replaceSubrange(swiftRange, with: "**\(word)**")
        }
        return result
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

    // MARK: - When to Use block builder

    /// Builds the "When to Use" content from register/domain labels scraped per sense.
    /// If no labels are found, falls back to manual prompts so the section remains useful.
    private static func buildWhenToUseBlock(content: DictionaryContent) -> String {
        // Collect unique, non-empty register labels across all senses
        var seen = Set<String>()
        var labels: [String] = []
        for entry in content.entries {
            for sense in entry.senses {
                if let reg = sense.register, !reg.isEmpty, seen.insert(reg.lowercased()).inserted {
                    labels.append(reg)
                }
            }
        }

        if !labels.isEmpty {
            return "**Register:** \(labels.joined(separator: ", "))\n"
        }
        // Fallback: preserve the manual prompts from the original template
        return "**Where it fits:**\n**In casual speech:**\n"
    }

    // MARK: - Word Family block builder

    /// Builds the "Word Family" list from Cambridge's word family box.
    /// Falls back to a manual note if no data was scraped.
    private static func buildWordFamilyBlock(content: DictionaryContent) -> String {
        guard !content.wordFamily.isEmpty else {
            return "*(no word family data found — add related forms manually)*\n"
        }
        return content.wordFamily.map { entry in
            let posLabel = entry.partsOfSpeech.isEmpty ? "" : " — \(entry.partsOfSpeech.joined(separator: ", "))"
            return "- **\(entry.word)**\(posLabel)"
        }.joined(separator: "\n") + "\n"
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
