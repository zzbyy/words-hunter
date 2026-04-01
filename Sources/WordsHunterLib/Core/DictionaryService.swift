import Foundation

// MARK: - DictionaryContent (unified model)

/// Unified dictionary content model used by Cambridge (primary) and MW (fallback).
/// Cambridge fills all fields; MW fills a subset (no CEFR, patterns, corpus examples).
struct DictionaryContent {
    let headword: String
    let pronunciationBrE: String?   // "/ˈdelɪɡət/"
    let pronunciationAmE: String?   // "/ˈdelɪɡət/"
    let entries: [OxfordEntry]      // one per POS (noun, verb, etc.)
    let nearbyWords: [NearbyWord]
    let corpusExamples: [String]    // Cambridge English Corpus examples
    let wordFamily: [WordFamilyEntry]   // Cambridge word family box (empty for MW)
    let source: String              // "Cambridge Dictionary" or "Merriam-Webster"
}

// MARK: - URLSession protocol for testability

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - Legacy MW response (internal, for adapter)

/// Raw MW API response — kept for fallback parsing, then adapted to DictionaryContent.
struct MWRawContent {
    let definitions: [String]
    let examples: [String]
    let pos: String?
    let pronunciation: String?
    let headword: String?
}

// MARK: - DictionaryService

/// Orchestrates dictionary lookups with Oxford as primary and MW as fallback.
///
/// Priority chain:
///   1. Oxford Learner's Dictionary (HTML scraping, no API key needed)
///   2. Merriam-Webster Collegiate API (if API key is configured)
///   3. Blank template (silent failure)
///
/// Architecture:
///   startLookup(word:at:)
///       │
///       ├── guard lookupEnabled → return early
///       ├── cancel any existing Task for this word
///       └── Task {
///               try Oxford → success → WordPageUpdater
///               catch → try MW (if key) → adapt → WordPageUpdater
///               catch → print error, leave blank
///           }
final class DictionaryService {
    static let shared = DictionaryService()

    private var session: URLSessionProtocol
    private struct LookupTaskRecord {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var lookupTasks: [String: LookupTaskRecord] = [:]
    private let lookupTasksLock = NSLock()

    /// Serial queue for Cambridge lookups — ensures only one scraping request at a time
    /// to be polite to Cambridge's servers. MW fallback is not serialized.
    private let oxfordQueue = AsyncSerialQueue()

    // Dependency injection for tests
    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Start a background lookup for `word` (lemma), writing results to the file at `path`.
    func startLookup(word: String, at path: String) {
        let settings = AppSettings.shared
        guard settings.lookupEnabled else { return }

        // Cancel any in-flight task for the same word before starting a new one
        cancelLookupTask(for: word)

        let mwApiKey = settings.mwApiKey
        let retries = settings.lookupRetries
        let session = self.session
        let queue = self.oxfordQueue
        let taskID = UUID()

        let task = Task<Void, Never> {
            defer { self.clearLookupTask(for: word, id: taskID) }
            do {
                // Try Cambridge first (serialized)
                let content: DictionaryContent? = try await queue.run {
                    try await self.fetchFromCambridge(
                        word: word, retries: retries, session: session
                    )
                }

                if let content = content {
                    try WordPageUpdater.update(at: path, with: content, lemma: word)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                print("[DictionaryService] Cambridge failed for '\(word)': \(error)")
            }

            // Oxford failed — try MW fallback if API key is configured
            if !mwApiKey.isEmpty {
                do {
                    if let content = try await fetchFromMW(
                        word: word, apiKey: mwApiKey, retries: retries, session: session
                    ) {
                        try WordPageUpdater.update(at: path, with: content, lemma: word)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    print("[DictionaryService] MW fallback also failed for '\(word)': \(error)")
                }
            }

            // Both sources failed — blank template remains
        }
        storeLookupTask(task, for: word, id: taskID)
    }

    /// Cancel all in-flight lookup tasks. Call from applicationWillTerminate.
    func cancelAll() {
        let tasks = allLookupTasks()
        tasks.forEach { $0.cancel() }

        lookupTasksLock.lock()
        lookupTasks.removeAll()
        lookupTasksLock.unlock()
    }

    // MARK: - Cambridge fetch

    private func fetchFromCambridge(
        word: String, retries: Int, session: URLSessionProtocol
    ) async throws -> DictionaryContent? {
        let maxAttempts = retries + 1
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                let delaySecs = UInt64(pow(2.0, Double(attempt)))  // 2, 4, 8, …
                try await Task.sleep(nanoseconds: delaySecs * 1_000_000_000)
                try Task.checkCancellation()
            }

            do {
                return try await CambridgeScraper.lookup(word: word, session: session)
            } catch CambridgeError.blocked {
                return nil  // blocked — don't retry, fall through to MW
            } catch {
                lastError = error
            }
        }

        if let err = lastError { throw err }
        return nil
    }

