import Foundation

/// Reads an existing word page, checks that auto-filled sections are still empty,
/// and writes all populated sections back in a single atomic operation.
///
/// Sections auto-filled (in one write):
///   1. {POS} placeholder in the header → replaced with MW `fl` value
///   2. ## Pronunciation → MW `hwi.prs[0].mw` pronunciation notation
///   3. ## Definition → numbered list of definitions
///   4. ## Related Words → `[[backlink]]` list from vault scan
///
/// Safety checks (per section):
///   - File not found → abort silently (deleted between create and lookup)
///   - Section already contains user text → skip that section (no clobbering)
///   - All writes happen in a single atomic file operation (no partial state)
enum WordPageUpdater {

    // MARK: - Public API

    /// Update all auto-filled sections of the word page at `path`.
    /// Reads once, applies all transforms, writes back atomically.
    /// Silently skips any section the user has already written to.
    static func updatePage(at path: String, with content: DictionaryContent) throws {
        let fileURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else { return }

        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return  // unreadable — abort silently
        }

        var updated = text

        // 1. POS: replace {POS} placeholder in header
        if let pos = content.partOfSpeech, !pos.isEmpty {
            updated = updated.replacingOccurrences(of: "{POS}", with: pos)
        }

        // 2. Pronunciation: fill if section is empty
        if let pronunciation = content.pronunciation, !pronunciation.isEmpty {
            updated = fillSection(
                header: "## Pronunciation",
                body: pronunciation,
                in: updated
            ) ?? updated
        }

        // 3. Definition: fill if section is empty
        if !content.definitions.isEmpty {
            let formatted = content.definitions
                .enumerated()
                .map { i, def in "\(i + 1). \(def)" }
                .joined(separator: "\n")
            updated = fillSection(
                header: "## Definition",
                body: formatted,
                in: updated
            ) ?? updated
        }

        // 4. Related Words: fill if section is empty
        if !content.relatedWords.isEmpty {
            let links = content.relatedWords.map { "[[\($0)]]" }.joined(separator: " ")
            updated = fillSection(
                header: "## Related Words",
                body: links,
                in: updated
            ) ?? updated
        }

        // Skip write if nothing changed
        guard updated != text else { return }

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

    /// Convenience alias for backward compatibility with call sites that use the old name.
    static func updateDefinition(at path: String, with content: DictionaryContent) throws {
        try updatePage(at: path, with: content)
    }

    // MARK: - Helpers

    /// Fills `header`'s section body with `body` if the section is currently whitespace-only.
    /// Returns the modified text, or nil if the section was not found or already has content.
    private static func fillSection(header: String, body: String, in text: String) -> String? {
        guard let sectionBody = extractSectionBody(header: header, from: text) else { return nil }
        guard sectionBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let replacement = "\(header)\n\n\(body)\n\n"
        return replaceSectionBody(header: header, in: text, with: replacement)
    }

    /// Returns the text between `\(header)\n` and the next `## ` heading (or end of file).
    private static func extractSectionBody(header: String, from text: String) -> String? {
        guard let headerRange = text.range(of: "\(header)\n") else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            return String(afterHeader[..<nextHeadingRange.lowerBound])
        } else {
            return String(afterHeader)
        }
    }

    /// Replaces the `header` section (up to next `## ` heading) with `replacement`.
    private static func replaceSectionBody(header: String, in text: String, with replacement: String) -> String? {
        guard let headerRange = text.range(of: "\(header)\n") else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            let before = text[..<headerRange.lowerBound]
            let after = text[nextHeadingRange.lowerBound...]
            return before + replacement + after
        } else {
            let before = text[..<headerRange.lowerBound]
            return before + replacement
        }
    }
}
