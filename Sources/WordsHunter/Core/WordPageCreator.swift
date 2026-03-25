import Foundation

enum PageCreationResult {
    case created(path: String)
    case skipped
    case error(message: String)
}

struct WordPageCreator {
    static func createPage(for word: String) -> PageCreationResult {
        let settings = AppSettings.shared
        guard !settings.vaultPath.isEmpty else {
            return .error(message: "Vault path not configured")
        }

        // Capitalize first letter, preserve remaining case (e.g. "API" stays "API")
        let filename = word.prefix(1).uppercased() + word.dropFirst()
        let folderURL = URL(fileURLWithPath: settings.vaultPath)
            .appendingPathComponent(settings.wordFolder)
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

        > 📅 Captured on \(dateString)

        ## Definition


        ## Examples


        ## Collocations


        ## Synonyms

        """

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .created(path: fileURL.path)
        } catch {
            return .error(message: "Could not write file: \(error.localizedDescription)")
        }
    }
}
