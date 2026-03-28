import Foundation

// MARK: - URLSession protocol for testability

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - DictionaryContent

struct DictionaryContent {
    let definitions: [String]       // all shortdefs from first entry
    let examples: [String]          // verbal illustrations from def.sseq.sense.dt.vis
    let pos: String?                // functional label from `fl` field
    let pronunciation: String?      // MW phonetic notation from `hwi.prs[0].mw`
    let headword: String?           // syllable-separated hw from hwi.hw, e.g. "pos*it"
    let source: String
}

// MARK: - DictionaryService

/// Fetches definitions from the Merriam-Webster Collegiate Dictionary API.
/// Runs lookups as cancellable background Tasks. Lookup is fire-and-forget:
/// success silently updates the word page; failure leaves the blank template.
///
/// Architecture:
///   startLookup(word:at:)
///       │
///       ├── guard lookupEnabled && !mwApiKey.isEmpty → return early
///       ├── cancel any existing Task for this word
///       └── Task { retry loop → URLSession → JSON parse → WordPageUpdater }
///               │
///               └── defer { lookupTasks[word] = nil }   ← evicts on completion
final class DictionaryService {
    static let shared = DictionaryService()

    private var session: URLSessionProtocol
    private var lookupTasks: [String: Task<Void, Never>] = [:]

    // Dependency injection for tests
    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Start a background lookup for `word` (lemma), writing results to the file at `path`.
    func startLookup(word: String, at path: String) {
        let settings = AppSettings.shared
        guard settings.lookupEnabled, !settings.mwApiKey.isEmpty else { return }

        // Cancel any in-flight task for the same word before starting a new one
        lookupTasks[word]?.cancel()

        let apiKey = settings.mwApiKey
        let retries = settings.lookupRetries
        let session = self.session

        let task = Task<Void, Never> {
            defer { lookupTasks[word] = nil }
            do {
                if let content = try await fetchWithRetries(
                    word: word, apiKey: apiKey, retries: retries, session: session
                ) {
                    try WordPageUpdater.update(at: path, with: content, lemma: word)
                }
            } catch is CancellationError {
                // Task was cancelled — normal, no action needed
            } catch {
                // All retries exhausted or permanent failure — blank definition remains
                print("[DictionaryService] Lookup failed for '\(word)': \(error)")
            }
        }
        lookupTasks[word] = task
    }

    /// Cancel all in-flight lookup tasks. Call from applicationWillTerminate.
    func cancelAll() {
        lookupTasks.values.forEach { $0.cancel() }
        lookupTasks.removeAll()
    }

    // MARK: - Fetch with retry

    /// Fetch the definition with exponential backoff.
    /// Returns nil when the word is not found (MW returns an array of strings, not objects).
    /// Returns nil on permanent 4xx failure (401/403/429) without retrying.
    /// Throws on cancellation.
    private func fetchWithRetries(
        word: String,
        apiKey: String,
        retries: Int,
        session: URLSessionProtocol
    ) async throws -> DictionaryContent? {
        // retries is the number of *additional* attempts: default 3 → 4 total attempts
        // Delays (seconds): first attempt immediate; subsequent: 1, 2, 4, 8, 16, …
        let maxAttempts = retries + 1

        var lastError: Error?
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                let delaySecs = UInt64(pow(2.0, Double(attempt - 1)))  // 1, 2, 4, …
                try await Task.sleep(nanoseconds: delaySecs * 1_000_000_000)
                try Task.checkCancellation()
            }

            do {
                let result = try await fetchOnce(word: word, apiKey: apiKey, session: session)
                return result   // success or word-not-found (nil)
            } catch DictionaryError.permanentFailure {
                return nil      // 4xx — do not retry
            } catch {
                lastError = error
                // network error or 5xx → will retry
            }
        }

        if let err = lastError { throw err }
        return nil
    }

    /// Single HTTP attempt. Returns nil for word-not-found. Throws DictionaryError.permanentFailure for 4xx.
    private func fetchOnce(
        word: String,
        apiKey: String,
        session: URLSessionProtocol
    ) async throws -> DictionaryContent? {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "https://www.dictionaryapi.com/api/v3/references/collegiate/json/\(encoded)?key=\(apiKey)") else {
            return nil
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))

        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            if code == 401 || code == 403 || code == 429 {
                throw DictionaryError.permanentFailure(statusCode: code)
            }
            if code >= 500 {
                throw DictionaryError.serverError(statusCode: code)
            }
        }

        return try parseMWResponse(data: data)
    }

    // MARK: - JSON parsing

    /// Parse MW API response.
    /// MW returns an array: if items are Dicts → definitions found; if items are Strings → word not found.
    /// Extracts: shortdef[0] as definition, fl as pos, hwi.prs[0].mw as pronunciation,
    /// def.sseq.sense.dt.vis entries as examples (MW format codes stripped).
    internal func parseMWResponse(data: Data) throws -> DictionaryContent? {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [Any], !array.isEmpty else { return nil }

        // Word-not-found: array of suggestion strings
        if array.first is String { return nil }

        guard let entries = array as? [[String: Any]] else { return nil }
        guard let firstEntry = entries.first else { return nil }

        // Definitions: all shortdefs from first entry
        guard let shortdefs = firstEntry["shortdef"] as? [String],
              !shortdefs.isEmpty, !shortdefs[0].isEmpty else { return nil }

        // POS: fl field from first entry
        let pos = firstEntry["fl"] as? String

        // Pronunciation and headword from hwi
        let pronunciation: String?
        let headword: String?
        if let hwi = firstEntry["hwi"] as? [String: Any] {
            headword = hwi["hw"] as? String
            if let prs = hwi["prs"] as? [[String: Any]],
               let firstPr = prs.first,
               let mw = firstPr["mw"] as? String {
                pronunciation = mw
            } else {
                pronunciation = nil
            }
        } else {
            pronunciation = nil
            headword = nil
        }

        // Examples: collect vis entries from def.sseq.sense.dt across all entries, strip format codes
        var examples: [String] = []
        for entry in entries {
            guard let defArray = entry["def"] as? [[String: Any]] else { continue }
            for defItem in defArray {
                guard let sseq = defItem["sseq"] as? [[[Any]]] else { continue }
                for sseqGroup in sseq {
                    for senseItem in sseqGroup {
                        guard senseItem.count >= 2,
                              let senseType = senseItem[0] as? String, senseType == "sense",
                              let senseData = senseItem[1] as? [String: Any],
                              let dt = senseData["dt"] as? [[Any]] else { continue }
                        for dtItem in dt {
                            guard dtItem.count >= 2,
                                  let dtType = dtItem[0] as? String, dtType == "vis",
                                  let visArray = dtItem[1] as? [[String: Any]] else { continue }
                            for visEntry in visArray {
                                if let t = visEntry["t"] as? String {
                                    examples.append(stripMWFormatCodes(t))
                                }
                            }
                        }
                    }
                }
            }
        }

        return DictionaryContent(
            definitions: shortdefs,
            examples: examples,
            pos: pos,
            pronunciation: pronunciation,
            headword: headword,
            source: "Merriam-Webster"
        )
    }

    // MARK: - Helpers

    /// Strips MW inline format codes such as {it}, {/it}, {bc}, {ldquo}, {rdquo}, etc.
    private func stripMWFormatCodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\{[^}]+\\}") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

// MARK: - Errors

private enum DictionaryError: Error {
    case permanentFailure(statusCode: Int)   // 401/403/429 — do not retry
    case serverError(statusCode: Int)        // 5xx — retry
}
