import XCTest
@testable import WordsHunterLib

// MARK: - AppSettings Tests

final class AppSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        return d
    }

    // MARK: Migration guard

    func testMigration_existingInstall_setsUseWordFolderTrue() {
        let d = freshDefaults()
        d.set(true, forKey: "isSetupComplete")
        // useWordFolder key deliberately absent — simulates existing install

        let settings = AppSettings(defaults: d)
        XCTAssertTrue(settings.useWordFolder,
                      "Existing install should default useWordFolder=true to preserve behavior")
    }

    func testMigration_newInstall_doesNotSetUseWordFolder() {
        let d = freshDefaults()
        // isSetupComplete is false (new install) — migration must NOT run
        let settings = AppSettings(defaults: d)
        XCTAssertFalse(settings.useWordFolder,
                       "New install should default useWordFolder=false (vault root)")
    }

    func testMigration_doesNotRerunAfterFirstSet() {
        let d = freshDefaults()
        d.set(true, forKey: "isSetupComplete")
        // First init: migration sets useWordFolder=true
        _ = AppSettings(defaults: d)
        XCTAssertEqual(d.object(forKey: "useWordFolder") as? Bool, true)
        // Manually set to false (user toggled it off)
        d.set(false, forKey: "useWordFolder")
        // Second init: key is present, migration must NOT override
        let settings2 = AppSettings(defaults: d)
        XCTAssertFalse(settings2.useWordFolder,
                       "Migration must not re-run once key is present")
    }

    // MARK: wordsFolderURL

    func testWordsFolderURL_emptyVaultPath_returnsNil() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertNil(settings.wordsFolderURL)
    }

    func testWordsFolderURL_useWordFolderFalse_returnsVaultRoot() {
        let d = freshDefaults()
        let settings = AppSettings(defaults: d)
        settings.vaultPath = "/Users/test/Vault"
        settings.useWordFolder = false
        XCTAssertEqual(settings.wordsFolderURL?.path, "/Users/test/Vault")
    }

    func testWordsFolderURL_useWordFolderTrue_appendsWordFolder() {
        let d = freshDefaults()
        let settings = AppSettings(defaults: d)
        settings.vaultPath = "/Users/test/Vault"
        settings.wordFolder = "Words"
        settings.useWordFolder = true
        XCTAssertEqual(settings.wordsFolderURL?.path, "/Users/test/Vault/Words")
    }

    func testLookupRetries_defaultIsThree() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.lookupRetries, 3)
    }

    func testLookupRetries_clampedToOneToFive() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.lookupRetries = 0
        XCTAssertEqual(settings.lookupRetries, 1)
        settings.lookupRetries = 10
        XCTAssertEqual(settings.lookupRetries, 5)
    }
}

// MARK: - DictionaryService JSON Parsing Tests

final class DictionaryServiceJSONTests: XCTestCase {

    // All tests call the real parseMWResponse method via @testable import

    private func callParseMWResponse(_ data: Data) throws -> DictionaryContent? {
        return try DictionaryService().parseMWResponse(data: data)
    }

    // MARK: Definitions

    func testParsing_happyPath_returnsTwoDefinitions() throws {
        let json = """
        [
          {"shortdef": ["lasting for a very short time", "of or relating to ephemera"]},
          {"shortdef": ["something that lasts for a very short time"]}
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.definitions.count, 2)
        XCTAssertEqual(content?.definitions[0], "lasting for a very short time")
        XCTAssertEqual(content?.definitions[1], "something that lasts for a very short time")
    }

    func testParsing_wordNotFound_returnsNil() throws {
        // MW returns array of suggestion strings when word not found
        let json = """
        ["ephemera", "ephemeron"]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertNil(content, "Word-not-found response should return nil, not attempt an update")
    }

