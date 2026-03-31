import Foundation
import SwiftSoup

// MARK: - Oxford Data Models

/// A single sense (definition) from Oxford
struct OxfordSense: Equatable {
    let cefrLevel: String?          // "A1", "B2", "C1", etc.
    let definition: String          // "a person who is chosen or elected to..."
    let examples: [String]          // inline examples under this sense
    let extraExamples: [String]     // "Extra Examples" expandable section
}

/// Collocation group (e.g. "adjective", "verb + delegate")
struct CollocationGroup: Equatable {
    let label: String               // "adjective", "verb + delegate", etc.
    let items: [String]             // ["conference", "congress", "convention", "…"]
}

/// A single Oxford dictionary entry (one POS)
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

// MARK: - Oxford Scraper

/// Fetches and parses word definitions from Oxford Learner's Dictionary via HTML scraping.
/// No API key required — works by parsing the public web page.
///
/// Usage:
///   let content = try await OxfordScraper.lookup(word: "delegate", session: URLSession.shared)
///
/// Anti-detection measures (built-in, invisible to users):
///   - Realistic User-Agent (macOS Safari)
///   - Accept-Language header
///   - Random jitter delay (0.5–2.0s) before each request
///   - Exponential backoff on failure
enum OxfordScraper {

    private static let baseURL = "https://www.oxfordlearnersdictionaries.com"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private struct OxfordPage {
        let html: String
        let finalURL: URL?
    }

    // MARK: - Public API

    /// Look up a word on Oxford Learner's Dictionary.
    /// Returns nil if the word is not found. Throws on network errors.
    /// Fetches all available entries (noun, verb, etc.) and merges them.
    static func lookup(word: String, session: URLSessionProtocol) async throws -> DictionaryContent? {
        try Task.checkCancellation()

        guard let primaryPage = try await resolvePrimaryPage(word: word, session: session) else {
            return nil
        }
        let html = primaryPage.html

        // Step 2: Parse the primary entry
        guard let primaryEntry = parseEntry(html: html) else {
            return nil
        }

        // Step 3: Extract headword and pronunciation from the page header
        let headword = extractHeadword(html: html) ?? word.lowercased()
        let pronunciationBrE = extractPronunciation(html: html, geo: "phons_br")
        let pronunciationAmE = extractPronunciation(html: html, geo: "phons_n_am")
        let nearbyWords = extractNearbyWords(html: html)

        // Step 4: Find other entry URLs (e.g., verb form)
        let primaryURL = normalizeDefinitionURL(primaryPage.finalURL)?.absoluteString
        let otherEntryURLs = extractOtherEntryURLs(html: html).filter { $0 != primaryURL }
        var allEntries = [primaryEntry]

        for entryURL in otherEntryURLs {
            try Task.checkCancellation()
            try await jitterDelay()

            if let otherPage = try await fetchPage(url: entryURL, session: session),
               let otherEntry = parseEntry(html: otherPage.html) {
                allEntries.append(otherEntry)
            }
        }

        return DictionaryContent(
            headword: headword,
            pronunciationBrE: pronunciationBrE,
            pronunciationAmE: pronunciationAmE,
            entries: allEntries,
            nearbyWords: nearbyWords,
            source: "Oxford Learner's Dictionary"
        )
    }

    // MARK: - HTTP

    /// Resolve the most promising Oxford definition page for a word.
    /// Tries the direct definition URL first, then Oxford's search page as a fallback.
    private static func resolvePrimaryPage(
        word: String,
        session: URLSessionProtocol
    ) async throws -> OxfordPage? {
        let encoded = word.lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word.lowercased()
        let definitionURL = "\(baseURL)/definition/english/\(encoded)"

        try await jitterDelay()
        if let directPage = try await fetchPage(url: definitionURL, session: session),
           looksLikeDefinitionPage(directPage.html) {
            return directPage
        }

        try Task.checkCancellation()
        try await jitterDelay()
        let searchURL = "\(baseURL)/search/english/?q=\(encoded)"
        guard let searchPage = try await fetchPage(url: searchURL, session: session) else {
            return nil
        }

        if looksLikeDefinitionPage(searchPage.html) {
            return searchPage
        }

        guard let resultURL = extractSearchResultURL(html: searchPage.html) else {
            return nil
        }

        try Task.checkCancellation()
        try await jitterDelay()
        return try await fetchPage(url: resultURL, session: session)
    }

