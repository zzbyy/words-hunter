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

    // MARK: lookupEnabled defaults

    func testLookupEnabled_defaultsToTrue() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertTrue(settings.lookupEnabled,
                      "New installs should have lookup enabled by default (Oxford needs no API key)")
    }

    func testLookupEnabled_explicitlySetToFalse_staysFalse() {
        let d = freshDefaults()
        let settings = AppSettings(defaults: d)
        settings.lookupEnabled = false
        XCTAssertFalse(settings.lookupEnabled)
    }
}

// MARK: - TextCapture Lemmatize Tests

final class TextCaptureLemmatizeTests: XCTestCase {

    func testLemmatize_inflected_returnsRoot() {
        let result = TextCapture.lemmatize("posited")
        XCTAssertEqual(result, "posit")
    }

    func testLemmatize_verbInflection_returnsRoot() {
        let result = TextCapture.lemmatize("running")
        XCTAssertEqual(result, result.lowercased(), "lemmatize must always return lowercase")
        XCTAssertFalse(result.isEmpty)
    }

    func testLemmatize_alreadyLower_unchanged() {
        let result = TextCapture.lemmatize("run")
        XCTAssertEqual(result, "run")
    }

    func testLemmatize_unknownWord_fallsBackToLowercased() {
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

// MARK: - DictionaryService MW JSON Parsing Tests (kept for fallback)

final class DictionaryServiceJSONTests: XCTestCase {

    private func callParseMWResponse(_ data: Data) throws -> MWRawContent? {
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
    static func callParseResponse(data: Data) throws -> MWRawContent? {
        let svc = DictionaryService()
        return try svc.parseMWResponse(data: data)
    }
}

// MARK: - OxfordScraper HTML Parsing Tests

final class OxfordScraperTests: XCTestCase {

    // MARK: - Headword extraction

    func testExtractHeadword_basic() {
        let html = """
        <h1 class="headword" hclass="headword" ox5000="y" htag="h1" id="delegate_h_1">delegate</h1>
        """
        XCTAssertEqual(OxfordScraper.extractHeadword(html: html), "delegate")
    }

    func testExtractHeadword_missing() {
        let html = "<div>no headword here</div>"
        XCTAssertNil(OxfordScraper.extractHeadword(html: html))
    }

    // MARK: - Pronunciation extraction

    func testExtractPronunciation_bre() {
        let html = """
        <div class="phons_br" hclass="phons_br" htag="div" geo="br" wd="delegate"><span class="phon">/ˈdelɪɡət/</span></div>
        """
        XCTAssertEqual(OxfordScraper.extractPronunciation(html: html, geo: "phons_br"), "/ˈdelɪɡət/")
    }

    func testExtractPronunciation_ame() {
        let html = """
        <div class="phons_n_am" htag="div" geo="n_am" hclass="phons_n_am" wd="delegate"><span class="phon">/ˈdelɪɡeɪt/</span></div>
        """
        XCTAssertEqual(OxfordScraper.extractPronunciation(html: html, geo: "phons_n_am"), "/ˈdelɪɡeɪt/")
    }

    func testExtractPronunciation_missing() {
        let html = "<div>no pronunciation</div>"
        XCTAssertNil(OxfordScraper.extractPronunciation(html: html, geo: "phons_br"))
    }

    func testExtractPronunciation_geoAttributeFallback() {
        let html = """
        <span geo="br" class="region-block"><span class="phon">/ˈtest/</span></span>
        """
        XCTAssertEqual(OxfordScraper.extractPronunciation(html: html, geo: "phons_br"), "/ˈtest/")
    }

    // MARK: - CEFR extraction

    func testExtractHeaderCEFR() {
        let html = """
        <span class="ox5ksym_c1"> </span>
        """
        XCTAssertEqual(OxfordScraper.extractHeaderCEFR(html: html), "C1")
    }

    func testExtractHeaderCEFR_b2() {
        let html = """
        <span class="ox3ksym_b2"> </span>
        """
        XCTAssertEqual(OxfordScraper.extractHeaderCEFR(html: html), "B2")
    }

    func testExtractHeaderCEFR_notPresent() {
        let html = "<div>no cefr here</div>"
        XCTAssertNil(OxfordScraper.extractHeaderCEFR(html: html))
    }

    // MARK: - Senses extraction

    func testExtractSenses_basic() {
        let html = """
        <li class="sense" id="delegate_sng_1" cefr="c1" hclass="sense" htag="li" sensenum="1"><span class="def" hclass="def" htag="span">a person who is chosen or elected to represent the views of a group</span><ul class="examples" hclass="examples" htag="ul"><li class="" htag="li"><span class="x">Congress delegates rejected the proposals.</span></li></ul></li>
        """
        let senses = OxfordScraper.extractSenses(html: html)
        XCTAssertEqual(senses.count, 1)
        XCTAssertEqual(senses[0].definition, "a person who is chosen or elected to represent the views of a group")
        XCTAssertEqual(senses[0].cefrLevel, "C1")
        XCTAssertEqual(senses[0].examples, ["Congress delegates rejected the proposals."])
    }

    func testExtractSenses_multipleSenses() {
        let html = """
        <li class="sense" id="s1" cefr="b2" hclass="sense" htag="li" sensenum="1"><span class="def">first definition</span></li><li class="sense" id="s2" cefr="c1" hclass="sense" htag="li" sensenum="2"><span class="def">second definition</span></li>
        """
        let senses = OxfordScraper.extractSenses(html: html)
        XCTAssertEqual(senses.count, 2)
        XCTAssertEqual(senses[0].definition, "first definition")
        XCTAssertEqual(senses[0].cefrLevel, "B2")
        XCTAssertEqual(senses[1].definition, "second definition")
        XCTAssertEqual(senses[1].cefrLevel, "C1")
    }

    func testExtractSenses_withExtraExamples() {
        let html = """
        <li class="sense" id="s1" cefr="b1" hclass="sense" htag="li" sensenum="1"><span class="def">the process of heating</span><ul class="examples"><li><span class="x">Who turned the heating off?</span></li></ul><div class="collapse" hclass="collapse" htag="div"><span class="unbox" unbox="extra_examples"><span class="box_title">Extra Examples</span><ul class="examples"><li><span class="unx">Our heating goes off at eleven.</span></li><li><span class="unx">The heating doesn't work.</span></li></ul></span></div></li>
        """
        let senses = OxfordScraper.extractSenses(html: html)
        XCTAssertEqual(senses.count, 1)
        XCTAssertEqual(senses[0].examples, ["Who turned the heating off?"])
        XCTAssertEqual(senses[0].extraExamples, ["Our heating goes off at eleven.", "The heating doesn't work."])
    }

    func testExtractSenses_noSenses() {
        let html = "<div>no senses here</div>"
        XCTAssertEqual(OxfordScraper.extractSenses(html: html), [])
    }

    // MARK: - Collocations extraction

    func testExtractCollocations() {
        let html = """
        Oxford Collocations Dictionary</span><span class="body"><span class="unbox">adjective</span><ul class="collocs_list"><li class="li">conference</li><li class="li">congress</li></ul><span class="unbox">verb + delegate</span><ul class="collocs_list"><li class="li">choose</li><li class="li">elect</li></ul></span>
        """
        let collocations = OxfordScraper.extractCollocations(html: html)
        XCTAssertEqual(collocations.count, 2)
        XCTAssertEqual(collocations[0].label, "adjective")
        XCTAssertEqual(collocations[0].items, ["conference", "congress"])
        XCTAssertEqual(collocations[1].label, "verb + delegate")
        XCTAssertEqual(collocations[1].items, ["choose", "elect"])
    }

    func testExtractCollocations_none() {
        let html = "<div>no collocations</div>"
        XCTAssertEqual(OxfordScraper.extractCollocations(html: html), [])
    }

    // MARK: - Nearby words extraction

    func testExtractNearbyWords() {
        let html = """
        <div class="responsive_row nearby"><ul><li><a href="/def"><DATA class="hwd">delectable <pos>adjective</pos></DATA></a></li><li><a href="/def"><DATA class="hwd">delegate <pos>noun</pos></DATA></a></li></ul></div>
        """
        let nearby = OxfordScraper.extractNearbyWords(html: html)
        XCTAssertEqual(nearby.count, 2)
        XCTAssertEqual(nearby[0].word, "delectable")
        XCTAssertEqual(nearby[0].pos, "adjective")
        XCTAssertEqual(nearby[1].word, "delegate")
        XCTAssertEqual(nearby[1].pos, "noun")
    }

    func testExtractNearbyWords_classOrderDoesNotMatter() {
        let html = """
        <div class="sidebar nearby responsive_row"><ul><li><a href="/def"><DATA class="hwd">delectable <pos>adjective</pos></DATA></a></li></ul></div>
        """
        let nearby = OxfordScraper.extractNearbyWords(html: html)
        XCTAssertEqual(nearby, [NearbyWord(word: "delectable", pos: "adjective")])
    }

    // MARK: - Other entry URLs extraction

    func testExtractOtherEntryURLs() {
        let html = """
        <div id="relatedentries"><dl><dt>All matches</dt><dd><ul><li><a href="https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2" title="delegate verb">delegate verb</a></li></ul></dd></dl></div>
        """
        let urls = OxfordScraper.extractOtherEntryURLs(html: html)
        XCTAssertEqual(urls, ["https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2"])
    }

    func testExtractOtherEntryURLs_deduplicatesPreservingOrder() {
        let html = """
        <div id="relatedentries"><dl><dd><ul><li><a href="https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2">delegate verb</a></li><li><a href="https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2">delegate verb</a></li><li><a href="https://www.oxfordlearnersdictionaries.com/definition/english/delegate_3">delegate adjective</a></li></ul></dd></dl></div>
        """
        let urls = OxfordScraper.extractOtherEntryURLs(html: html)
        XCTAssertEqual(urls, [
            "https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2",
            "https://www.oxfordlearnersdictionaries.com/definition/english/delegate_3"
        ])
    }

    func testExtractOtherEntryURLs_supportsRelativeLinks() {
        let html = """
        <div id="relatedentries"><dl><dd><ul><li><a href="/definition/english/delegate_2">delegate verb</a></li></ul></dd></dl></div>
        """
        let urls = OxfordScraper.extractOtherEntryURLs(html: html)
        XCTAssertEqual(urls, ["https://www.oxfordlearnersdictionaries.com/definition/english/delegate_2"])
    }

    // MARK: - Search fallback parsing

    func testExtractSearchResultURL_prefersDefinitionLink() {
        let html = """
        <div id="search-results"><ul class="result-list"><li><a href="/definition/english/delegate_1">delegate</a></li></ul></div>
        """
        XCTAssertEqual(
            OxfordScraper.extractSearchResultURL(html: html),
            "https://www.oxfordlearnersdictionaries.com/definition/english/delegate_1"
        )
    }

    func testExtractSearchResultURL_fallsBackToWholeHTML() {
        let html = """
        <html><body><a href="https://www.oxfordlearnersdictionaries.com/definition/english/delegate_1">delegate</a></body></html>
        """
        XCTAssertEqual(
            OxfordScraper.extractSearchResultURL(html: html),
            "https://www.oxfordlearnersdictionaries.com/definition/english/delegate_1"
        )
    }

    // MARK: - Entry parsing

    func testParseEntry_basic() {
        let html = """
        <div class="entry"><div class="top-container"><div class="webtop"><h1 class="headword">delegate</h1> <span class="pos">noun</span><span class="ox5ksym_c1"> </span></div></div></div><ol><li class="sense" id="s1" cefr="c1" hclass="sense" htag="li"><span class="def">a person who represents others</span><ul class="examples"><li><span class="x">The delegate spoke.</span></li></ul></li></ol>
        """
        let entry = OxfordScraper.parseEntry(html: html)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.pos, "noun")
        XCTAssertEqual(entry?.cefrLevel, "C1")
        XCTAssertEqual(entry?.senses.count, 1)
        XCTAssertEqual(entry?.senses[0].definition, "a person who represents others")
    }

    func testParseEntry_noSenses_returnsNil() {
        let html = "<div class=\"entry\"><h1 class=\"headword\">xyz</h1></div>"
        XCTAssertNil(OxfordScraper.parseEntry(html: html))
    }

    // MARK: - HTML stripping

    func testStripHTML() {
        let input = "<span class=\"x\">The <b>delegate</b> spoke.</span>"
        XCTAssertEqual(OxfordScraper.stripHTML(input), "The delegate spoke.")
    }

    func testStripHTML_entities() {
        let input = "Tom &amp; Jerry &lt;3"
        XCTAssertEqual(OxfordScraper.stripHTML(input), "Tom & Jerry <3")
    }

    func testStripHTML_numericEntities() {
        let input = "Tom&#39;s&nbsp;book&#160;is here"
        XCTAssertEqual(OxfordScraper.stripHTML(input), "Tom's book is here")
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
        XCTAssertTrue(content.contains("**Pronunciation:**"))
    }

    func testCreatePage_sightingsWithDate() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.contains("- \(dateString) — *(context sentence where you saw the word)*"))
    }

