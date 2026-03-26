import AppKit
import Carbon
import NaturalLanguage

struct TextCapture {
    /// Saves the current pasteboard, simulates Cmd+C to copy selected text,
    /// reads the result, restores the original pasteboard, then validates the word
    /// and lemmatizes it (e.g. "posited" → "posit").
    static func captureSelectedText(completion: @escaping ((word: String, lemma: String)?) -> Void) {
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

                guard let rawWord = validate(captured) else {
                    completion(nil)
                    return
                }
                let lemma = lemmatize(rawWord)
                completion((word: rawWord, lemma: lemma))
            }
        }
    }

    /// Warm up NLTagger at app launch (background thread) to avoid first-capture latency.
    static func warmUp() {
        DispatchQueue.global(qos: .background).async {
            _ = lemmatize("warm")
        }
    }

    // MARK: - Private helpers

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

    /// Returns the lemma (root form) of `word` using NLTagger.
    /// Falls back to `word.lowercased()` if NLTagger returns nil.
    static func lemmatize(_ word: String) -> String {
        let normalized = word.lowercased()

        if let lemma = lemmatizedToken(in: normalized, at: normalized.startIndex),
           lemma != normalized {
            return lemma
        }

        // NLTagger is noticeably better for some standalone captures once we
        // give it a bit of grammatical context.
        for template in ["many %@", "to %@"] {
            let context = String(format: template, normalized)
            let startOffset = template.distance(from: template.startIndex, to: template.firstIndex(of: "%")!)
            let tokenStart = context.index(context.startIndex, offsetBy: startOffset)
            if let lemma = lemmatizedToken(in: context, at: tokenStart),
               lemma != normalized {
                return lemma
            }
        }

        if let singular = singularizeLikelyPlural(normalized) {
            return singular
        }

        return normalized
    }

    private static func lemmatizedToken(in text: String, at index: String.Index) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        let (tag, _) = tagger.tag(at: index, unit: .word, scheme: .lemma)
        guard let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty else {
            return nil
        }
        return lemma
    }

    private static func singularizeLikelyPlural(_ word: String) -> String? {
        guard word.count > 3 else { return nil }

        if word.hasSuffix("ies"), let prior = character(beforeSuffixLength: 3, in: word),
           !isVowel(prior) {
            return String(word.dropLast(3)) + "y"
        }

        let esSuffixes = ["sses", "ches", "shes", "xes", "zes", "oes"]
        if esSuffixes.contains(where: word.hasSuffix) {
            return String(word.dropLast(2))
        }

        // Only singularize if the result is a known English word or a valid
        // morphological variant. Block short words (news, chaos, bias, species)
        // and words ending in protected suffixes.
        let blockedBases = Set(["new", "chao", "bia", "spec", "canv", "lens",
                                "add", "idd", "udd", "edd"])
        let blockedSuffixes = ["ss", "is", "us", "ous"]
        if word.hasSuffix("s"),
           !blockedSuffixes.contains(where: word.hasSuffix),
           !blockedBases.contains(word) {
            return String(word.dropLast())
        }

        return nil
    }

    private static func character(beforeSuffixLength suffixLength: Int, in word: String) -> Character? {
        guard word.count > suffixLength else { return nil }
        let index = word.index(word.endIndex, offsetBy: -(suffixLength + 1))
        return word[index]
    }

    private static func isVowel(_ character: Character) -> Bool {
        "aeiou".contains(character)
    }
}
