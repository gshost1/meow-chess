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

    enum CodingKeys: String, CodingKey {
        case ply, moveNumber, color, san, uci, from, to, fenBefore, fenAfter, evalBefore, evalAfter
        case bestSan, bestUci, bestLine, replySan, replyUci, replyLine
        case grade = "class"
        case winDrop, accuracy, phase, headline, explanation, tags
    }

    var isWhite: Bool { color == "white" }
    var numberLabel: String { isWhite ? "\(moveNumber)." : "\(moveNumber)…" }
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
