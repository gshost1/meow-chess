import XCTest
@testable import MeowChess

final class QAFixTests: XCTestCase {
    func testUsernameNormalizesDashesSpacesAndSymbols() {
        XCTAssertEqual(ChessComUsername.normalize("  julius201  "), "julius201")
        XCTAssertEqual(ChessComUsername.normalize("this\u{2014}does-not-"), "this--does-not-")
        XCTAssertEqual(ChessComUsername.normalize("this\u{2013}does"), "this-does")
        XCTAssertEqual(ChessComUsername.normalize("a\u{2014}b\u{2013}c"), "a--b-c")
        XCTAssertEqual(ChessComUsername.normalize("julius 201"), "julius201")
        XCTAssertEqual(ChessComUsername.normalize("hello_world"), "hello_world")
        XCTAssertEqual(ChessComUsername.normalize("Julius201!!"), "Julius201")
        XCTAssertEqual(ChessComUsername.normalize("😺julius"), "julius")
        XCTAssertEqual(ChessComUsername.normalize("   "), "")
        XCTAssertEqual(ChessComUsername.normalize(""), "")
        XCTAssertTrue(ChessComUsername.needsHint("   "))
        XCTAssertTrue(ChessComUsername.needsHint("!!!"))
        XCTAssertFalse(ChessComUsername.needsHint(""))
        XCTAssertFalse(ChessComUsername.needsHint("julius201"))
        XCTAssertFalse(ChessComUsername.needsHint("  julius201  "))
    }

    func testNextMistakeSkipsInaccuraciesUntilNothingWorseRemains() {
        let mixed: [(Bool, Grade)] = [
            (true, .inaccuracy),
            (false, .blunder),
            (true, .good),
            (true, .mistake),
            (true, .blunder),
            (true, .inaccuracy),
        ]
        XCTAssertEqual(ReviewNavigation.nextMistakeIndices(mixed), [4, 5])

        let onlySlips: [(Bool, Grade)] = [
            (true, .inaccuracy),
            (false, .mistake),
            (true, .good),
            (true, .inaccuracy),
        ]
        XCTAssertEqual(ReviewNavigation.nextMistakeIndices(onlySlips), [1, 4])
        XCTAssertEqual(ReviewNavigation.nextMistakeIndices([(true, .best), (true, .excellent)]), [])
    }

    func testBackfiredClauseReadsAsASentence() {
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Blunder: ignores a threat"),
            "But it backfired: the move ignores a threat."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Mistake: hangs the queen"),
            "But it backfired: the move hangs the queen."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Blunder: missed winning the knight"),
            "But it backfired: the move missed winning the knight."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Inaccuracy: allows a fork"),
            "But it backfired: the move allows a fork."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Mistake: leaves the rook unprotected"),
            "But it backfired: the move leaves the rook unprotected."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Blunder: loses the queen"),
            "But it backfired: the move loses the queen."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Mistake: Nf3 was better"),
            "But it backfired: Nf3 was better."
        )
        XCTAssertEqual(
            QuizFeedback.backfiredSentence(headline: "Checkmate!"),
            "But it backfired: Checkmate!"
        )
    }

    func testBoardShrinksForAQuestionAndStaysLargeOtherwise() {
        let width: CGFloat = 402
        let height: CGFloat = 730
        let open = ReviewLayout.boardHeight(contentWidth: width, contentHeight: height, detail: .none, keyboard: false)
        let explaining = ReviewLayout.boardHeight(contentWidth: width, contentHeight: height, detail: .explanation, keyboard: false)
        let asking = ReviewLayout.boardHeight(contentWidth: width, contentHeight: height, detail: .question, keyboard: false)
        XCTAssertEqual(open, 370, "the starting board stays at the full-width cap")
        XCTAssertGreaterThan(open, explaining)
        XCTAssertGreaterThan(explaining, asking)
        XCTAssertGreaterThanOrEqual(height - 168 - asking, 300, "a question keeps room for every answer")
        XCTAssertGreaterThanOrEqual(height - 168 - explaining, 256, "a typical explanation keeps its room")

        let typing = ReviewLayout.boardHeight(contentWidth: width, contentHeight: 420, detail: .question, keyboard: true)
        XCTAssertEqual(typing, 252, "the keyboard still caps the board at 60% of the height")
    }
}