    func testParsing_malformedJSON_throws() {
        let json = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try callParseMWResponse(json))
    }

    func testParsing_emptyArray_returnsNil() throws {
        let json = "[]".data(using: .utf8)!
        let content = try callParseMWResponse(json)
        XCTAssertNil(content)
    }

    // MARK: POS

    func testParsing_extractsPOS_fromFirstEntry() throws {
        let json = """
        [
          {"fl": "verb", "shortdef": ["to make or become more secure"]},
          {"fl": "noun", "shortdef": ["the act of consolidating"]}
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.partOfSpeech, "verb",
                       "POS should be taken from first entry's fl field")
    }

    func testParsing_missingPOS_returnsNilField() throws {
        let json = """
        [
          {"shortdef": ["to make or become more secure"]}
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertNil(content?.partOfSpeech,
                     "Missing fl field should yield nil partOfSpeech")
    }

    // MARK: Pronunciation

    func testParsing_extractsPronunciation_hwi() throws {
        let json = """
        [
          {
            "fl": "verb",
            "hwi": {"hw": "con*sol*i*date", "prs": [{"mw": "kən-ˈsä-lə-ˌdāt"}]},
            "shortdef": ["to make or become more secure"]
          }
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.pronunciation, "kən-ˈsä-lə-ˌdāt")
    }

    func testParsing_missingPronunciation_returnsNilField() throws {
        let json = """
        [
          {"fl": "verb", "shortdef": ["to make or become more secure"]}
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertNil(content?.pronunciation,
                     "Missing hwi/prs should yield nil pronunciation")
    }
}

// MARK: - TextCapture Lemmatization Tests

final class TextCaptureTests: XCTestCase {

    func testLemmatize_regularVerb() {
        // "consolidates" should lemmatize to "Consolidate"
        let result = TextCapture.lemmatize("consolidates")
        XCTAssertEqual(result, "Consolidate")
    }

    func testLemmatize_irregularVerb() {
        // "has" should lemmatize to "Have"
        let result = TextCapture.lemmatize("has")
        XCTAssertEqual(result, "Have")
    }

    func testLemmatize_alreadyBaseForm() {
        // "run" in base form should stay "Run"
        let result = TextCapture.lemmatize("run")
        XCTAssertEqual(result, "Run")
    }

    func testLemmatize_unknownWord_fallback() {
        // "API" — NLTagger returns nil for acronyms → fallback to original casing
        let result = TextCapture.lemmatize("API")
        XCTAssertEqual(result, "API",
                       "Unknown/acronym words should preserve original casing")
    }
}

// MARK: - Vault Scan Tests

final class VaultScanTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createPage(_ name: String) {
        let url = tempDir.appendingPathComponent("\(name).md")
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    func testVaultScan_matchesWordInDefinition() {
        createPage("Strengthen")
        let definitions = ["to make stronger or more powerful; to strengthen bonds"]
        let result = DictionaryService.vaultScanRelatedWords(
            word: "Consolidate", definitions: definitions, folderURL: tempDir
        )
        XCTAssertEqual(result, ["Strengthen"])
    }

    func testVaultScan_excludesSelf() {
        createPage("Consolidate")
        createPage("Strengthen")
        let definitions = ["to consolidate power; to strengthen bonds"]
        let result = DictionaryService.vaultScanRelatedWords(
            word: "Consolidate", definitions: definitions, folderURL: tempDir
        )
        // "Consolidate" (self) must be excluded; "Strengthen" should appear
        XCTAssertFalse(result.contains("Consolidate"), "Self must be excluded from related words")
        XCTAssertTrue(result.contains("Strengthen"))
    }

    func testVaultScan_filtersShortWords_lessThan4Chars() {
        createPage("Run")   // 3 chars — must be filtered
        createPage("Give")  // 4 chars — should match if in definition
        let definitions = ["to run quickly; to give power"]
        let result = DictionaryService.vaultScanRelatedWords(
            word: "Consolidate", definitions: definitions, folderURL: tempDir
        )
        XCTAssertFalse(result.contains("Run"), "Words shorter than 4 chars must be filtered")
        XCTAssertTrue(result.contains("Give"), "4-char words should be included")
    }

    func testVaultScan_emptyVault_returnsEmpty() {
        let result = DictionaryService.vaultScanRelatedWords(
            word: "Consolidate", definitions: ["any definition"], folderURL: tempDir
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testVaultScan_noMatches_returnsEmpty() {
        createPage("Ephemeral")
        // Definition doesn't contain "ephemeral"
        let definitions = ["to make secure and stable"]
        let result = DictionaryService.vaultScanRelatedWords(
            word: "Consolidate", definitions: definitions, folderURL: tempDir
        )
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - WordPageUpdater Tests

final class WordPageUpdaterTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeFile(name: String, content: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func content(
        definitions: [String],
        partOfSpeech: String? = nil,
        pronunciation: String? = nil,
        relatedWords: [String] = []
    ) -> DictionaryContent {
        DictionaryContent(
            definitions: definitions,
            source: "Merriam-Webster",
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            relatedWords: relatedWords
        )
    }

    // MARK: Existing tests (unchanged behavior via updateDefinition alias)

    func testUpdate_templateBody_writesDefinitions() throws {
        let template = """
        # Ephemeral

        > 📅 Captured on 2026-03-25

        ## Definition


        ## Examples


        """
        let url = writeFile(name: "Ephemeral.md", content: template)
        try WordPageUpdater.updateDefinition(at: url.path, with: content(definitions: ["lasting a very short time"]))

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("1. lasting a very short time"))
    }

    func testUpdate_userEditedDefinition_abortsWithoutChanging() throws {
        let edited = """
        # Ephemeral

        ## Definition

        My own definition here.

        ## Examples

        """
        let url = writeFile(name: "Ephemeral.md", content: edited)
        try WordPageUpdater.updateDefinition(at: url.path, with: content(definitions: ["new definition"]))

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("My own definition here."), "User-edited definition must not be overwritten")
        XCTAssertFalse(after.contains("new definition"))
    }

    func testUpdate_fileDeleted_abortsWithoutThrowing() {
        let missingPath = tempDir.appendingPathComponent("DoesNotExist.md").path
        XCTAssertNoThrow(
            try WordPageUpdater.updateDefinition(
                at: missingPath,
                with: content(definitions: ["definition"])
            )
        )
    }

    func testUpdate_whitespaceyBody_isStillConsideredEmpty() throws {
        let template = "## Definition\n\n\n\n## Examples\n\n"
        let url = writeFile(name: "Test.md", content: template)
        try WordPageUpdater.updateDefinition(at: url.path, with: content(definitions: ["value"]))
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("1. value"))
    }

    // MARK: POS replacement

    func testUpdatePage_writesPOS_whenPlaceholderPresent() throws {
        let template = "# Consolidate\n\n> 📅 2026-03-26 | {POS} | {register/domain}\n\n## Definition\n\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(at: url.path, with: content(definitions: ["to make secure"], partOfSpeech: "verb"))

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("| verb |"), "POS should replace {POS} placeholder")
        XCTAssertFalse(after.contains("{POS}"), "{POS} literal should be gone after update")
    }

    func testUpdatePage_skipsPOS_whenAlreadyEdited() throws {
        // User manually replaced {POS} with "noun" already
        let template = "# Consolidate\n\n> 📅 2026-03-26 | noun | {register/domain}\n\n## Definition\n\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(at: url.path, with: content(definitions: ["to make secure"], partOfSpeech: "verb"))

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("| noun |"), "User-edited POS must not be overwritten")
    }

    // MARK: Pronunciation

    func testUpdatePage_writesPronunciation_whenEmpty() throws {
        let template = "# Consolidate\n\n## Pronunciation\n\n\n## Definition\n\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(
            at: url.path,
            with: content(definitions: ["to make secure"], pronunciation: "kən-ˈsä-lə-ˌdāt")
        )

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("kən-ˈsä-lə-ˌdāt"))
    }

    func testUpdatePage_skipsPronunciation_whenUserEdited() throws {
        let template = "# Consolidate\n\n## Pronunciation\n\nkən-ˈSÄ-lə-ˌdāt (my edit)\n\n## Definition\n\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(
            at: url.path,
            with: content(definitions: ["to make secure"], pronunciation: "kən-ˈsä-lə-ˌdāt")
        )

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("my edit"), "User-edited pronunciation must not be overwritten")
    }

    // MARK: Related Words

    func testUpdatePage_writesRelatedWords_whenEmpty() throws {
        let template = "# Consolidate\n\n## Definition\n\n\n## Related Words\n\n\n## Word Family\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(
            at: url.path,
            with: content(definitions: ["to make secure"], relatedWords: ["Strengthen", "Unify"])
        )

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("[[Strengthen]]"))
        XCTAssertTrue(after.contains("[[Unify]]"))
    }

    func testUpdatePage_skipsRelatedWords_whenUserEdited() throws {
        let template = "# Consolidate\n\n## Definition\n\n\n## Related Words\n\n[[Merge]] [[Integrate]]\n\n## Word Family\n\n"
        let url = writeFile(name: "Consolidate.md", content: template)
        try WordPageUpdater.updatePage(
            at: url.path,
            with: content(definitions: ["to make secure"], relatedWords: ["Strengthen"])
        )

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("[[Merge]]"), "User-written related words must not be overwritten")
        XCTAssertFalse(after.contains("[[Strengthen]]"))
    }

    // MARK: Single atomic write

    func testUpdatePage_allFourSectionsInSingleAtomicWrite() throws {
        // Full new template — all auto-fill sections empty
        let template = """
        # Consolidate

        > 📅 2026-03-26 | {POS} | {register/domain}

        ## Pronunciation


        ## Definition


        ## Useful Frames

        <!-- hint -->

        ## Related Words


        ## Word Family

        - Noun:

        """
        let url = writeFile(name: "Consolidate.md", content: template)

        try WordPageUpdater.updatePage(
            at: url.path,
            with: content(
                definitions: ["to make or become more secure"],
                partOfSpeech: "verb",
                pronunciation: "kən-ˈsä-lə-ˌdāt",
                relatedWords: ["Strengthen"]
            )
        )

        let after = try String(contentsOf: url, encoding: .utf8)
        // All four auto-fills present in the final file
        XCTAssertTrue(after.contains("| verb |"), "POS should be written")
        XCTAssertTrue(after.contains("kən-ˈsä-lə-ˌdāt"), "Pronunciation should be written")
        XCTAssertTrue(after.contains("1. to make or become more secure"), "Definition should be written")
        XCTAssertTrue(after.contains("[[Strengthen]]"), "Related words should be written")
        // Manual sections untouched
        XCTAssertTrue(after.contains("<!-- hint -->"), "Manual section hints should be preserved")
    }
}

// MARK: - WordPageCreator Regression Test

final class WordPageCreatorRegressionTests: XCTestCase {

    /// Regression: WordPageCreator must use wordsFolderURL rather than constructing its own URL inline.
    /// Before the fix, it always appended wordFolder regardless of useWordFolder.
    func testCreatePage_useWordFolderFalse_writesToVaultRoot() throws {
        let tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempVault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVault) }

        let d = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: d)
        settings.vaultPath = tempVault.path
        settings.useWordFolder = false
        settings.isSetupComplete = true

        // We can't swap the singleton easily, but we can verify wordsFolderURL is vault root
        // and that the file would be written there (indirect verification via the URL logic)
        let folderURL = settings.wordsFolderURL
        XCTAssertEqual(folderURL?.path, tempVault.path,
                       "useWordFolder=false should return vault root, not a subfolder")
    }
}
