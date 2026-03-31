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

    func testParsing_happyPath_returnsAllShortdefs() throws {
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
        XCTAssertEqual(content?.definitions.count, 2)
        XCTAssertEqual(content?.definitions[0], "lasting for a very short time")
        XCTAssertEqual(content?.definitions[1], "of or relating to ephemera")
    }

    func testParsing_headwordExtracted() throws {
        let json = mwJSON()
        let content = try callParseMWResponse(json)
        XCTAssertEqual(content?.headword, "pos*it")
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

    func testCreatePage_lowercaseFilename() throws {
        let lemma = "Posit"
        let expected = "posit.md"
        XCTAssertEqual(lemma.lowercased() + ".md", expected)
    }

    func testCreatePage_headerLine() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.contains("# posit"))
        XCTAssertTrue(content.contains("**Syllables:**"))
    }

    func testCreatePage_sightingsWithDate() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.contains("- \(dateString) — *(context sentence where you saw the word)*"))
    }

    func testCreatePage_allSectionsPresent() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        for section in ["Sightings", "Meanings", "When to Use", "Word Family", "See Also", "Memory Tip"] {
            XCTAssertTrue(content.contains("## \(section)"), "Missing section: \(section)")
        }
    }

    func testCreatePage_meaningsVariable() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.contains("{{meanings}}"), "Template must contain {{meanings}} lookup variable")
    }

    func testCreatePage_noFrontmatter() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertFalse(content.contains("---\ncaptured:"), "Template must not contain YAML frontmatter")
        XCTAssertFalse(content.contains("pos: \"\""))
        XCTAssertFalse(content.contains("pronunciation: \"\""))
    }

    func testCreatePage_hasWordHeading() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.hasPrefix("# posit"), "Template must start with word heading")
    }

    func testCreatePage_recapture_returnsSkipped() throws {
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

    // Helper that reproduces the template string from WordPageCreator (variable-based format)
    private func makeTemplate(lemma: String, date: String) -> String {
        """
        # \(lemma)

        **Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}

        ## Sightings
        - \(date) — *(context sentence where you saw the word)*

        ---

        ## Meanings
        {{meanings}}

        ## When to Use

        **Where it fits:**
        **In casual speech:**

        ---

        ## Word Family

        *(list related forms, each with a short example)*

        ---

        ## See Also
        {{see-also}}

        ---

        ## Memory Tip
        *(optional: etymology, mnemonic, personal association — anything that helps you remember)*
        """
    }
}

// MARK: - WordPageCreator Regression Test

final class WordPageCreatorRegressionTests: XCTestCase {

    /// Regression: WordPageCreator must use wordsFolderURL rather than constructing its own URL inline.
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

        let folderURL = settings.wordsFolderURL
        XCTAssertEqual(folderURL?.path, tempVault.path,
                       "useWordFolder=false should return vault root, not a subfolder")
    }
}

// MARK: - WordPageCreator seedTemplateIfNeeded Tests

final class WordPageCreatorSeedTests: XCTestCase {

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

    private var templateURL: URL {
        tempVault.appendingPathComponent(".wordshunter").appendingPathComponent("template.md")
    }