    /// Fetch HTML from a URL with browser-like headers. Returns nil on 404.
    /// Throws on network errors or non-2xx responses (except 404).
    private static func fetchPage(url urlString: String, session: URLSessionProtocol) async throws -> OxfordPage? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            if code == 404 { return nil }
            if code == 429 || code == 403 {
                throw OxfordError.blocked(statusCode: code)
            }
            if code >= 500 {
                throw OxfordError.serverError(statusCode: code)
            }
            if code < 200 || code >= 300 {
                throw OxfordError.unexpectedStatus(statusCode: code)
            }
        }

        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return OxfordPage(html: html, finalURL: response.url)
    }

    /// Random delay of 0.5–2.0 seconds
    private static func jitterDelay() async throws {
        let delayMs = UInt64.random(in: 500...2000)
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }

    // MARK: - Entry Parsing

    /// Parse an Oxford entry page HTML into an OxfordEntry.
    /// Returns nil if no definitions are found.
    internal static func parseEntry(html: String) -> OxfordEntry? {
        let pos = firstText(
            html: html,
            selectors: [".webtop .pos", ".top-container .pos", "span.pos"]
        )

        // Extract word-level CEFR from header (e.g., ox5ksym_c1)
        let headerCEFR = extractHeaderCEFR(html: html)

        // Extract senses (definitions)
        let senses = extractSenses(html: html)
        guard !senses.isEmpty else { return nil }

        // Extract collocations
        let collocations = extractCollocations(html: html)

        return OxfordEntry(
            pos: pos,
            cefrLevel: headerCEFR,
            senses: senses,
            collocations: collocations
        )
    }

    // MARK: - Headword & Pronunciation

    /// Extract the headword from `<h1 class="headword">`
    internal static func extractHeadword(html: String) -> String? {
        firstText(html: html, selectors: ["h1.headword", "h1"])
    }

    /// Extract pronunciation IPA from a specific geo section (phons_br or phons_n_am)
    internal static func extractPronunciation(html: String, geo: String) -> String? {
        let selectors: [String]
        switch geo {
        case "phons_br":
            selectors = [".phons_br .phon", "[geo=br] .phon"]
        case "phons_n_am":
            selectors = [".phons_n_am .phon", "[geo=n_am] .phon"]
        default:
            selectors = [".\(geo) .phon"]
        }

        if let parserText = firstText(html: html, selectors: selectors) {
            return parserText
        }
        return nil
    }

    // MARK: - CEFR Level

    /// Extract CEFR level from the page header (e.g., ox5ksym_b2, ox3ksym_a1)
    internal static func extractHeaderCEFR(html: String) -> String? {
        guard let doc = makeDocument(html),
              let elements = try? doc.select(".webtop [class*=ox5ksym_], .webtop [class*=ox3ksym_], [class*=ox5ksym_], [class*=ox3ksym_]")
        else { return nil }

        for element in elements {
            if let classValue = try? element.attr("class"),
               let level = cefrFromClassNames(classValue) {
                return level
            }
        }

        return nil
    }

    // MARK: - Senses (Definitions)

    /// Extract all senses (definitions) from the page.
    internal static func extractSenses(html: String) -> [OxfordSense] {
        guard let doc = makeDocument(html),
              let senseElements = try? doc.select("li.sense")
        else { return [] }

        var senses: [OxfordSense] = []
        for sense in senseElements {
            guard let definition = firstText(in: sense, selectors: [".def"]) else { continue }

            let cefrLevel = normalizeCEFR(try? sense.attr("cefr"))
            let examples = texts(in: sense, selectors: ["ul.examples .x", ".examples .x"])
            let extraExamples = texts(in: sense, selectors: ["[unbox=extra_examples] .unx", ".unx"])

            senses.append(OxfordSense(
                cefrLevel: cefrLevel,
                definition: definition,
                examples: examples,
                extraExamples: extraExamples
            ))
        }

        return senses
    }

    // MARK: - Collocations

    /// Extract collocation groups from the Oxford Collocations Dictionary section.
    internal static func extractCollocations(html: String) -> [CollocationGroup] {
        guard let doc = makeDocument(html),
              let labels = try? doc.select("span.unbox")
        else { return [] }

        var groups: [CollocationGroup] = []
        for labelElement in labels {
            guard let label = try? labelElement.text().trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty
            else { continue }
            if label == "Oxford Collocations Dictionary" || label == "Extra Examples" { continue }

            guard let listElement = try? labelElement.nextElementSibling(),
                  listElement.hasClass("collocs_list"),
                  let items = try? listElement.select("li")
            else { continue }

            let values = items.compactMap { try? $0.text() }
                .map(cleanText)
                .filter { !$0.isEmpty }

            if !values.isEmpty {
                groups.append(CollocationGroup(label: label, items: values))
            }
        }

        return groups
    }

    // MARK: - Nearby Words

    /// Extract nearby words from the sidebar
    internal static func extractNearbyWords(html: String) -> [NearbyWord] {
        guard let doc = makeDocument(html),
              let nearbyElements = try? doc.select(".nearby data.hwd, .nearby DATA.hwd")
        else {
            return []
        }

        return nearbyElements.compactMap { element -> NearbyWord? in
            let word = cleanText(element.ownText())
            guard !word.isEmpty else { return nil }
            let pos = firstText(in: element, selectors: ["pos"])
            return NearbyWord(word: word, pos: pos)
        }
    }

    // MARK: - Other Entries (sidebar)

    /// Extract URLs for other entries of the same word (e.g., delegate_2 verb)
    internal static func extractOtherEntryURLs(html: String) -> [String] {
        extractDefinitionURLs(html: html, selectors: ["#relatedentries a[href]", "a[href*=\"/definition/english/\"]"])
    }

    /// Extract the first result URL from Oxford search results.
    internal static func extractSearchResultURL(html: String) -> String? {
        extractDefinitionURLs(
            html: html,
            selectors: ["#search-results a[href]", ".result-list a[href]", ".list-result a[href]", "a[href*=\"/definition/english/\"]"]
        ).first
    }

    // MARK: - Generic HTML Helpers

    private static func looksLikeDefinitionPage(_ html: String) -> Bool {
        guard let doc = makeDocument(html) else { return false }
        return firstText(in: doc, selectors: ["h1.headword", "li.sense .def"]) != nil
    }

    private static func makeDocument(_ html: String) -> Document? {
        try? SwiftSoup.parse(html)
    }

    private static func firstText(html: String, selectors: [String]) -> String? {
        guard let doc = makeDocument(html) else { return nil }
        return firstText(in: doc, selectors: selectors)
    }

    private static func firstText(in root: Element, selectors: [String]) -> String? {
        for selector in selectors {
            if let elements = try? root.select(selector),
               let first = elements.first(),
               let text = try? first.text() {
                let cleaned = cleanText(text)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private static func texts(in root: Element, selectors: [String]) -> [String] {
        for selector in selectors {
            if let elements = try? root.select(selector) {
                let texts = elements.compactMap { try? $0.text() }
                    .map(cleanText)
                    .filter { !$0.isEmpty }
                if !texts.isEmpty { return texts }
            }
        }
        return []
    }

    private static func extractDefinitionURLs(html: String, selectors: [String]) -> [String] {
        guard let doc = makeDocument(html) else { return [] }
        for selector in selectors {
            if let links = try? doc.select(selector) {
                let urls = links.compactMap { try? $0.attr("href") }
                    .compactMap { absoluteOxfordDefinitionURL(from: $0) }
                let deduped = deduplicated(urls)
                if !deduped.isEmpty { return deduped }
            }
        }
        return []
    }

    private static func cleanText(_ text: String?) -> String {
        guard let text else { return "" }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func absoluteOxfordDefinitionURL(from href: String) -> String? {
        absoluteOxfordURL(from: href)?.absoluteString
    }

    private static func absoluteOxfordURL(from href: String) -> URL? {
        if let absolute = URL(string: href), absolute.host != nil {
            return normalizeDefinitionURL(absolute)
        }

        guard let base = URL(string: baseURL),
              let relative = URL(string: href, relativeTo: base)?.absoluteURL else {
            return nil
        }
        return normalizeDefinitionURL(relative)
    }

    private static func normalizeDefinitionURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard let host = url.host, host.contains("oxfordlearnersdictionaries.com") else { return nil }
        guard url.path.contains("/definition/english/") else { return nil }
        return url
    }

    /// Strip all HTML tags from a string
    internal static func stripHTML(_ text: String) -> String {
        if let doc = try? SwiftSoup.parseBodyFragment(text),
           let body = doc.body(),
           let bodyText = try? body.text() {
            return cleanText(bodyText)
        }
        return cleanText(text)
    }

    private static func deduplicated(_ urls: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for url in urls where seen.insert(url).inserted {
            ordered.append(url)
        }
        return ordered
    }

    private static func normalizeCEFR(_ level: String?) -> String? {
        guard let level else { return nil }
        let cleaned = cleanText(level).uppercased()
        guard ["A1", "A2", "B1", "B2", "C1", "C2"].contains(cleaned) else { return nil }
        return cleaned
    }

    private static func cefrFromClassNames(_ classNames: String) -> String? {
        for token in classNames.split(separator: " ") {
            let lowercased = token.lowercased()
            if let level = lowercased.split(separator: "_").last {
                let normalized = normalizeCEFR(String(level))
                if normalized != nil && (lowercased.contains("ox5ksym_") || lowercased.contains("ox3ksym_")) {
                    return normalized
                }
            }
        }
        return nil
    }
}

// MARK: - Errors

enum OxfordError: Error {
    case blocked(statusCode: Int)       // 403/429 — site is blocking us
    case serverError(statusCode: Int)   // 5xx
    case unexpectedStatus(statusCode: Int)
    case parseError                     // HTML structure changed
}
