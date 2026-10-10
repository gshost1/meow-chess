import Foundation

// MARK: - Engine output (mirrors core/src/analysis.rs)

struct Eval: Codable, Hashable {
    let cp: Int?
    let mate: Int?

    /// Score from White's point of view, clamped for display (mate counts as ±10 pawns).
    var whitePawns: Double {
        if let m = mate { return m > 0 ? 10 : -10 }
        return max(-10, min(10, Double(cp ?? 0) / 100))
    }

    var text: String {
        if let m = mate { return m > 0 ? "M\(m)" : "-M\(-m)" }
        let p = Double(cp ?? 0) / 100
        return p >= 0 ? String(format: "+%.1f", p) : String(format: "%.1f", p)
    }
}

enum Grade: String, Codable, CaseIterable {
    case forced, best, excellent, good, inaccuracy, mistake, blunder

    var label: String {
        switch self {
        case .forced: return "Only move"
        case .best: return "Best"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        }
    }

    var symbol: String {
        switch self {
        case .forced, .best: return "★"
        case .excellent: return "!"
        case .good: return "✓"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    var isBad: Bool { self == .inaccuracy || self == .mistake || self == .blunder }
}

struct MoveReview: Codable, Hashable, Identifiable {
    var id: Int { ply }
    let ply: Int
    let moveNumber: Int
    let color: String
    let san: String
    let uci: String
    let from: String
    let to: String
    let fenBefore: String
    let fenAfter: String
    let evalBefore: Eval
    let evalAfter: Eval
    let bestSan: String
    let bestUci: String
    let bestLine: [String]
    let replySan: String?
    let replyUci: String?
    let replyLine: [String]
    let grade: Grade
    let winDrop: Double
    let accuracy: Double
    let phase: String
    let headline: String
    let explanation: String
    let tags: [String]
    let ideas: [Idea]?
    let ideasText: String?
    let bestIdeas: [Idea]?
    let bestText: String?
    let opponentThreat: String?
    let bestLineMoves: [LineMove]?
    let replyLineMoves: [LineMove]?
    let cpLoss: Int?

    enum CodingKeys: String, CodingKey {
        case ply, moveNumber, color, san, uci, from, to, fenBefore, fenAfter, evalBefore, evalAfter
        case bestSan, bestUci, bestLine, replySan, replyUci, replyLine
        case grade = "class"
        case winDrop, accuracy, phase, headline, explanation, tags
        case ideas, ideasText, bestIdeas, bestText, opponentThreat, bestLineMoves, replyLineMoves, cpLoss
    }

    var isWhite: Bool { color == "white" }
    var numberLabel: String { isWhite ? "\(moveNumber)." : "\(moveNumber)…" }
    var playedIsBest: Bool { uci == bestUci }
}

struct Idea: Codable, Hashable {
    let kind: String
    let text: String

    var category: IdeaCategory { IdeaCategory(kind: kind) }
}

struct LineMove: Codable, Hashable {
    let san: String
    let uci: String
    let fen: String
}

/// The plain-language idea groups used by the "what was your idea?" quiz.
enum IdeaCategory: String, CaseIterable, Codable, Identifiable {
    case attack, kingAttack, winMaterial, trade, defend, develop, castle, center, pawnPush, improve

    var id: String { rawValue }

    init(kind: String) {
        switch kind {
        case "attack", "fork", "pin": self = .attack
        case "king_attack", "check", "checkmate": self = .kingAttack
        case "capture", "promote": self = .winMaterial
        case "trade": self = .trade
        case "defend", "save_piece", "prevent": self = .defend
        case "develop": self = .develop
        case "castle", "prepare_castle", "king_safety": self = .castle
        case "center": self = .center
        case "pawn_push": self = .pawnPush
        default: self = .improve
        }
    }

    var label: String {
        switch self {
        case .attack: return "Attack a piece"
        case .kingAttack: return "Go after the king"
        case .winMaterial: return "Win material"
        case .trade: return "Trade pieces"
        case .defend: return "Defend or save a piece"
        case .develop: return "Develop a piece"
        case .castle: return "Keep my king safe"
        case .center: return "Control the center"
        case .pawnPush: return "Push a pawn forward"
        case .improve: return "Improve a piece"
        }
    }

    /// Completes "If you wanted to ...".
    var verb: String {
        switch self {
        case .attack: return "attack a piece"
        case .kingAttack: return "go after the king"
        case .winMaterial: return "win material"
        case .trade: return "trade pieces"
        case .defend: return "defend"
        case .develop: return "develop a piece"
        case .castle: return "keep your king safe"
        case .center: return "control the center"
        case .pawnPush: return "push a pawn"
        case .improve: return "improve a piece"
        }
    }

    var icon: String {
        switch self {
        case .attack: return "scope"
        case .kingAttack: return "crown"
        case .winMaterial: return "gift"
        case .trade: return "arrow.left.arrow.right"
        case .defend: return "shield"
        case .develop: return "figure.walk"
        case .castle: return "house"
        case .center: return "circle.grid.cross"
        case .pawnPush: return "arrow.up"
        case .improve: return "wand.and.stars"
        }
    }
}

struct PlanSummary: Codable, Hashable {
    let style: String
    let styleDetail: String
    let focus: String
    let highlights: [String]
}

struct LegalMove: Codable, Hashable {
    let uci: String
    let san: String
    let from: String
    let to: String
    let fen: String
}

struct SideSummary: Codable, Hashable {
    let accuracy: Double
    let best: Int
    let excellent: Int
    let good: Int
    let inaccuracy: Int
    let mistake: Int
    let blunder: Int
    let castledOnMove: Int?
    let acpl: Double?
    let estimatedRating: Int?
    let plan: PlanSummary?
    let ideaCounts: [String: Int]?

    /// Recomputed from `acpl` so reviews saved under an older formula stay consistent.
    var playedLikeRating: Int? { acpl.map(CoachView.rating) ?? estimatedRating }
}

struct GameAnalysis: Codable, Hashable {
    let white: String
    let black: String
    let whiteElo: String?
    let blackElo: String?
    let result: String
    let date: String?
    let termination: String?
    let startFen: String
    let moves: [MoveReview]
    let whiteSummary: SideSummary
    let blackSummary: SideSummary
    let depthReached: Int

    func userIsWhite(_ username: String) -> Bool? {
        if white.caseInsensitiveCompare(username) == .orderedSame { return true }
        if black.caseInsensitiveCompare(username) == .orderedSame { return false }
        return nil
    }
}

struct EngineEnvelope: Codable {
    let ok: Bool
    let analysis: GameAnalysis?
    let error: String?
}

// MARK: - Chess.com public API

struct ChessComPlayer: Codable, Hashable {
    let username: String
    let rating: Int?
    let result: String?
}

struct ChessComGame: Codable, Hashable, Identifiable {
    let url: String
    let pgn: String?
    let timeControl: String?
    let endTime: Int?
    let rated: Bool?
    let timeClass: String?
    let rules: String?
    let white: ChessComPlayer
    let black: ChessComPlayer

    var id: String { url.split(separator: "/").last.map(String.init) ?? url }

    var endDate: Date? { endTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    func userColorIsWhite(_ username: String) -> Bool {
        white.username.caseInsensitiveCompare(username) == .orderedSame
    }

    func opponent(of username: String) -> ChessComPlayer {
        userColorIsWhite(username) ? black : white
    }

    func me(_ username: String) -> ChessComPlayer {
        userColorIsWhite(username) ? white : black
    }

    enum Outcome { case win, loss, draw }

    func outcome(for username: String) -> Outcome {
        let r = me(username).result ?? ""
        if r == "win" { return .win }
        let draws: Set<String> = ["agreed", "repetition", "stalemate", "insufficient", "50move", "timevsinsufficient"]
        return draws.contains(r) ? .draw : .loss
    }
}

struct ChessComArchives: Codable { let archives: [String] }
struct ChessComMonth: Codable { let games: [ChessComGame] }
