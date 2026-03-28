import Foundation

// MARK: - URLSession protocol for testability

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - DictionaryContent

struct DictionaryContent {
    let definitions: [String]       // first shortdef from first 2 entries
    let source: String
    let partOfSpeech: String?       // functional label from `fl` field
    let pronunciation: String?      // MW phonetic notation from `hwi.prs[0].mw`
    var relatedWords: [String] = [] // vault-scanned backlinks (populated after fetch)
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
///       └── Task { retry loop → URLSession → JSON parse → vault scan → WordPageUpdater }
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

    /// Start a background lookup for `word`, writing results to the file at `path`.
    func startLookup(word: String, at path: String) {
        let settings = AppSettings.shared
        guard settings.lookupEnabled, !settings.mwApiKey.isEmpty else { return }

        // Cancel any in-flight task for the same word before starting a new one
        lookupTasks[word]?.cancel()

        let apiKey = settings.mwApiKey
        let retries = settings.lookupRetries
        let session = self.session
        // Capture vault scan parameters at call time (on main thread)
        let useWordFolder = settings.useWordFolder
        let folderURL = settings.wordsFolderURL

        let task = Task<Void, Never> {
            defer { lookupTasks[word] = nil }
            do {
                if var content = try await fetchWithRetries(
                    word: word, apiKey: apiKey, retries: retries, session: session
                ) {
                    // Vault scan for related words — only when word folder is configured
                    if useWordFolder, let folderURL = folderURL {
                        content.relatedWords = DictionaryService.vaultScanRelatedWords(
                            word: word, definitions: content.definitions, folderURL: folderURL
                        )
                    }
                    try WordPageUpdater.updatePage(at: path, with: content)
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

    // MARK: - Vault scan

    /// Scan the word folder for existing pages whose names appear in the definition text.
    /// Returns a sorted list of Obsidian [[link]] targets.
    ///
    /// Rules:
    /// - Only scans `.md` files in `folderURL` (not recursive)
    /// - Skips candidates shorter than 4 chars (noise reduction)
    /// - Excludes the captured word itself
    /// - Whole-word case-insensitive match against joined definition text
    static func vaultScanRelatedWords(word: String, definitions: [String], folderURL: URL) -> [String] {
        let definitionText = definitions.joined(separator: " ").lowercased()
        let wordLower = word.lowercased()

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            return []
        }

        var matches: [String] = []

        for file in files {
            guard file.pathExtension == "md" else { continue }
            let candidate = file.deletingPathExtension().lastPathComponent
            let candidateLower = candidate.lowercased()

            guard candidateLower.count >= 4 else { continue }
            guard candidateLower != wordLower else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: candidateLower))\\b"
            if definitionText.range(of: pattern, options: .regularExpression) != nil {
                matches.append(candidate)
            }
        }

        return matches.sorted()
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
    /// Extracts from first entry: POS (`fl`), pronunciation (`hwi.prs[0].mw`).
    /// Takes first 2 entries × first shortdef each for definitions.
    func parseMWResponse(data: Data) throws -> DictionaryContent? {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [Any], !array.isEmpty else { return nil }

        // Word-not-found: array of suggestion strings
        if array.first is String { return nil }

        guard let entries = array as? [[String: Any]] else { return nil }

        // POS and pronunciation from first entry only
        let firstEntry = entries[0]
        let partOfSpeech = firstEntry["fl"] as? String
        let pronunciation: String? = {
            guard let hwi = firstEntry["hwi"] as? [String: Any],
                  let prs = hwi["prs"] as? [[String: Any]],
                  let first = prs.first,
                  let mw = first["mw"] as? String else { return nil }
            return mw
        }()

        var definitions: [String] = []
        for entry in entries.prefix(2) {
            if let shortdefs = entry["shortdef"] as? [String],
               let first = shortdefs.first {
                definitions.append(first)
            }
        }

        guard !definitions.isEmpty else { return nil }
        return DictionaryContent(
            definitions: definitions,
            source: "Merriam-Webster",
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation
        )
    }
}

// MARK: - Errors

private enum DictionaryError: Error {
    case permanentFailure(statusCode: Int)   // 401/403/429 — do not retry
    case serverError(statusCode: Int)        // 5xx — retry
}
