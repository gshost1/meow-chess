import XCTest
@testable import MeowChess

final class PracticePolishTests: XCTestCase {
    func testModesUseBestMoveRatherThanPlayedMove() throws {
        let move = try fixture(best: [("save_piece", "moves the attacked rook to safety")], played: "fork")
        XCTAssertEqual(PuzzleMode.classify(move), [.all, .defend, .hangingPiece])
        XCTAssertEqual(PuzzleMode.primary(move), .hangingPiece)
    }

    func testFreeCapturesExcludeTradesAndRecaptures() throws {
        let free = try fixture(best: [("capture", "wins the black queen on d5 for free")], san: "Rxd5")
        XCTAssertEqual(PuzzleMode.classify(free), [.all, .attack, .freePieces])
        for text in ["takes back on d5 to win back the material", "takes the queen, although the rook can be taken back"] {
            XCTAssertFalse(PuzzleMode.classify(try fixture(best: [("capture", text)], san: "Rxd5")).contains(.freePieces))
        }
        XCTAssertFalse(PuzzleMode.classify(try fixture(best: [("trade", "offers a trade")], san: "Rxd5")).contains(.freePieces))
    }

    func testAttackDefendMateAndLegacyReviews() throws {
        for kind in ["fork", "pin", "attack", "check", "king_attack", "promote"] {
            XCTAssertTrue(PuzzleMode.classify(try fixture(best: [(kind, "")])).contains(.attack), kind)
        }
        for kind in ["defend", "prevent"] {
            XCTAssertTrue(PuzzleMode.classify(try fixture(best: [(kind, "")])).contains(.defend), kind)
        }
        let mate = try fixture(best: [("checkmate", "delivers checkmate")], san: "Rd8#")
        XCTAssertEqual(PuzzleMode.classify(mate), [.all, .attack, .checkmate])
        XCTAssertEqual(PuzzleMode.primary(mate), .checkmate)
        XCTAssertEqual(PuzzleMode.classify(try fixture(best: nil)), [.all])
        XCTAssertTrue(PuzzleMode.classify(try fixture(best: nil, san: "Qh7#")).contains(.checkmate))
        XCTAssertTrue(PuzzleMode.classify(try fixture(best: nil, tags: ["missed_mate"])).contains(.checkmate))
        // A threat or hung_piece tag describes the played move's failure, not necessarily the best move's job.
        XCTAssertFalse(PuzzleMode.classify(try fixture(best: nil, tags: ["hung_piece", "ignored_threat"])).contains(.hangingPiece))
    }

    func testSharedAnimationsIncludeCastlingAndEnPassantBothWays() throws {
        let castle = BoardAnimation.move(key: 1, uci: "e1g1", san: "O-O", before: "")
        XCTAssertEqual(castle?.slides, [Slide(from: Square(4), to: Square(6)), Slide(from: Square(7), to: Square(5))])
        let back = BoardAnimation.move(key: 2, uci: "e8c8", san: "O-O-O", before: "", backwards: true)
        XCTAssertEqual(back?.slides, [Slide(from: Square(58), to: Square(60)), Slide(from: Square(59), to: Square(56))])
        let ep = BoardAnimation.move(key: 3, uci: "e5d6", san: "exd6", before: "6k1/8/8/3pP3/8/8/8/6K1 w - d6 0 1")
        XCTAssertEqual(ep?.poof, Poof(piece: "p", square: Square(35)))
    }

    @MainActor func testAllPackEventsAreBundled() {
        for pack in SoundPack.allCases {
            for event in Meow.allCases {
                XCTAssertNotNil(Bundle.main.url(forResource: "\(pack.rawValue)_\(event.rawValue)", withExtension: "wav"))
            }
        }
    }

    private func fixture(best: [(String, String)]?, san: String = "Rd2", played: String = "develop", tags: [String] = []) throws -> MoveReview {
        var json: [String: Any] = ["ply": 1, "move_number": 1, "color": "white", "san": "Rd2", "uci": "d1d2",
            "from": "d1", "to": "d2", "fen_before": "6k1/8/8/3q4/8/8/8/3R2K1 w - - 0 1", "fen_after": "",
            "eval_before": ["cp": 0], "eval_after": ["cp": -500], "best_san": san, "best_uci": "d1d5",
            "best_line": [], "reply_line": [], "class": "blunder", "win_drop": 0.3, "accuracy": 20,
            "phase": "endgame", "headline": "", "explanation": "", "tags": tags,
            "opponent_threat": "Qxd2", "ideas": [["kind": played, "text": ""]]]
        if let best { json["best_ideas"] = best.map { ["kind": $0.0, "text": $0.1] } }
        return try Engine.decoder.decode(MoveReview.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
