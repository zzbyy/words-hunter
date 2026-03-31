import Foundation
import SwiftSoup

// MARK: - Cambridge Scraper

/// Fetches and parses word definitions from Cambridge Learner's Dictionary via HTML scraping.
/// No API key required — works by parsing the public web page.
///
/// Usage:
///   let content = try await CambridgeScraper.lookup(word: "delegate", session: URLSession.shared)
///
/// Anti-detection measures (built-in):
///   - Realistic User-Agent (macOS Safari)
///   - Accept-Language header
///   - Random jitter delay (0.5–2.0s) before each request
enum CambridgeScraper {

    private static let baseURL = "https://dictionary.cambridge.org"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    // MARK: - Public API

    /// Look up a word on Cambridge Dictionary.
    /// Returns nil if the word is not found. Throws on network errors.
    static func lookup(word: String, session: URLSessionProtocol) async throws -> DictionaryContent? {
        try Task.checkCancellation()
        try await jitterDelay()

        let encoded = word.lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word.lowercased()
        let urlString = "\(baseURL)/dictionary/english/\(encoded)"

        guard let html = try await fetchPage(url: urlString, session: session) else {
            return nil
        }

        return parseContent(html: html, word: word)
    }

    // MARK: - HTTP

    /// Fetch HTML from a URL with browser-like headers. Returns nil on 404.
    private static func fetchPage(url urlString: String, session: URLSessionProtocol) async throws -> String? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            if code == 404 { return nil }
            if code == 429 || code == 403 { throw CambridgeError.blocked(statusCode: code) }
            if code >= 500 { throw CambridgeError.serverError(statusCode: code) }
            if code < 200 || code >= 300 { throw CambridgeError.unexpectedStatus(statusCode: code) }
        }

        return String(data: data, encoding: .utf8)
    }

    private static func jitterDelay() async throws {
        let delayMs = UInt64.random(in: 500...2000)
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }

    // MARK: - Page Parsing

    internal static func parseContent(html: String, word: String) -> DictionaryContent? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }

        let headword = extractHeadword(doc: doc) ?? word.lowercased()
        let (breIPA, ameIPA) = extractPronunciations(doc: doc)
        let entries = extractEntries(doc: doc)
        let corpusExamples = extractCorpusExamples(doc: doc)

        guard !entries.isEmpty else { return nil }

        return DictionaryContent(
            headword: headword,
            pronunciationBrE: breIPA,
            pronunciationAmE: ameIPA,
            entries: entries,
            nearbyWords: [],
            corpusExamples: corpusExamples,
            source: "Cambridge Dictionary"
        )
    }

    // MARK: - Headword

    internal static func extractHeadword(doc: Document) -> String? {
        let text = (try? doc.select(".headword").first()?.text())
            ?? (try? doc.select(".hw.dhw").first()?.text())
        return text.map { clean($0) }?.nonEmpty
    }

    // MARK: - Pronunciations

    /// Returns (BrE, AmE) IPA strings, each wrapped in /…/
    internal static func extractPronunciations(doc: Document) -> (String?, String?) {
        let bre = extractIPA(doc: doc, regionClass: "uk")
        let ame = extractIPA(doc: doc, regionClass: "us")
        return (bre, ame)
    }

    private static func extractIPA(doc: Document, regionClass: String) -> String? {
        // .uk.dpron-i or .us.dpron-i contain .ipa.dipa
        guard let region = (try? doc.select(".\(regionClass).dpron-i"))?.first() else { return nil }
        guard let ipa = (try? region.select(".ipa.dipa"))?.first() else { return nil }
        let text = clean(ipa.ownText())
        guard !text.isEmpty else { return nil }
        return "/\(text)/"
    }

    // MARK: - Entries (POS blocks)

    /// Parse the main English entry and merge American Dictionary examples into it.
    ///
    /// Cambridge structure:
    ///   - Main English: first `div.entry-body` (not inside any `div.di-body`)
    ///   - American:     `div.entry-body` elements inside the `div.di-body` whose
    ///                   parent contains a `div.di-head` with "American" in the text
    internal static func extractEntries(doc: Document) -> [OxfordEntry] {
        // 1. Parse main English entry (first entry-body in the document)
        guard let mainBody = (try? doc.select("div.entry-body"))?.first() else { return [] }
        guard let posBlocks = try? mainBody.select("div.pr.entry-body__el") else { return [] }

        var entries: [OxfordEntry] = []
        for block in posBlocks {
            if let entry = parseEntryBlock(block) {
                entries.append(entry)
            }
        }
        guard !entries.isEmpty else { return [] }

        // 2. Find the American Dictionary di-body and merge its examples
        if let americanBody = findDiBody(labeled: "American", in: doc) {
            let americanPOSBlocks = (try? americanBody.select("div.pr.entry-body__el"))?.array() ?? []
            let americanEntries = americanPOSBlocks.compactMap { parseEntryBlock($0) }
            mergeExamples(from: americanEntries, into: &entries)
        }

        return entries
    }

    /// Find the `div.di-body` whose sibling `div.di-head` contains `label`.
    private static func findDiBody(labeled label: String, in doc: Document) -> Element? {
        guard let diBodies = try? doc.select("div.di-body") else { return nil }
        for body in diBodies {
            guard let parent = body.parent(),
                  let headText = try? parent.select("div.di-head").first()?.text(),
                  headText.contains(label) else { continue }
            return body
        }
        return nil
    }

    /// Merge examples from `source` entries into `target` entries, matched by POS and sense index.
    /// Only adds examples not already present in the target sense.
    private static func mergeExamples(from source: [OxfordEntry], into target: inout [OxfordEntry]) {
        for srcEntry in source {
            guard let targetIdx = target.firstIndex(where: { $0.pos == srcEntry.pos }) else { continue }
            var targetSenses = target[targetIdx].senses

            for (senseIdx, srcSense) in srcEntry.senses.enumerated() {
                guard senseIdx < targetSenses.count else { break }
                let existing = Set(targetSenses[senseIdx].examples)
                let newExamples = srcSense.examples.filter { !existing.contains($0) }
                guard !newExamples.isEmpty else { continue }

                let old = targetSenses[senseIdx]
                targetSenses[senseIdx] = OxfordSense(
                    cefrLevel: old.cefrLevel,
                    definition: old.definition,
                    examples: old.examples + newExamples,
                    extraExamples: old.extraExamples,
                    senseLabel: old.senseLabel,
                    grammar: old.grammar,
                    patterns: old.patterns
                )
            }

            target[targetIdx] = OxfordEntry(
                pos: target[targetIdx].pos,
                cefrLevel: target[targetIdx].cefrLevel,
                senses: targetSenses,
                collocations: target[targetIdx].collocations
            )
        }
    }

    private static func parseEntryBlock(_ block: Element) -> OxfordEntry? {
        // POS label
        let pos = (try? block.select("b.pos.dpos, span.pos.dpos").first()?.text())
            .map { clean($0) }?.nonEmpty

        // Entry-level grammar like [C] for nouns — in .posgram .gram.dgram
        let entryGrammar = (try? block.select(".posgram .gram.dgram").first()?.text())
            .map { cleanGrammar($0) }

        // Senses from dsense blocks
        let senses = parseSenses(from: block, fallbackGrammar: entryGrammar)
        guard !senses.isEmpty else { return nil }

        return OxfordEntry(pos: pos, cefrLevel: nil, senses: senses, collocations: [])
    }

    // MARK: - Senses

    private static func parseSenses(from block: Element, fallbackGrammar: String?) -> [OxfordSense] {
        guard let dsenseBlocks = try? block.select("div.dsense") else { return [] }

        var senses: [OxfordSense] = []
        for dsense in dsenseBlocks {
            // Sense label from dsense_h (e.g., "GIVE", "CHOOSE PERSON")
            let senseLabel = extractSenseLabel(from: dsense)

            // Each dsense can contain multiple def-blocks
            guard let defBlocks = try? dsense.select("div.ddef_block") else { continue }
            for defBlock in defBlocks {
                if let sense = parseDefBlock(defBlock, senseLabel: senseLabel, fallbackGrammar: fallbackGrammar) {
                    senses.append(sense)
                }
            }
        }
        return senses
    }

    private static func extractSenseLabel(from dsense: Element) -> String? {
        // dsense_h contains text like "delegate verb (GIVE)" — extract just the parenthesised label
        guard let header = (try? dsense.select(".dsense_h").first()) else { return nil }
        let text = clean(header.ownText())

        // Try to find text in parentheses
        if let match = text.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let inner = String(text[match]).dropFirst().dropLast()
            return inner.isEmpty ? nil : String(inner)
        }
        // Also check child span text
        if let spanText = (try? header.select("span").first()?.text()).map({ clean($0) }),
           !spanText.isEmpty {
            return spanText
        }
        return nil
    }

    private static func parseDefBlock(_ block: Element, senseLabel: String?, fallbackGrammar: String?) -> OxfordSense? {
        // CEFR: span.epp-xref (text is the level)
        let cefr = (try? block.select("span.epp-xref").first()?.text())
            .map { normalizeCEFR(clean($0)) } ?? nil

        // Grammar: .gram.dgram inside .ddef_h (sense-level), fall back to entry-level
        let grammar: String?
        if let g = (try? block.select(".ddef_h .gram.dgram").first()?.text()).map({ cleanGrammar($0) }), !g.isEmpty {
            grammar = g
        } else {
            grammar = fallbackGrammar
        }

        // Definition: div.def.ddef_d — use text() not ownText() because Cambridge wraps
        // every content word in <a class="query"> links, so ownText() would strip them all.
        guard let defEl = (try? block.select("div.def.ddef_d").first()) else { return nil }
        let definition = clean((try? defEl.text()) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard !definition.isEmpty else { return nil }

        // Patterns and examples from .examp.dexamp
        var patterns: [String] = []
        var examples: [String] = []

        if let exampBlocks = try? block.select(".def-body .examp.dexamp") {
            for examp in exampBlocks {
                // Pattern: span.lu.dlu (optional)
                if let luEl = (try? examp.select("span.lu.dlu").first()),
                   let luText = try? luEl.text() {
                    let pattern = clean(luText)
                    if !pattern.isEmpty && !patterns.contains(pattern) {
                        patterns.append(pattern)
                    }
                }
                // Example: span.eg.deg
                if let egEl = (try? examp.select("span.eg.deg").first()),
                   let egText = try? egEl.text() {
                    let ex = clean(egText)
                    if !ex.isEmpty {
                        examples.append(ex)
                    }
                }
            }
        }

        // Also include accordion examples (More examples) — class "eg dexamp hax"
        if let accordionExamples = try? block.select("li.eg.dexamp.hax") {
            for eg in accordionExamples {
                if let text = try? eg.text() {
                    let ex = clean(text)
                    if !ex.isEmpty { examples.append(ex) }
                }
            }
        }

        return OxfordSense(
            cefrLevel: cefr,
            definition: definition,
            examples: examples,
            extraExamples: [],
            senseLabel: senseLabel,
            grammar: grammar,
            patterns: patterns
        )
    }

    // MARK: - Corpus Examples

    internal static func extractCorpusExamples(doc: Document) -> [String] {
        // Corpus examples are span.deg inside .lbb.lb-cm blocks
        // (each followed by a .dsource containing "Cambridge English Corpus")
        var results: [String] = []

        guard let corpusBlocks = try? doc.select("div.lbb.lb-cm") else { return [] }
        for block in corpusBlocks {
            // Verify it's a corpus example (not another source)
            let source = (try? block.select(".dsource").text()) ?? ""
            guard source.contains("Cambridge English Corpus") else { continue }

            if let egEl = try? block.select("span.deg").first(),
               let text = try? egEl.text() {
                let ex = clean(text)
                if !ex.isEmpty { results.append(ex) }
            }
        }
        return results
    }

    // MARK: - Text Helpers

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanGrammar(_ raw: String) -> String {
        // Normalise "[  I  or  T  ]" → "[I or T]"
        let collapsed = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed
    }

    private static func normalizeCEFR(_ text: String) -> String? {
        let upper = text.uppercased()
        return ["A1","A2","B1","B2","C1","C2"].contains(upper) ? upper : nil
    }
}

// MARK: - String helper

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Errors

enum CambridgeError: Error {
    case blocked(statusCode: Int)
    case serverError(statusCode: Int)
    case unexpectedStatus(statusCode: Int)
}
