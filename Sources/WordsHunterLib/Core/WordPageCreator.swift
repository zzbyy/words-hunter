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
    /// **Lookup-time variables** (filled after the Cambridge dictionary lookup completes):
    /// - `{{pronunciation-bre}}` — British English IPA (e.g. "/ˈpɒz.ɪt/")
    /// - `{{pronunciation-ame}}` — American English IPA (e.g. "/ˈpɑː.zɪt/")
    /// - `{{cefr}}` — CEFR level badge (e.g. "B2")
    /// - `{{meanings}}` — definition blocks (definition as heading, patterns, examples)
    /// - `{{corpus-examples}}` — real-world usage from the Cambridge English Corpus
    /// - `{{see-also}}` — `[[wikilink]]` lines for related words found in the vault
    ///
    /// Any variable can be omitted from a custom template to opt out of that section being auto-filled.
    /// Used when `.wordshunter/template.md` does not exist in the vault.
    static let defaultTemplate = """
    # {{word}}

    **Pronunciation:** 🇬🇧 {{pronunciation-bre}} · 🇺🇸 {{pronunciation-ame}} · **Level:** {{cefr}}

    ## Definitions
    {{meanings}}

    ## Corpus Examples
    {{corpus-examples}}

    ---

    ## When to Use
    {{when-to-use}}
    ---

    ## Word Family
    {{word-family}}

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

    /// All lookup-time variable names used in the current template system.
    static let allLookupVariables = [
        "{{pronunciation-bre}}", "{{pronunciation-ame}}", "{{cefr}}",
        "{{meanings}}", "{{corpus-examples}}",
        "{{when-to-use}}", "{{word-family}}", "{{see-also}}",
        // Legacy Oxford/MW variables — kept so old pages are still detected as fillable
        "{{collocations}}", "{{nearby-words}}"
    ]

    /// Legacy lookup variables (used for migration detection).
    /// MW-era: {{syllables}}, {{pronunciation}}
    /// Oxford-era: {{collocations}}, {{nearby-words}} (without {{corpus-examples}})
    private static let legacyMWVariables = [
        "{{syllables}}", "{{pronunciation}}"
    ]

    private static let legacyOxfordVariables = [
        "{{collocations}}", "{{nearby-words}}"
    ]

    /// Writes the default template to `.wordshunter/template.md`.
    /// Migration cases:
    /// - No file exists → create with new Oxford template
    /// - Old MW-era template (has {{syllables}}) → replace with new Oxford template
    /// - Old pre-variable template (no lookup vars at all) → replace with new Oxford template
    /// - Template with deprecated Sightings section → replace
    /// - Current Oxford-era template (has any new variable) → leave untouched
    static func seedTemplateIfNeeded(vaultPath: String) {
        guard !vaultPath.isEmpty else { return }
        let dotDir = URL(fileURLWithPath: vaultPath).appendingPathComponent(".wordshunter")
        let templateURL = dotDir.appendingPathComponent("template.md")
        try? FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: templateURL.path) {
            if let existing = try? String(contentsOf: templateURL, encoding: .utf8) {
                // MW-era template → replace
                let hasLegacyMWVar = legacyMWVariables.contains { existing.contains($0) }
                if hasLegacyMWVar {
                    try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
                    return
                }
                // Oxford-era template (has collocations/nearby but no corpus-examples) → replace
                let hasLegacyOxfordVar = legacyOxfordVariables.contains { existing.contains($0) }
                let hasCambridgeVar = existing.contains("{{corpus-examples}}")
                if hasLegacyOxfordVar && !hasCambridgeVar {
                    try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
                    return
                }
                // Cambridge-era template missing new variables → upgrade
                if hasCambridgeVar && !existing.contains("{{when-to-use}}") {
                    try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
                    return
                }
                // Template still has deprecated Sightings section → upgrade
                if existing.contains("## Sightings") {
                    try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
                    return
                }
                // Current Cambridge template → leave untouched
                if hasCambridgeVar { return }

                // Pre-variable template → overwrite
                try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
            }
            return
        }
        try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
    }
}
