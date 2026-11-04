import XCTest
@testable import MeowChess

final class ReviewQuestionTests: XCTestCase {
    func testWorstLossesWinAndTiesUsePly() throws {
        let game = try analysis([
            move(1, loss: 30), move(3, loss: 600), move(5, loss: 200),
            move(7, loss: 600), move(9, loss: 0, grade: "best", idea: "fork"),
            move(2, loss: 1000, color: "black")
        ])
        XCTAssertEqual(game.keyQuestionPlies(userIsWhite: true), [3, 5, 7])
        XCTAssertEqual(game.keyQuestionPlies(userIsWhite: true), game.keyQuestionPlies(userIsWhite: true))
        XCTAssertEqual(game.keyQuestionPlies(userIsWhite: false), [2])
    }

    func testAtMostOneGoodTacticAfterMistakes() throws {
        let game = try analysis([
            move(1, loss: 40), move(3, loss: 100),
            move(5, loss: 0, grade: "best", idea: "fork"),
            move(7, loss: 0, grade: "excellent", idea: "capture")
        ])
        XCTAssertEqual(game.keyQuestionPlies(userIsWhite: true), [1, 3, 5])
    }

    func testQuietMovesAndOpponentsTacticsDoNotAddQuestions() throws {
        let game = try analysis([
            move(1, loss: 0, grade: "good", idea: "develop"),
            move(2, loss: 0, grade: "best", color: "black", idea: "fork")
        ])
        XCTAssertTrue(game.keyQuestionPlies(userIsWhite: true).isEmpty)
        XCTAssertEqual(game.keyQuestionPlies(userIsWhite: false), [2])
    }

    private func move(_ ply: Int, loss: Int, grade: String = "mistake", color: String = "white", idea: String = "develop") -> [String: Any] {
        ["ply": ply, "move_number": (ply + 1) / 2, "color": color,
         "san": "e4", "uci": "e2e4", "from": "e2", "to": "e4", "fen_before": "", "fen_after": "",
         "eval_before": ["cp": 0], "eval_after": ["cp": -loss], "best_san": "e4", "best_uci": "e2e4",
         "best_line": [], "reply_line": [], "class": grade, "win_drop": 0.1, "accuracy": 80,
         "phase": "opening", "headline": "", "explanation": "", "tags": [], "cp_loss": loss,
         "ideas": [["kind": idea, "text": ""]]]
    }

    private func analysis(_ moves: [[String: Any]]) throws -> GameAnalysis {
        let summary: [String: Any] = ["accuracy": 80, "best": 0, "excellent": 0, "good": 0,
                                      "inaccuracy": 0, "mistake": 0, "blunder": 0]
        let json: [String: Any] = ["white": "player", "black": "opponent", "result": "*", "start_fen": "",
                                   "moves": moves, "white_summary": summary, "black_summary": summary, "depth_reached": 1]
        return try Engine.decoder.decode(GameAnalysis.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
