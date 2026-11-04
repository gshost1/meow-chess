import Foundation

/// Modes overlap: saving a piece is also a defensive puzzle.
enum PuzzleMode: String, CaseIterable, Identifiable {
    case all, attack, defend, freePieces, hangingPiece, checkmate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .attack: return "Attack"
        case .defend: return "Defend"
        case .freePieces: return "Free pieces"
        case .hangingPiece: return "Hanging piece"
        case .checkmate: return "Checkmate"
        }
    }
    var prompt: String {
        switch self {
        case .all: return "Find a better move."
        case .attack: return "Find a move that creates a threat or wins material."
        case .defend: return "Stop the threat or protect a piece."
        case .freePieces: return "Take the piece left undefended."
        case .hangingPiece: return "Save your attacked piece."
        case .checkmate: return "Find the checkmate."
        }
    }

    static func classify(_ move: MoveReview) -> Set<PuzzleMode> {
        let ideas = move.bestIdeas ?? []
        let kinds = Set(ideas.map(\.kind))
        var modes: Set<PuzzleMode> = [.all]
        if !kinds.isDisjoint(with: ["attack", "fork", "pin", "check", "checkmate", "king_attack", "capture", "promote"])
            || move.bestSan.contains("x") || move.bestSan.contains("+") || move.tags.contains("missed_fork") || move.tags.contains("missed_win") {
            modes.insert(.attack)
        }
        if !kinds.isDisjoint(with: ["defend", "save_piece", "prevent"]) {
            modes.insert(.defend)
        }
        if kinds.contains("save_piece") { modes.insert(.hangingPiece) }
        // The engine distinguishes a free capture from trades and recaptures in this idea text.
        // SAN x alone cannot tell whether the captured piece was defended.
        if ideas.contains(where: { $0.kind == "capture" && $0.text.contains("for free") }) {
            modes.insert(.freePieces)
        }
        if kinds.contains("checkmate") || move.bestSan.hasSuffix("#") || move.tags.contains("missed_mate") {
            modes.formUnion([.attack, .checkmate])
        }
        return modes
    }

    static func primary(_ move: MoveReview) -> PuzzleMode {
        let modes = classify(move)
        return [Self.checkmate, .freePieces, .hangingPiece, .defend, .attack].first(where: modes.contains) ?? .all
    }
}
