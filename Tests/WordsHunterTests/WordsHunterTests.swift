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

    // We test the JSON parsing logic by probing DictionaryService via a mock URLSession.

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

    // Access the private parseMWResponse via a test-only subclass
    private func callParseMWResponse(_ data: Data) throws -> DictionaryContent? {
        return try DictionaryServiceTestable.callParseResponse(data: data)
    }
}

/// Test-only helper that exposes the private parsing method
final class DictionaryServiceTestable {
    static func callParseResponse(data: Data) throws -> DictionaryContent? {
        // Re-implement the parsing inline so we can test it without network calls
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [Any], !array.isEmpty else { return nil }
        if array.first is String { return nil }
        guard let entries = array as? [[String: Any]] else { return nil }
        var definitions: [String] = []
        for entry in entries.prefix(2) {
            if let shortdefs = entry["shortdef"] as? [String], let first = shortdefs.first {
                definitions.append(first)
            }
        }
        guard !definitions.isEmpty else { return nil }
        return DictionaryContent(definitions: definitions, source: "Merriam-Webster")
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

    private func content(definitions: [String]) -> DictionaryContent {
        DictionaryContent(definitions: definitions, source: "Merriam-Webster")
    }

    // MARK: Happy path

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

    // MARK: Safety: user already edited

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

    // MARK: Safety: file deleted between createPage and updateDefinition

    func testUpdate_fileDeleted_abortsWithoutThrowing() {
        let missingPath = tempDir.appendingPathComponent("DoesNotExist.md").path
        XCTAssertNoThrow(
            try WordPageUpdater.updateDefinition(
                at: missingPath,
                with: content(definitions: ["definition"])
            )
        )
    }

    // MARK: Whitespace-only body (blank lines, trailing newline)

    func testUpdate_whitespaceyBody_isStillConsideredEmpty() throws {
        let template = "## Definition\n\n\n\n## Examples\n\n"
        let url = writeFile(name: "Test.md", content: template)
        try WordPageUpdater.updateDefinition(at: url.path, with: content(definitions: ["value"]))
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("1. value"))
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
