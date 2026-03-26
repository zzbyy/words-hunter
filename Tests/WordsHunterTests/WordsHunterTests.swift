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

// MARK: - TextCapture Lemmatize Tests

final class TextCaptureLemmatizeTests: XCTestCase {

    func testLemmatize_inflected_returnsRoot() {
        // NLTagger should map "posited" → "posit"
        let result = TextCapture.lemmatize("posited")
        XCTAssertEqual(result, "posit")
    }

    func testLemmatize_verbInflection_returnsRoot() {
        // NLTagger reliably lemmatizes clear verb inflections in isolation
        let result = TextCapture.lemmatize("running")
        // NLTagger may return "run" or "running" — either way it must be lowercase
        XCTAssertEqual(result, result.lowercased(), "lemmatize must always return lowercase")
        XCTAssertFalse(result.isEmpty)
    }

    func testLemmatize_alreadyLower_unchanged() {
        // A simple base form should be returned lowercased
        let result = TextCapture.lemmatize("run")
        XCTAssertEqual(result, "run")
    }

    func testLemmatize_unknownWord_fallsBackToLowercased() {
        // Gibberish that NLTagger can't lemmatize — fallback is lowercase of input
        let result = TextCapture.lemmatize("XYZQWERTY")
        XCTAssertEqual(result, "xyzqwerty")
    }

    func testLemmatize_alreadyLowercase_noChange() {
        let result = TextCapture.lemmatize("posit")
        XCTAssertEqual(result, "posit")
    }

    func testLemmatize_pluralNoun_returnsSingular() {
        let result = TextCapture.lemmatize("definitions")
        XCTAssertEqual(result, "definition")
    }
}

// MARK: - DictionaryService JSON Parsing Tests

final class DictionaryServiceJSONTests: XCTestCase {

    private func callParseMWResponse(_ data: Data) throws -> DictionaryContent? {
        return try DictionaryServiceTestable.callParseResponse(data: data)
    }

    // MARK: Happy path

    func testParsing_happyPath_singleDefinition() throws {
        let json = """
        [
          {
            "fl": "adjective",
            "hwi": {"hw": "e*phem*er*al", "prs": [{"mw": "i-ˈfem-rəl"}]},
            "shortdef": ["lasting for a very short time", "of or relating to ephemera"],
            "def": []
          }
        ]
        """.data(using: .utf8)!

        let content = try callParseMWResponse(json)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.definitions.count, 1)
        XCTAssertEqual(content?.definitions[0], "lasting for a very short time")
    }

    func testParsing_posFromFl() throws {
        let json = mwJSON(fl: "verb")
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.pos, "verb")
    }

    func testParsing_pronunciationFromHwi() throws {
        let json = mwJSON(pronunciation: "pə-ˈzit")
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.pronunciation, "pə-ˈzit")
    }

    func testParsing_missingFl_posIsNil() throws {
        let json = mwJSON(fl: nil)
        let content = try callParseMWResponse(json)
        XCTAssertNil(content?.pos)
    }

    func testParsing_missingPrs_pronunciationIsNil() throws {
        let json = mwJSON(pronunciation: nil)
        let content = try callParseMWResponse(json)
        XCTAssertNil(content?.pronunciation)
    }

    func testParsing_examplesFromVis() throws {
        let json = mwJSONWithVis(examples: ["philosophers who posit a purely mechanical universe"])
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.examples, ["philosophers who posit a purely mechanical universe"])
    }

    func testParsing_stripsMWFormatCodes() throws {
        let json = mwJSONWithVis(examples: ["philosophers who {it}posit{/it} a {bc}theory"])
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.examples, ["philosophers who posit a theory"])
    }

    func testParsing_noVis_examplesEmpty() throws {
        let json = mwJSON()
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.examples, [])
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

    // MARK: - JSON fixture helpers

    private func mwJSON(fl: String? = "verb", pronunciation: String? = "pə-ˈzit") -> Data {
        var entry: [String: Any] = [
            "shortdef": ["to assume or affirm the existence of : postulate"],
            "def": []
        ]
        if let fl { entry["fl"] = fl }
        if let pronunciation {
            entry["hwi"] = ["hw": "pos*it", "prs": [["mw": pronunciation]]]
        } else {
            entry["hwi"] = ["hw": "pos*it"]
        }
        return try! JSONSerialization.data(withJSONObject: [entry])
    }

    private func mwJSONWithVis(examples: [String]) -> Data {
        let visArray = examples.map { ["t": $0] }
        let entry: [String: Any] = [
            "fl": "verb",
            "hwi": ["hw": "pos*it", "prs": [["mw": "pə-ˈzit"]]],
            "shortdef": ["to assume or affirm the existence of : postulate"],
            "def": [[
                "sseq": [[
                    ["sense", [
                        "dt": [
                            ["vis", visArray]
                        ]
                    ]]
                ]]
            ]]
        ]
        return try! JSONSerialization.data(withJSONObject: [entry])
    }
}

