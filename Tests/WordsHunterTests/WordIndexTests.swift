import XCTest
@testable import WordsHunterLib

final class WordIndexTests: XCTestCase {

    private var tmpDir: URL!
    private var wordsDir: URL!
    private var dotDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wh-idx-\(UUID().uuidString)")
        wordsDir = tmpDir.appendingPathComponent("Words")
        dotDir = tmpDir.appendingPathComponent(".wordshunter")
        try? FileManager.default.createDirectory(at: wordsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func regenerate() {
        WordIndex.regenerate(folderURL: wordsDir, vaultPath: tmpDir.path)
    }

    private func readIndex() -> String? {
        try? String(contentsOf: wordsDir.appendingPathComponent("index.md"), encoding: .utf8)
    }

    private func writeMastery(_ words: [String: WordIndex.MasteryEntry]) {
        let store: [String: Any] = [
            "version": 1,
            "words": Dictionary(uniqueKeysWithValues: words.map { key, entry in
                (key, [
                    "word": entry.word,
                    "box": entry.box,
                    "status": entry.status,
                    "next_review": entry.next_review,
                ] as [String: Any])
            })
        ]
        if let data = try? JSONSerialization.data(withJSONObject: store) {
            try? data.write(to: dotDir.appendingPathComponent("mastery.json"))
        }
    }

    private func writeWordPage(_ word: String) {
        try? "# \(word)".write(
            to: wordsDir.appendingPathComponent("\(word).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Tests

    func testEmptyVault_zeroStats() {
        writeMastery([:])
        regenerate()
        let content = readIndex()
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("0 words"))
        XCTAssertFalse(content!.contains("## Mastered"))
        XCTAssertFalse(content!.contains("## Reviewing"))
        XCTAssertFalse(content!.contains("## Learning"))
    }

    func testGroupsByStatus() {
        writeMastery([
            "posit": .init(word: "posit", box: 4, status: "mastered", next_review: "2026-04-12"),
            "ephemeral": .init(word: "ephemeral", box: 3, status: "reviewing", next_review: "2026-04-05"),
            "liminal": .init(word: "liminal", box: 1, status: "learning", next_review: "2026-03-28"),
        ])
        writeWordPage("posit")
        writeWordPage("ephemeral")
        writeWordPage("liminal")

        regenerate()
        let content = readIndex()!

        XCTAssertTrue(content.contains("3 words"))
        XCTAssertTrue(content.contains("1 mastered"))
        XCTAssertTrue(content.contains("1 reviewing"))
        XCTAssertTrue(content.contains("1 learning"))
        XCTAssertTrue(content.contains("## Mastered (1)"))
        XCTAssertTrue(content.contains("[[posit]]"))
        XCTAssertTrue(content.contains("## Reviewing (1)"))
        XCTAssertTrue(content.contains("[[ephemeral]]"))
        XCTAssertTrue(content.contains("## Learning (1)"))
        XCTAssertTrue(content.contains("[[liminal]]"))
    }

    func testDeletedPagesExcluded() {
        writeMastery([
            "posit": .init(word: "posit", box: 4, status: "mastered", next_review: "2026-04-12"),
            "deleted": .init(word: "deleted", box: 2, status: "learning", next_review: "2026-04-01"),
        ])
        writeWordPage("posit")
        // 'deleted' has no .md page

        regenerate()
        let content = readIndex()!

        XCTAssertTrue(content.contains("1 words"))
        XCTAssertTrue(content.contains("[[posit]]"))
        XCTAssertFalse(content.contains("[[deleted]]"))
    }

    func testUntrackedWordsAppearAsLearning() {
        writeMastery([:])
        writeWordPage("untracked")
        writeWordPage("orphan")

        regenerate()
        let content = readIndex()!

        XCTAssertTrue(content.contains("2 words"))
        XCTAssertTrue(content.contains("2 learning"))
        XCTAssertTrue(content.contains("[[orphan]]"))
        XCTAssertTrue(content.contains("[[untracked]]"))
    }

    func testIndexMdNotCountedAsWord() {
        writeMastery([:])
        writeWordPage("posit")
        try? "> old index".write(
            to: wordsDir.appendingPathComponent("index.md"),
            atomically: true,
            encoding: .utf8
        )

        regenerate()
        let content = readIndex()!

        XCTAssertTrue(content.contains("1 words"))
        XCTAssertTrue(content.contains("[[posit]]"))
        XCTAssertFalse(content.contains("[[index]]"))
    }
}