    // MARK: - MW fetch + retry (kept for fallback)

    private func fetchFromMW(
        word: String, apiKey: String, retries: Int, session: URLSessionProtocol
    ) async throws -> DictionaryContent? {
        let maxAttempts = retries + 1
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                let delaySecs = UInt64(pow(2.0, Double(attempt - 1)))
                try await Task.sleep(nanoseconds: delaySecs * 1_000_000_000)
                try Task.checkCancellation()
            }

            do {
                let result = try await fetchMWOnce(word: word, apiKey: apiKey, session: session)
                return result
            } catch DictionaryError.permanentFailure {
                return nil
            } catch {
                lastError = error
            }
        }

        if let err = lastError { throw err }
        return nil
    }

    /// Single MW HTTP attempt. Returns nil for word-not-found.
    private func fetchMWOnce(
        word: String, apiKey: String, session: URLSessionProtocol
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

        guard let raw = try parseMWResponse(data: data) else { return nil }
        return adaptMWContent(raw, word: word)
    }

    // MARK: - MW JSON parsing (kept for fallback)

    /// Parse MW API response into MWRawContent.
    internal func parseMWResponse(data: Data) throws -> MWRawContent? {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [Any], !array.isEmpty else { return nil }

        // Word-not-found: array of suggestion strings
        if array.first is String { return nil }

        guard let entries = array as? [[String: Any]] else { return nil }
        guard let firstEntry = entries.first else { return nil }

        guard let shortdefs = firstEntry["shortdef"] as? [String],
              !shortdefs.isEmpty, !shortdefs[0].isEmpty else { return nil }

        let pos = firstEntry["fl"] as? String

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

        // Examples: collect vis entries
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

        return MWRawContent(
            definitions: shortdefs,
            examples: examples,
            pos: pos,
            pronunciation: pronunciation,
            headword: headword
        )
    }

    /// Adapt MW raw content into unified DictionaryContent model.
    private func adaptMWContent(_ mw: MWRawContent, word: String) -> DictionaryContent {
        var senses: [OxfordSense] = []
        for (i, def) in mw.definitions.enumerated() {
            let example = i < mw.examples.count ? [mw.examples[i]] : []
            senses.append(OxfordSense(
                cefrLevel: nil,
                definition: def,
                examples: example,
                extraExamples: []
            ))
        }

        let entry = OxfordEntry(
            pos: mw.pos,
            cefrLevel: nil,
            senses: senses,
            collocations: []
        )

        let syllableDisplay = mw.headword?.replacingOccurrences(of: "*", with: "·")

        return DictionaryContent(
            headword: syllableDisplay ?? word,
            pronunciationBrE: mw.pronunciation.map { "/\($0)/" },
            pronunciationAmE: nil,
            entries: [entry],
            nearbyWords: [],
            corpusExamples: [],
            wordFamily: [],
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

    // MARK: - Lookup task bookkeeping

    private func cancelLookupTask(for word: String) {
        lookupTasksLock.lock()
        let existingTask = lookupTasks[word]?.task
        lookupTasksLock.unlock()
        existingTask?.cancel()
    }

    private func storeLookupTask(_ task: Task<Void, Never>, for word: String, id: UUID) {
        lookupTasksLock.lock()
        lookupTasks[word] = LookupTaskRecord(id: id, task: task)
        lookupTasksLock.unlock()
    }

    private func clearLookupTask(for word: String, id: UUID) {
        lookupTasksLock.lock()
        if lookupTasks[word]?.id == id {
            lookupTasks[word] = nil
        }
        lookupTasksLock.unlock()
    }

    private func allLookupTasks() -> [Task<Void, Never>] {
        lookupTasksLock.lock()
        let tasks = lookupTasks.values.map(\.task)
        lookupTasksLock.unlock()
        return tasks
    }
}

// MARK: - Errors

private enum DictionaryError: Error {
    case permanentFailure(statusCode: Int)   // MW: 401/403/429 — do not retry
    case serverError(statusCode: Int)        // MW: 5xx — retry
}

// MARK: - AsyncSerialQueue

/// Lightweight serial queue for async operations. Ensures only one operation runs at a time.
actor AsyncSerialQueue {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Run an async operation, waiting for any previous operation to complete first.
    func run<T>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        if isRunning {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isRunning = true
        defer {
            if waiters.isEmpty {
                isRunning = false
            } else {
                let next = waiters.removeFirst()
                next.resume()
            }
        }

        return try await operation()
    }
}