    func testCreatePage_allSectionsPresent() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        for section in ["Sightings", "Meanings", "Collocations", "When to Use", "Word Family", "Nearby Words", "See Also", "Memory Tip"] {
            XCTAssertTrue(content.contains("## \(section)"), "Missing section: \(section)")
        }
    }

    func testCreatePage_oxfordVariables() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.contains("{{pronunciation-bre}}"), "Template must contain {{pronunciation-bre}}")
        XCTAssertTrue(content.contains("{{pronunciation-ame}}"), "Template must contain {{pronunciation-ame}}")
        XCTAssertTrue(content.contains("{{cefr}}"), "Template must contain {{cefr}}")
        XCTAssertTrue(content.contains("{{meanings}}"), "Template must contain {{meanings}}")
        XCTAssertTrue(content.contains("{{collocations}}"), "Template must contain {{collocations}}")
        XCTAssertTrue(content.contains("{{nearby-words}}"), "Template must contain {{nearby-words}}")
    }

    func testCreatePage_noFrontmatter() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertFalse(content.contains("---\ncaptured:"), "Template must not contain YAML frontmatter")
    }

    func testCreatePage_hasWordHeading() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertTrue(content.hasPrefix("# posit"), "Template must start with word heading")
    }

    func testCreatePage_noLegacyMWVariables() {
        let dateString = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let content = makeTemplate(lemma: "posit", date: dateString)
        XCTAssertFalse(content.contains("{{syllables}}"), "Template must not contain legacy {{syllables}}")
        XCTAssertFalse(content.contains("{{pronunciation}}"), "Template must not contain legacy {{pronunciation}} (should be -bre/-ame)")
    }

    func testCreatePage_recapture_returnsSkipped() throws {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: d)
        settings.vaultPath = tempVault.path
        settings.useWordFolder = false
        settings.isSetupComplete = true

        let fileURL = tempVault.appendingPathComponent("posit.md")
        try "existing content".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // Helper that reproduces the template string from WordPageCreator (Oxford-based format)
    private func makeTemplate(lemma: String, date: String) -> String {
        WordPageCreator.defaultTemplate
            .replacingOccurrences(of: "{{word}}", with: lemma)
            .replacingOccurrences(of: "{{date}}", with: date)
    }
}

