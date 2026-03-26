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
        // Escape for YAML double-quoted string: escape backslashes first, then quotes.
        let escapedApp = sourceApp
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let content = """
        ---
        captured: \(dateString)
        app: "\(escapedApp)"
        pos: ""
        pronunciation: ""
        ---

        ## Context
        *(paste the sentence where you saw this word)*

        ## Definition


        ## Examples


        ## Usage
        **Register:**
        **Common with:**

        ## Word family
        \(filename)
        *(add related forms)*

        ## Linked words
        *(other captured words in the same semantic cluster — add [[wikilinks]])*

        ## Memory hook
        *(etymology, mnemonic, or story)*
        """

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .created(path: fileURL.path)
        } catch {
            return .error(message: "Could not write file: \(error.localizedDescription)")
        }
    }
}
