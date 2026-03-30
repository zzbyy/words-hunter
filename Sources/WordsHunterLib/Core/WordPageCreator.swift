import Foundation

enum PageCreationResult {
    case created(path: String)
    case skipped
    case error(message: String)
}

struct WordPageCreator {

    /// Default template with `{{word}}` and `{{date}}` placeholders.
    /// Used when `.wordshunter/template.md` does not exist in the vault.
    static let defaultTemplate = """
    # {{word}}

    **Syllables:** *(e.g. po·sit)* · **Pronunciation:** *(e.g. /ˈpɒz.ɪt/)*

    ## Sightings
    - {{date}} — *(context sentence where you saw the word)*

    ---

    ## Meanings

    ### 1. () *()*

    > *()*

    **My sentence:**
    - *(write your own sentence using this word)*

    **Patterns:**
    - *(common word combinations and grammar patterns)*

    ---

    ## When to Use

    **Where it fits:**
    **In casual speech:**

    ---

    ## Word Family

    *(list related forms, each with a short example)*

    ---

    ## See Also
    *(link to other captured words with a note on how they differ)*

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

    /// Writes the default template to `.wordshunter/template.md` if it doesn't exist yet.
    static func seedTemplateIfNeeded(vaultPath: String) {
        guard !vaultPath.isEmpty else { return }
        let dotDir = URL(fileURLWithPath: vaultPath).appendingPathComponent(".wordshunter")
        let templateURL = dotDir.appendingPathComponent("template.md")
        guard !FileManager.default.fileExists(atPath: templateURL.path) else { return }
        try? FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        try? defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
    }
}