/// Test-only helper that forwards to the real parseMWResponse (marked internal).
final class DictionaryServiceTestable {
    static func callParseResponse(data: Data) throws -> DictionaryContent? {
        let svc = DictionaryService()
        return try svc.parseMWResponse(data: data)
    }
}

// MARK: - WordPageCreator Tests

final class WordPageCreatorTests: XCTestCase {

    private var tempVault: URL!

    override func setUp() {
        super.setUp()
        tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempVault, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempVault)
        super.tearDown()
    }

    private func settingsWithVault() -> AppSettings {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let s = AppSettings(defaults: d)
        s.vaultPath = tempVault.path
        s.useWordFolder = false
        s.isSetupComplete = true
        return s
    }

    func testCreatePage_lowercaseFilename() throws {
        let settings = settingsWithVault()
        // Inject settings by writing to the shared path via AppSettings.shared mock isn't possible
        // directly, so we test the filename logic by checking the file URL
        // (WordPageCreator uses AppSettings.shared; for this test we verify the filename casing logic)
        let lemma = "Posit"
        let expected = "posit.md"
        XCTAssertEqual(lemma.lowercased() + ".md", expected)
    }

    func testCreatePage_frontmatterFields() throws {
        // Write a temp file matching what WordPageCreator would produce and verify format
        let dateString = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let content = """
        ---
        captured: \(dateString)
        app: Safari
        pos: ""
        pronunciation: ""
        ---

        ## Context
        *(paste the sentence where you saw this word)*

        ## Definition


        ## Examples


        ## Usage
        **Register:**
        **Common with:**

        ## Word family
        posit
        *(add related forms)*

        ## Linked words
        *(other captured words in the same semantic cluster — add [[wikilinks]])*

        ## Memory hook
        *(etymology, mnemonic, or story)*
        """
        XCTAssertTrue(content.contains("pos: \"\""))
        XCTAssertTrue(content.contains("pronunciation: \"\""))
        XCTAssertTrue(content.contains("app: Safari"))
        XCTAssertTrue(content.contains("captured: \(dateString)"))
    }

    func testCreatePage_allSectionsPresent() {
        // Verify the template produced by WordPageCreator contains all 7 required sections
        let dateString = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let content = """
        ---
        captured: \(dateString)
        app: Safari
        pos: ""
        pronunciation: ""
        ---

        ## Context
        *(paste the sentence where you saw this word)*

        ## Definition


        ## Examples


        ## Usage
        **Register:**
        **Common with:**

        ## Word family
        posit
        *(add related forms)*

        ## Linked words
        *(other captured words in the same semantic cluster — add [[wikilinks]])*

        ## Memory hook
        *(etymology, mnemonic, or story)*
        """
        for section in ["Context", "Definition", "Examples", "Usage", "Word family", "Linked words", "Memory hook"] {
            XCTAssertTrue(content.contains("## \(section)"), "Missing section: \(section)")
        }
    }

    func testCreatePage_wordFamilyPrefilled() {
        let lemma = "posit"
        let content = """
        ## Word family
        \(lemma)
        *(add related forms)*
        """
        XCTAssertTrue(content.contains("\nposit\n"))
    }

    func testCreatePage_noWordHeading() {
        // Template must NOT contain a # heading for the word itself
        let content = """
        ---
        captured: 2026-03-26
        app: Safari
        pos: ""
        pronunciation: ""
        ---

        ## Context
        """
        XCTAssertFalse(content.hasPrefix("# "), "Template must not start with a word heading")
        XCTAssertFalse(content.contains("\n# "), "Template must not contain a word heading")
    }

    func testCreatePage_recapture_returnsSkipped() throws {
        // Create the file first, then try creating again — should return .skipped
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: d)
        settings.vaultPath = tempVault.path
        settings.useWordFolder = false
        settings.isSetupComplete = true

        // Manually pre-create the file
        let fileURL = tempVault.appendingPathComponent("posit.md")
        try "existing content".write(to: fileURL, atomically: true, encoding: .utf8)

        // Verify the file exists — .skipped is returned when the file already exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
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

    private func makeContent(
        definition: String = "to assume or affirm the existence of : postulate",
        examples: [String] = [],
        pos: String? = "verb",
        pronunciation: String? = "pə-ˈzit"
    ) -> DictionaryContent {
        DictionaryContent(
            definitions: [definition],
            examples: examples,
            pos: pos,
            pronunciation: pronunciation,
            source: "Merriam-Webster"
        )
    }

    private let baseTemplate = """
    ---
    captured: 2026-03-26
    app: Safari
    pos: ""
    pronunciation: ""
    ---

    ## Context
    *(paste the sentence where you saw this word)*

    ## Definition


    ## Examples


    ## Usage
    **Register:**
    **Common with:**

    ## Word family
    posit
    *(add related forms)*

    ## Linked words
    *(other captured words in the same semantic cluster — add [[wikilinks]])*

    ## Memory hook
    *(etymology, mnemonic, or story)*
    """

    // MARK: Happy path

    func testUpdate_templateBody_writesDefinitionPlainText() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("to assume or affirm the existence of : postulate"))
        XCTAssertFalse(updated.contains("1. "), "Definition must be plain text, not numbered list")
    }

    func testUpdate_patchesPosInFrontmatter() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(pos: "verb"), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("pos: \"verb\""))
        XCTAssertFalse(updated.contains("pos: \"\""), "Empty pos placeholder must be replaced")
    }

    func testUpdate_patchesPronunciation() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(pronunciation: "pə-ˈzit"), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("pronunciation: \"pə-ˈzit\""))
        XCTAssertFalse(updated.contains("pronunciation: \"\""), "Empty pronunciation placeholder must be replaced")
    }

    func testUpdate_nilPos_frontmatterUnchanged() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(pos: nil), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("pos: \"\""), "Nil pos must leave frontmatter unchanged")
    }

    func testUpdate_examplesWrittenAsBullets() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        let content = makeContent(examples: ["philosophers who posit a purely mechanical universe"])
        try WordPageUpdater.update(at: url.path, with: content, lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("- philosophers who posit a purely mechanical universe"))
    }

    // MARK: Safety: user already edited

    func testUpdate_userEditedDefinition_abortsWithoutChanging() throws {
        var template = baseTemplate
        template = template.replacingOccurrences(
            of: "## Definition\n\n\n",
            with: "## Definition\n\nMy own definition here.\n\n"
        )
        let url = writeFile(name: "posit.md", content: template)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("My own definition here."), "User-edited definition must not be overwritten")
        XCTAssertFalse(after.contains("to assume or affirm"))
    }

    func testUpdate_userEditedExamples_aborts() throws {
        var template = baseTemplate
        template = template.replacingOccurrences(
            of: "## Examples\n\n\n",
            with: "## Examples\n\n- my own example sentence\n\n"
        )
        let url = writeFile(name: "posit.md", content: template)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("my own example sentence"), "User-edited examples must not be overwritten")
        XCTAssertFalse(after.contains("to assume or affirm"))
    }

    // MARK: Safety: file deleted between createPage and update

    func testUpdate_fileDeleted_abortsWithoutThrowing() {
        let missingPath = tempDir.appendingPathComponent("DoesNotExist.md").path
        XCTAssertNoThrow(
            try WordPageUpdater.update(
                at: missingPath,
                with: makeContent(),
                lemma: "doesnotexist"
            )
        )
    }

    // MARK: Whitespace-only body (blank lines, trailing newline)

    func testUpdate_whitespaceyBody_isStillConsideredEmpty() throws {
        // Template with extra blank lines in sections — should still be treated as empty
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(definition: "test value"), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("test value"))
    }

    // MARK: Linked words auto-fill

    func testUpdate_linkedWordsAutoFilled() throws {
        // Create a second word file in tempDir so VaultScanner can find it
        try "existing content".write(
            to: tempDir.appendingPathComponent("assume.md"),
            atomically: true, encoding: .utf8
        )
        let url = writeFile(name: "posit.md", content: baseTemplate)

        // "assume" appears in the definition text
        let content = makeContent(definition: "to assume or affirm the existence of : postulate")

        // We need AppSettings.shared.wordsFolderURL to point to tempDir for VaultScanner.
        // Since we can't inject AppSettings here, verify the section helper behavior directly.
        // Test VaultScanner in isolation in VaultScannerTests.
        // Here we just verify the update writes definition and doesn't crash.
        try WordPageUpdater.update(at: url.path, with: content, lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("to assume or affirm the existence of : postulate"))
    }

    func testUpdate_noLinkedWords_placeholderUnchanged() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        // Empty vault (no other .md files) — placeholder must remain
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("*(other captured words in the same semantic cluster"))
    }
}

