import Foundation

enum PageCreationResult {
    case created(path: String)
    case skipped
    case error(message: String)
}

struct WordPageCreator {
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

        // Write the template
        let dateString = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let content = """
        # \(filename)

        **Syllables:** *(e.g. po·sit)* · **Pronunciation:** *(e.g. /ˈpɒz.ɪt/)*

        ## Sightings
        - \(dateString) — *(context sentence where you saw the word)*

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

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .created(path: fileURL.path)
        } catch {
            return .error(message: "Could not write file: \(error.localizedDescription)")
        }
    }
}
