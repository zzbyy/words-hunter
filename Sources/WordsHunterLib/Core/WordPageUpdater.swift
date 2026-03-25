import Foundation

/// Reads an existing word page, checks that the Definition section is still empty,
/// replaces it with fetched content, and writes back atomically.
///
/// Safety checks:
/// - File not found → abort silently (deleted between create and lookup)
/// - Definition section already contains user text → abort silently (no clobbering)
/// - Uses FileManager.replaceItem for atomic write (no partial state visible to Obsidian)
enum WordPageUpdater {

    /// Update the `## Definition` section of the file at `path` with `content`.
    /// Silently aborts if the file is gone or the user has already written to the Definition section.
    static func updateDefinition(at path: String, with content: DictionaryContent) throws {
        let fileURL = URL(fileURLWithPath: path)

        // Guard: file may have been deleted between createPage and this call
        guard FileManager.default.fileExists(atPath: path) else { return }

        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return  // unreadable — abort silently
        }

        // Extract the body of the ## Definition section
        guard let definitionBody = extractDefinitionBody(from: text) else { return }

        // Guard: user has already written content — do not overwrite
        guard definitionBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Build the replacement section
        let formattedDefinitions = content.definitions
            .enumerated()
            .map { i, def in "\(i + 1). \(def)" }
            .joined(separator: "\n")
        let replacement = "## Definition\n\n\(formattedDefinitions)\n\n"

        // Replace the Definition section
        guard let updatedText = replaceDefinitionSection(in: text, with: replacement) else { return }

        // Atomic write via temp file + replaceItem
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try updatedText.write(to: tempURL, atomically: false, encoding: .utf8)
        try FileManager.default.replaceItem(
            at: fileURL,
            withItemAt: tempURL,
            backupItemName: nil,
            options: .usingNewMetadataOnly,
            resultingItemURL: nil
        )
    }

    // MARK: - Helpers

    /// Returns the text between `## Definition\n` and the next `## ` heading (or end of file).
    private static func extractDefinitionBody(from text: String) -> String? {
        guard let defRange = text.range(of: "## Definition\n") else { return nil }
        let afterHeader = text[defRange.upperBound...]

        // Find the next ## heading
        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            return String(afterHeader[..<nextHeadingRange.lowerBound])
        } else {
            return String(afterHeader)
        }
    }

    /// Replaces the `## Definition` section (up to next `## `) with `replacement`.
    private static func replaceDefinitionSection(in text: String, with replacement: String) -> String? {
        guard let defRange = text.range(of: "## Definition\n") else { return nil }
        let afterHeader = text[defRange.upperBound...]

        if let nextHeadingRange = afterHeader.range(of: "\n## ") {
            // Keep the newline before the next heading
            let before = text[..<defRange.lowerBound]
            let after = text[nextHeadingRange.lowerBound...]
            return before + replacement + after
        } else {
            let before = text[..<defRange.lowerBound]
            return before + replacement
        }
    }
}
