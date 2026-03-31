import Foundation

enum PageCreationResult {
    case created(path: String)
    case skipped
    case error(message: String)
}

struct WordPageCreator {

    /// Default template with creation-time and lookup-time placeholders.
    ///
    /// **Creation-time variables** (filled immediately when the page is created):
    /// - `{{word}}` — lowercased lemma (e.g. "posit")
    /// - `{{date}}` — capture date in YYYY-MM-DD format
    ///
    /// **Lookup-time variables** (filled after the MW dictionary lookup completes):
    /// - `{{syllables}}` — syllable breakdown (e.g. "po·sit")
    /// - `{{pronunciation}}` — IPA string (e.g. "/ˈpɒz.ɪt/")
    /// - `{{meanings}}` — numbered meaning blocks generated from the API response
    /// - `{{see-also}}` — `[[wikilink]]` lines for related words found in the vault
    ///
    /// Any variable can be omitted from a custom template to opt out of that section being auto-filled.
    /// Used when `.wordshunter/template.md` does not exist in the vault.
    static let defaultTemplate = """
    # {{word}}

    **Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}

    ## Sightings
    - {{date}} — *(context sentence where you saw the word)*

    ---

    ## Meanings
    {{meanings}}

    ## When to Use

    **Where it fits:**
    **In casual speech:**

    ---

    ## Word Family

    *(list related forms, each with a short example)*

    ---

    ## See Also
    {{see-also}}

    ---

    ## Memory Tip
    *(optional: etymology, mnemonic, personal association — anything that helps you remember)*
    """

    /// Create a new word page for `lemma` (root form, e.g. "posit").
    /// Filename is lowercased: "posit.md". Returns .skipped if the page already exists.
    static func createPage(lemma: String, sourceApp: String) -> PageCreationResult {
        let settings = AppSettings.shared
        let filename = lemma.lowercased()

        guard let folderURL = settings.wordsFolderURL else {
            return .error(message: "Vault path not configured")
        }
        let fileURL = folderURL.appendingPathComponent("\(filename).md")

        // Skip silently if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return .skipped
        }

        // Create folder if needed
        do {
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        } catch {
            return .error(message: "Could not create folder: \(error.localizedDescription)")
        }

        // Load template (custom file or built-in default), substitute placeholders
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let template = loadTemplate(vaultPath: settings.vaultPath)
        let content = template
            .replacingOccurrences(of: "{{word}}", with: filename)
            .replacingOccurrences(of: "{{date}}", with: dateString)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .created(path: fileURL.path)
        } catch {
            return .error(message: "Could not write file: \(error.localizedDescription)")
        }
    }

    /// Reads `.wordshunter/template.md` from the vault root.
    /// Falls back to `defaultTemplate` if the file is missing or empty.
    private static func loadTemplate(vaultPath: String) -> String {
        guard !vaultPath.isEmpty else { return defaultTemplate }
        let templateURL = URL(fileURLWithPath: vaultPath)
            .appendingPathComponent(".wordshunter")
            .appendingPathComponent("template.md")
        if let custom = try? String(contentsOf: templateURL, encoding: .utf8),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return defaultTemplate
    }

    /// Writes the default template to `.wordshunter/template.md`.
    /// If the file already exists but predates the variable system (no `{{syllables}}`), it is
    /// replaced with the new default so lookup-time fill works correctly.
    static func seedTemplateIfNeeded(vaultPath: String) {
        guard !vaultPath.isEmpty else { return }
        let dotDir = URL(fileURLWithPath: vaultPath).appendingPathComponent(".wordshunter")
        let templateURL = dotDir.appendingPathComponent("template.md")
        try? FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: templateURL.path) {
            // Migrate pre-variable templates: if NO lookup-time variable is present, overwrite with
            // the new default. Checking only one variable would wrongly clobber custom templates
            // that use some variables but not others (a valid opt-out pattern).
            if let existing = try? String(contentsOf: templateURL, encoding: .utf8) {
                let hasAnyLookupVar = existing.contains("{{syllables}}")
                    || existing.contains("{{pronunciation}}")
                    || existing.contains("{{meanings}}")
                    || existing.contains("{{see-also}}")
                if !hasAnyLookupVar {
                    try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
                }
            }
            return
        }
        try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
    }
}
