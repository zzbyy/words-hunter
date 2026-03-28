import AppKit
import Carbon
import NaturalLanguage

struct TextCapture {
    /// Saves the current pasteboard, simulates Cmd+C to copy selected text,
    /// reads the result, restores the original pasteboard, then validates the word.
    static func captureSelectedText(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general

            // Save current pasteboard contents
            let savedContents = pasteboard.pasteboardItems?.compactMap { item -> (types: [NSPasteboard.PasteboardType], data: [(NSPasteboard.PasteboardType, Data)])? in
                let types = item.types
                let data = types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    guard let d = item.data(forType: type) else { return nil }
                    return (type, d)
                }
                return (types: types, data: data)
            }

            // Clear and mark pasteboard so we can detect if it changes
            pasteboard.clearContents()

            // Simulate Cmd+C
            let src = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Wait for pasteboard to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let captured = pasteboard.string(forType: .string)

                // Restore original pasteboard
                pasteboard.clearContents()
                if let saved = savedContents {
                    for item in saved {
                        let newItem = NSPasteboardItem()
                        for (type, data) in item.data {
                            newItem.setData(data, forType: type)
                        }
                        pasteboard.writeObjects([newItem])
                    }
                }

                completion(validate(captured).map { lemmatize($0) })
            }
        }
    }

    /// Reduces an inflected word to its base (lemma) form.
    /// Uses NLTagger(.lemma) on macOS 13+. Falls back to the original word if NLTagger
    /// returns nil (proper nouns, acronyms, unknown words).
    /// Returns the base form with the first letter capitalised.
    static func lemmatize(_ word: String) -> String {
        let lowercased = word.lowercased()
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = lowercased
        let (tag, _) = tagger.tag(at: lowercased.startIndex, unit: .word, scheme: .lemma)
        if let lemma = tag?.rawValue, !lemma.isEmpty {
            return lemma.prefix(1).uppercased() + lemma.dropFirst()
        }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    private static func validate(_ raw: String?) -> String? {
        guard let text = raw else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(" "), !trimmed.contains("\n") else { return nil }

        // Strip non-alphabetic characters
        let alpha = trimmed.filter { $0.isLetter }
        guard !alpha.isEmpty else { return nil }

        // Return the cleaned word (use original casing but stripped of non-letters)
        return alpha
    }
}
