import XCTest
@testable import MeowChess

final class QAFixTests: XCTestCase {
    func testUsernameNormalizesDashesSpacesAndSymbols() {
        XCTAssertEqual(ChessComUsername.normalize("  julius201  "), "julius201")
        XCTAssertEqual(ChessComUsername.normalize("this\u{2014}does-not-"), "this--does-not-")
        XCTAssertEqual(ChessComUsername.normalize("this\u{2013}does"), "this-does")
        XCTAssertEqual(ChessComUsername.normalize("a\u{2014}b\u{2013}c"), "a--b-c")
        XCTAssertEqual(ChessComUsername.normalize("hello_world"), "hello_world")
        // Anything else inside the name is refused rather than silently removed (it could be someone else).
        XCTAssertEqual(ChessComUsername.normalize("julius 201"), "")
        XCTAssertEqual(ChessComUsername.normalize("Julius201!!"), "")
        XCTAssertEqual(ChessComUsername.normalize("😺julius"), "")
        XCTAssertEqual(ChessComUsername.normalize("   "), "")
        XCTAssertEqual(ChessComUsername.normalize(""), "")
        XCTAssertEqual(ChessComUsername.hint("   "), "Enter your Chess.com username")
        XCTAssertEqual(ChessComUsername.hint("julius 201"), "Chess.com usernames only use letters, numbers, _ and -")
        XCTAssertNil(ChessComUsername.hint(""))
        XCTAssertNil(ChessComUsername.hint("julius201"))
        XCTAssertNil(ChessComUsername.hint("  julius201  "))
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

    func testBoardLeavesRoomForQuestionsAndIsFullWidthWithout() {
        let width: CGFloat = 402
        let height: CGFloat = 730
        let off = ReviewLayout.boardHeight(contentWidth: width, contentHeight: height, questionsOn: false, keyboard: false)
        let on = ReviewLayout.boardHeight(contentWidth: width, contentHeight: height, questionsOn: true, keyboard: false)
        XCTAssertEqual(off, 370, "with questions off the board is full width")
        XCTAssertEqual(on, 312, "with questions on the board leaves room for the question card")
        XCTAssertGreaterThanOrEqual(height - 168 - on, 250)

        let typing = ReviewLayout.boardHeight(contentWidth: width, contentHeight: 420, questionsOn: true, keyboard: true)
        XCTAssertEqual(typing, 132, "with the keyboard up the board leaves room for the typed answer")
    }
}
