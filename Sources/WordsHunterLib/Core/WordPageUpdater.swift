import Foundation

/// Reads an existing word page, checks that Definition and Examples sections are still empty,
/// patches frontmatter (pos, pronunciation), fills Definition, Examples, and Linked words,
/// then writes back atomically.
///
/// Safety checks:
/// - File not found → abort silently (deleted between create and lookup)
/// - Definition or Examples section already contains user text → abort silently (no clobbering)
/// - Uses FileManager.replaceItem for atomic write (no partial state visible to Obsidian)
enum WordPageUpdater {

    /// Update a word page at `path` with looked-up `content`.
    /// `lemma` is the root form of the word (e.g. "posit"), used for VaultScanner self-exclusion.
    /// Silently aborts if the file is gone or the user has already written to Definition or Examples.
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

        // Guard: abort if user has already written to Definition
        guard let definitionBody = extractSectionBody(named: "Definition", from: text),
              definitionBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Guard: abort if user has already written to Examples
        guard let examplesBody = extractSectionBody(named: "Examples", from: text),
              examplesBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Scan vault for related words (uses combined definition + example text for matching)
        let scanText = content.definitions.joined(separator: " ")
            + " " + content.examples.joined(separator: " ")
        let relatedWords = VaultScanner.scan(
            definitionText: scanText,
            wordsFolderURL: AppSettings.shared.wordsFolderURL,
            excluding: lemma
        )

        var updated = text

        // Patch frontmatter: pos: "" → pos: "verb"
        if let pos = content.pos {
            var lines = updated.components(separatedBy: "\n")
            for i in lines.indices {
                if lines[i] == "pos: \"\"" {
                    lines[i] = "pos: \"\(pos)\""
                    break
                }
            }
            updated = lines.joined(separator: "\n")
        }

        // Patch frontmatter: pronunciation: "" → pronunciation: "pə-ˈzit"
        if let pronunciation = content.pronunciation {
            var lines = updated.components(separatedBy: "\n")
            for i in lines.indices {
                if lines[i] == "pronunciation: \"\"" {
                    lines[i] = "pronunciation: \"\(pronunciation)\""
                    break
                }
            }
            updated = lines.joined(separator: "\n")
        }

        // Replace Definition section with plain text definition
        let definitionText = content.definitions.first ?? ""
        guard let afterDefinition = replaceSection(named: "Definition", in: updated, with: "\n\(definitionText)\n\n") else { return }
        updated = afterDefinition

        // Replace Examples section with bullet-list of verbal illustrations
        if !content.examples.isEmpty {
            let examplesText = content.examples.map { "- \($0)" }.joined(separator: "\n")
            if let afterExamples = replaceSection(named: "Examples", in: updated, with: "\n\(examplesText)\n\n") {
                updated = afterExamples
            }
        }

        // Replace Linked words placeholder if vault scan found related words
        if !relatedWords.isEmpty {
            let linkedText = relatedWords.map { "- [[\($0)]]" }.joined(separator: "\n")
            if let afterLinked = replaceSection(named: "Linked words", in: updated, with: "\n\(linkedText)\n\n") {
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