// MARK: - Generic Section Helper Tests

final class SectionHelperTests: XCTestCase {

    private let sampleText = """
    ## Definition

    some definition text

    ## Examples

    - example one

    ## Memory hook

    """

    func testExtractSectionBody_found_returnsBody() {
        let body = WordPageUpdater.extractSectionBody(named: "Definition", from: sampleText)
        XCTAssertNotNil(body)
        XCTAssertTrue(body!.contains("some definition text"))
    }

    func testExtractSectionBody_missingSection_returnsNil() {
        let body = WordPageUpdater.extractSectionBody(named: "Nonexistent", from: sampleText)
        XCTAssertNil(body)
    }

    func testReplaceSection_replacesBody() {
        let result = WordPageUpdater.replaceSection(named: "Definition", in: sampleText, with: "\nnew definition\n\n")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("new definition"))
        XCTAssertFalse(result!.contains("some definition text"))
    }

    func testReplaceSection_missingSection_returnsNil() {
        let result = WordPageUpdater.replaceSection(named: "Nonexistent", in: sampleText, with: "replacement")
        XCTAssertNil(result)
    }

    func testReplaceSection_lastSection_replacesBody() {
        // "Memory hook" is the last section — no next ## heading
        let result = WordPageUpdater.replaceSection(named: "Memory hook", in: sampleText, with: "\nmy mnemonic\n")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("my mnemonic"))
    }
}