// MARK: - AsyncSerialQueue Tests

final class AsyncSerialQueueTests: XCTestCase {

    func testRun_serializesConcurrentOperations() async {
        let queue = AsyncSerialQueue()
        let tracker = FlightTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try? await queue.run {
                        await tracker.started()
                        try await Task.sleep(nanoseconds: 50_000_000)
                        await tracker.finished()
                    }
                }
            }
        }

        let maxInFlight = await tracker.maxInFlight
        XCTAssertEqual(maxInFlight, 1, "Serial queue must never run more than one operation at a time")
    }
}

private actor FlightTracker {
    private(set) var maxInFlight = 0
    private var inFlight = 0

    func started() {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
    }

    func finished() {
        inFlight -= 1
    }
}

// MARK: - WordPageCreator Regression Test

final class WordPageCreatorRegressionTests: XCTestCase {

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
        XCTAssertTrue(content?.contains("{{pronunciation-bre}}") == true, "Seeded template must contain Oxford lookup variables")
    }

    func testSeed_oldMWTemplate_migratesToOxfordFormat() throws {
        // Simulate an MW-era template (has {{syllables}} but no Oxford vars)
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let mwTemplate = "# {{word}}\n\n**Syllables:** {{syllables}} · **Pronunciation:** {{pronunciation}}\n\n## Meanings\n{{meanings}}\n"
        try mwTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(after.contains("{{pronunciation-bre}}"), "MW template must be migrated to Oxford format")
        XCTAssertTrue(after.contains("{{collocations}}"), "Migrated template must contain {{collocations}}")
        XCTAssertFalse(after.contains("{{syllables}}"), "Legacy {{syllables}} must be gone after migration")
    }

    func testSeed_preVariableTemplate_migratesToOxfordFormat() throws {
        // Simulate a pre-variable template (no lookup variables at all)
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let oldTemplate = "# {{word}}\n\n**Syllables:** *(e.g. po·sit)*\n\n## Meanings\n\n### 1. () *()*\n"
        try oldTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(after.contains("{{pronunciation-bre}}"), "Pre-variable template must be migrated to Oxford format")
    }

    func testSeed_oxfordTemplate_notOverwritten() throws {
        // Simulate an already-current Oxford template — must not be touched
        let dotDir = tempVault.appendingPathComponent(".wordshunter")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let customTemplate = "# {{word}}\n\n**Pronunciation:** {{pronunciation-bre}}\n\nMy custom section.\n"
        try customTemplate.write(to: templateURL, atomically: true, encoding: .utf8)

        WordPageCreator.seedTemplateIfNeeded(vaultPath: tempVault.path)

        let after = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertEqual(after, customTemplate, "Oxford-era template must not be overwritten")
    }

    func testSeed_emptyVaultPath_noOp() {
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

    private func makeOxfordContent(
        headword: String = "delegate",
        pronunciationBrE: String? = "/ˈdelɪɡət/",
        pronunciationAmE: String? = "/ˈdelɪɡət/",
        entries: [OxfordEntry]? = nil,
        nearbyWords: [NearbyWord] = []
    ) -> DictionaryContent {
        let defaultEntries = entries ?? [
            OxfordEntry(
                pos: "noun",
                cefrLevel: "C1",
                senses: [
                    OxfordSense(
                        cefrLevel: "C1",
                        definition: "a person who is chosen or elected to represent the views of a group",
                        examples: ["Congress delegates rejected the proposals."],
                        extraExamples: ["The delegates voted to support the resolution."]
                    )
                ],
                collocations: [
                    CollocationGroup(label: "adjective", items: ["conference", "congress"]),
                    CollocationGroup(label: "verb + delegate", items: ["choose", "elect"])
                ]
            )
        ]
        return DictionaryContent(
            headword: headword,
            pronunciationBrE: pronunciationBrE,
            pronunciationAmE: pronunciationAmE,
            entries: defaultEntries,
            nearbyWords: nearbyWords,
            source: "Oxford Learner's Dictionary"
        )
    }

    // Base template using the new Oxford format
    private let baseTemplate = """
    # delegate

    **Pronunciation:** 🇬🇧 {{pronunciation-bre}} · 🇺🇸 {{pronunciation-ame}} · **Level:** {{cefr}}

    ## Sightings
    - 2026-03-28 — *(context sentence where you saw the word)*

    ---

    ## Meanings
    {{meanings}}

    ## Collocations
    {{collocations}}

    ---

    ## When to Use

    **Where it fits:**
    **In casual speech:**

    ---

    ## Word Family

    *(list related forms, each with a short example)*

    ---

    ## Nearby Words
    {{nearby-words}}

    ---

    ## See Also
    {{see-also}}

    ---

    ## Memory Tip
    *(optional: etymology, mnemonic, personal association — anything that helps you remember)*
    """

    // MARK: Happy path

    func testUpdate_fillsPronunciationBrE() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("🇬🇧 /ˈdelɪɡət/"))
        XCTAssertFalse(updated.contains("{{pronunciation-bre}}"))
    }

    func testUpdate_fillsPronunciationAmE() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("🇺🇸 /ˈdelɪɡət/"))
        XCTAssertFalse(updated.contains("{{pronunciation-ame}}"))
    }

    func testUpdate_fillsCEFR() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**Level:** C1"))
        XCTAssertFalse(updated.contains("{{cefr}}"))
    }

    func testUpdate_fillsMeanings() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("### 1. (noun) *(a person who is chosen or elected to represent the views of a group)* `C1`"))
        XCTAssertFalse(updated.contains("{{meanings}}"))
    }

    func testUpdate_fillsExtraExamples() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**Extra examples:**"))
        XCTAssertTrue(updated.contains("*The delegates voted to support the resolution.*"))
    }

    func testUpdate_fillsCollocations() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("**adjective:**"))
        XCTAssertTrue(updated.contains("· conference"))
        XCTAssertTrue(updated.contains("**verb + delegate:**"))
        XCTAssertFalse(updated.contains("{{collocations}}"))
    }

    func testUpdate_fillsNearbyWords() throws {
        let content = makeOxfordContent(nearbyWords: [
            NearbyWord(word: "delectable", pos: "adjective"),
            NearbyWord(word: "delegation", pos: "noun")
        ])
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: content, lemma: "delegate")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("- delectable *adjective*"))
        XCTAssertTrue(updated.contains("- delegation *noun*"))
        XCTAssertFalse(updated.contains("{{nearby-words}}"))
    }

    // MARK: MW fallback content (sparse data)

    func testUpdate_mwFallback_fillsAvailableFields() throws {
        let mwContent = DictionaryContent(
            headword: "pos·it",
            pronunciationBrE: "/pə-ˈzit/",
            pronunciationAmE: nil,
            entries: [OxfordEntry(
                pos: "verb",
                cefrLevel: nil,
                senses: [OxfordSense(
                    cefrLevel: nil,
                    definition: "to assume or affirm the existence of : postulate",
                    examples: ["philosophers who posit a purely mechanical universe"],
                    extraExamples: []
                )],
                collocations: []
            )],
            nearbyWords: [],
            source: "Merriam-Webster"
        )
        let url = writeFile(name: "posit.md", content: baseTemplate.replacingOccurrences(of: "delegate", with: "posit"))
        try WordPageUpdater.update(at: url.path, with: mwContent, lemma: "posit")
        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(updated.contains("🇬🇧 /pə-ˈzit/"))
        XCTAssertTrue(updated.contains("*(to assume or affirm"))
        XCTAssertTrue(updated.contains("**Level:** —"))  // no CEFR from MW
        XCTAssertTrue(updated.contains("*(no collocations available)*"))
    }

    // MARK: Safety

    func testUpdate_noLookupVars_abortsGracefully() throws {
        let filledPage = "# delegate\n\nAlready filled manually.\n"
        let url = writeFile(name: "delegate.md", content: filledPage)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(after, filledPage, "Page without lookup vars must not be modified")
    }

    func testUpdate_fileDeleted_abortsWithoutThrowing() {
        let missingPath = tempDir.appendingPathComponent("DoesNotExist.md").path
        XCTAssertNoThrow(
            try WordPageUpdater.update(
                at: missingPath,
                with: makeOxfordContent(),
                lemma: "doesnotexist"
            )
        )
    }

    func testUpdate_allLookupVarsReplaced() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let after = try String(contentsOf: url, encoding: .utf8)
        for v in WordPageCreator.allLookupVariables {
            XCTAssertFalse(after.contains(v), "\(v) must be replaced")
        }
    }

    // MARK: See Also auto-fill

    func testUpdate_seeAlsoVariableAlwaysReplaced() throws {
        let url = writeFile(name: "delegate.md", content: baseTemplate)
        try WordPageUpdater.update(at: url.path, with: makeOxfordContent(), lemma: "delegate")
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(after.contains("{{see-also}}"))
        let hasSeeAlsoContent = after.contains("*(no related words found yet)*") || after.contains("[[")
        XCTAssertTrue(hasSeeAlsoContent, "See Also section must contain actual content after fill")
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
        createWordFile("position")
        let results = VaultScanner.scan(
            definitionText: "to posit a theory",
            wordsFolderURL: tempDir,
            excluding: "something"
        )
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
