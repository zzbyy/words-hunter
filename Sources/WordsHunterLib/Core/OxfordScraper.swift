import Foundation

// MARK: - Dictionary Data Models
//
// Shared data models used by CambridgeScraper and the MW fallback adapter.
// (File retained for historical naming reasons; the Oxford scraper itself was
//  removed when Cambridge became the primary source.)

/// A single sense (definition) from Cambridge or MW
struct OxfordSense: Equatable {
    let cefrLevel: String?          // "A1", "B2", "C1", etc.
    let definition: String          // "a person who is chosen or elected to..."
    let examples: [String]          // inline examples under this sense
    let extraExamples: [String]     // "Extra Examples" expandable section
    let senseLabel: String?         // Cambridge: "GIVE", "CHOOSE PERSON", nil for noun
    let grammar: String?            // Cambridge: "[I or T]", "[C]", "[T]"
    let patterns: [String]          // Cambridge: ["delegate sth to sb", "delegate to"]
    let register: String?           // Cambridge: "formal", "informal", "specialized", etc.

    init(cefrLevel: String?, definition: String, examples: [String], extraExamples: [String],
         senseLabel: String? = nil, grammar: String? = nil, patterns: [String] = [],
         register: String? = nil) {
        self.cefrLevel = cefrLevel
        self.definition = definition
        self.examples = examples
        self.extraExamples = extraExamples
        self.senseLabel = senseLabel
        self.grammar = grammar
        self.patterns = patterns
        self.register = register
    }
}

/// Collocation group (e.g. "adjective", "verb + delegate")
struct CollocationGroup: Equatable {
    let label: String               // "adjective", "verb + delegate", etc.
    let items: [String]             // ["conference", "congress", "convention", "…"]
}

/// A single dictionary entry (one POS)
struct OxfordEntry: Equatable {
    let pos: String?                // "noun", "verb", "adjective"
    let cefrLevel: String?          // word-level CEFR (from header)
    let senses: [OxfordSense]
    let collocations: [CollocationGroup]
}

/// Nearby word with its POS
struct NearbyWord: Equatable {
    let word: String
    let pos: String?
}

/// A word family entry — one related word form with its parts of speech
struct WordFamilyEntry: Equatable {
    let word: String
    let partsOfSpeech: [String]     // e.g. ["noun", "verb"]
}
