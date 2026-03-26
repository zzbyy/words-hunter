import Foundation

enum PageCreationResult {
    case created(path: String)
    case skipped
    case error(message: String)
}

struct WordPageCreator {
    static func createPage(for word: String) -> PageCreationResult {
        let settings = AppSettings.shared

        // Capitalize first letter, preserve remaining case (e.g. "API" stays "API")
        let filename = word.prefix(1).uppercased() + word.dropFirst()
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

        > 📅 \(dateString) | {POS} | {register/domain}

        ## Pronunciation


        ## Definition


        ## Useful Frames

        <!-- Semi-fixed patterns: "\(filename) A into B", "help \(filename.lowercased())" -->

        ## Collocations

        <!-- Natural pairings: \(filename.lowercased()) + [power / position / gains / debt] -->

        ## Examples

        <!-- Real sentences from where you found the word. Include source. -->
        1.
        2.

        ## Use It

        <!-- Write one sentence YOU would actually say or write. Not copied — yours. -->

        ## Synonyms

        <!-- List each with: HOW does it differ from this word? -->
        -

        ## Related Words


        ## Word Family

        - Noun:
        - Verb:
        - Adjective:
        - Adverb:

        ## Memory Hook

        <!-- Etymology, mnemonic, or personal connection that makes it stick. -->
        """

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .created(path: fileURL.path)
        } catch {
            return .error(message: "Could not write file: \(error.localizedDescription)")
        }
    }
}