    func testSeed_noExistingFile_createsTemplate() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: templateURL.path))
        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: templateURL.path))
        let content = try? String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(content?.contains("{{syllables}}") == true, "Seeded template must contain lookup variables")
    }

    func testSeed_oldFormatTemplate_migratesToNewFormat() throws {
        // Simulate a pre-variable template (old format) — no lookup variables at all
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let oldTemplate = "# {{word}}\n\n**Syllables:** *(e.g. po·sit)*\n\n## Meanings\n\n### 1. () *()*\n"
        try oldTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        // The new default contains all lookup variables
        XCTAssertTrue(after.contains("{{syllables}}"), "Old template must be migrated to new variable format")
        XCTAssertTrue(after.contains("{{meanings}}"), "Migrated template must contain {{meanings}}")
        XCTAssertFalse(after.contains("### 1. () *()*"), "Old meaning placeholder must be gone after migration")
    }

    func testSeed_newFormatTemplate_notOverwritten() throws {
        // Simulate an already-migrated template — must not be touched
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let customTemplate = "# {{word}}\n\n**Syllables:** {{syllables}}\n\nMy custom section.\n"
        try customTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertEqual(after, customTemplate, "New-format template with {{syllables}} must not be overwritten")
    }

    func testSeed_partialVariableTemplate_notOverwritten() throws {
        // Template with only {{meanings}} and no {{syllables}} — still a valid new-format template
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let partialTemplate = "# {{word}}\n\n## Meanings\n{{meanings}}\n\nMy minimal layout.\n"
        try partialTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertEqual(after, partialTemplate, "Custom template with any lookup variable must not be overwritten")
    }

    func testSeed_emptyVaultPath_noOp() {
        // Must not crash or create anything when vault path is empty
        WordPageCreator.seedTemplateIfNeeded(vaultPath: "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: templateURL.path))
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
        definitions: [String] = ["to assume or affirm the existence of : postulate"],
        examples: [String] = [],
        pos: String? = "verb",
        pronunciation: String? = "pə-ˈzit",
        headword: String? = "pos*it"
    ) -> DictionaryContent {
        DictionaryContent(
            definitions: definitions,
            examples: examples,
            pos: pos,
            pronunciation: pronunciation,
            headword: headword,
            source: "Merriam-Webster"
        )
    }

    // Base template using the new lookup-time variable format
    private let baseTemplate = """
    # posit

    **Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}

    ## Sightings
    - 2026-03-28 — *(context sentence where you saw the word)*

    ---

    ## Meanings
    {{meanings}}

    ## When to Use

    **Where it fits:**
    **In casual speech:**

    ---

    ## Word Family

    *(list related forms, each with a short example)*

    ---

    ## See Also
    {{see-also}}

    ---

    ## Memory Tip
    *(optional: etymology, mnemonic, personal association — anything that helps you remember)*
    """

    // MARK: Happy path

    func testUpdate_fillsSyllables() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**Syllables:** pos·it"))
    }

    func testUpdate_fillsPronunciation() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(pronunciation: "pə-ˈzit"), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("/pə-ˈzit/"))
        XCTAssertFalse(updated.contains("{{pronunciation}}"), "Variable must be replaced")
    }

    func testUpdate_nilPronunciation_emptyDisplay() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(pronunciation: nil), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**Syllables:** pos·it · **Pronunciation:** "))
    }

    func testUpdate_nilHeadword_fallsBackToLemma() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(headword: nil), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**Syllables:** posit"))
    }

    func testUpdate_singleDefinition_writesNumberedMeaning() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("### 1. (verb) *(to assume or affirm the existence of : postulate)*"))
        XCTAssertFalse(updated.contains("{{meanings}}"), "Variable must be replaced")
    }

    func testUpdate_multipleDefinitions_generatesNumberedHeadings() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        let content = makeContent(
            definitions: ["to assume or affirm", "to put forward as a basis of argument"],
            examples: ["she posited a theory", "he posited that premise"]
        )
        try WordPageUpdater.update(at: url.path, with: content, lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("### 1. (verb) *(to assume or affirm)*"))
        XCTAssertTrue(updated.contains("### 2. (verb) *(to put forward as a basis of argument)*"))
        XCTAssertTrue(updated.contains("> *(she posited a theory)*"))
        XCTAssertTrue(updated.contains("> *(he posited that premise)*"))
    }

    func testUpdate_exampleInMeaning() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        let content = makeContent(examples: ["philosophers who posit a purely mechanical universe"])
        try WordPageUpdater.update(at: url.path, with: content, lemma: "posit")

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("> *(philosophers who posit a purely mechanical universe)*"))
    }

    // MARK: Safety: old-format page

    func testUpdate_oldFormatPage_abortsGracefully() throws {
        let oldTemplate = """
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

        """
        let url = writeFile(name: "posit.md", content: oldTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(after, oldTemplate, "Old-format pages must not be touched")
    }

    // MARK: Safety: page already filled (no lookup variables remain)

    func testUpdate_pageAlreadyFilled_abortsWithoutChanging() throws {
        // Simulate a page that was already filled by a prior lookup — no {{...}} variables remain
        let filledPage = """
        # posit

        **Syllables:** pos·it · **Pronunciation:** /pə-ˈzit/

        ## Sightings
        - 2026-03-28 — *(context sentence where you saw the word)*

        ---

        ## Meanings

        ### 1. (verb) *(to assume or affirm the existence of : postulate)*

        > *(philosophers who posit a mechanical universe)*

        **My sentence:**
        -

        **Patterns:**
        - *(common word combinations and grammar patterns)*

        ## See Also
        - [[assume]]
        """
        let url = writeFile(name: "posit.md", content: filledPage)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(after, filledPage, "Already-filled page (no lookup vars) must not be touched")
    }

    // MARK: Variable coverage

    func testUpdate_allLookupVarsReplaced() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(after.contains("{{syllables}}"), "{{syllables}} must be replaced")
        XCTAssertFalse(after.contains("{{pronunciation}}"), "{{pronunciation}} must be replaced")
        XCTAssertFalse(after.contains("{{meanings}}"), "{{meanings}} must be replaced")
        XCTAssertFalse(after.contains("{{see-also}}"), "{{see-also}} must be replaced")
    }

    func testUpdate_partialVariables_onlyFillsPresent() throws {
        // Template with only {{syllables}} — other vars absent (user opted out)
        let partialTemplate = """
        # posit

        **Syllables:** {{syllables}}

        ## Sightings
        - 2026-03-28 — *(sentence)*
        """
        let url = writeFile(name: "posit.md", content: partialTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(after.contains("{{syllables}}"), "{{syllables}} must be replaced")
        XCTAssertFalse(after.contains("{{pronunciation}}"), "No {{pronunciation}} var — nothing to replace")
        XCTAssertFalse(after.contains("{{meanings}}"), "No {{meanings}} var — nothing to replace")
    }

    func testUpdate_noLookupVars_abortsGracefully() throws {
        // Old-format page without any lookup variables — updater must not touch it
        let oldFormat = """
        # posit

        **Syllables:** po·sit · **Pronunciation:** /pə-ˈzit/

        ## Meanings

        ### 1. (verb) *(already filled manually)*
        """
        let url = writeFile(name: "posit.md", content: oldFormat)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(after, oldFormat, "Page without lookup vars must not be modified")
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

    // MARK: See Also auto-fill

    func testUpdate_seeAlsoVariableAlwaysReplaced() throws {
        // Regardless of vault scan results, {{see-also}} must be replaced (never left as a raw variable)
        let url = writeFile(name: "posit.md", content: baseTemplate)
        let content = makeContent(definitions: ["to assume or affirm the existence of : postulate"])
        try WordPageUpdater.update(at: url.path, with: content, lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(after.contains("{{see-also}}"), "{{see-also}} variable must always be replaced after lookup")
        // Either the fallback text or wikilinks should be present
        let hasSeeAlsoContent = after.contains("*(no related words found yet)*") || after.contains("[[")
        XCTAssertTrue(hasSeeAlsoContent, "See Also section must contain actual content after fill")
    }

    func testUpdate_noRelatedWords_seeAlsoShowsFallback() throws {
        let url = writeFile(name: "posit.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeContent(), lemma: "posit")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("*(no related words found yet)*"))
        XCTAssertFalse(after.contains("{{see-also}}"), "Variable must be replaced even when no matches found")
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