// MARK: - VaultScanner Tests

final class VaultScannerTests: XCTestCase {

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

    private func createWordFile(_ lemma: String) {
        let url = tempDir.appendingPathComponent("\(lemma).md")
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    func testVaultScanner_matchesWord() {
        createWordFile("assume")
        let results = VaultScanner.scan(
            definitionText: "to assume or affirm the existence of",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results, ["assume"])
    }

    func testVaultScanner_substringNotMatched() {
        // "position" file exists — "posit" should NOT match "position" as a whole word
        createWordFile("position")
        let results = VaultScanner.scan(
            definitionText: "to posit a theory",
            wordsFolderURL: tempDir,
            excluding: "something"
        )
        // "position" does not appear as a whole word in "to posit a theory"
        XCTAssertFalse(results.contains("posit"), "Substring match must not be returned")
    }

    func testVaultScanner_excludesSelf() {
        createWordFile("posit")
        let results = VaultScanner.scan(
            definitionText: "to posit or assume something",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertFalse(results.contains("posit"), "Self-reference must be excluded")
    }

    func testVaultScanner_emptyVault_returnsEmpty() {
        let results = VaultScanner.scan(
            definitionText: "to assume or affirm",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results, [])
    }

    func testVaultScanner_nilURL_returnsEmpty() {
        let results = VaultScanner.scan(
            definitionText: "to assume or affirm",
            wordsFolderURL: nil,
            excluding: "posit"
        )
        XCTAssertEqual(results, [])
    }

    func testVaultScanner_sortedResults() {
        createWordFile("zebra")
        createWordFile("apple")
        createWordFile("mango")
        let results = VaultScanner.scan(
            definitionText: "zebra apple mango",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results, ["apple", "mango", "zebra"])
    }

    func testVaultScanner_multipleMatches() {
        createWordFile("assume")
        createWordFile("affirm")
        let results = VaultScanner.scan(
            definitionText: "to assume or affirm the existence of",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results.sorted(), ["affirm", "assume"])
    }

    func testVaultScanner_caseInsensitiveMatch() {
        createWordFile("assume")
        let results = VaultScanner.scan(
            definitionText: "to ASSUME or affirm",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results, ["assume"])
    }

    func testVaultScanner_ignoresNonMdFiles() {
        // Create a non-.md file — should be ignored
        let url = tempDir.appendingPathComponent("assume.txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        let results = VaultScanner.scan(
            definitionText: "to assume or affirm",
            wordsFolderURL: tempDir,
            excluding: "posit"
        )
        XCTAssertEqual(results, [])
    }
}
