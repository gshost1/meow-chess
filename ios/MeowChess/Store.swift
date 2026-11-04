import Foundation
import SwiftUI

enum AnalysisStrength: String, CaseIterable, Identifiable {
    case fast, normal, deep
    var id: String { rawValue }
    var msPerMove: UInt32 {
        switch self {
        case .fast: return 60
        case .normal: return 180
        case .deep: return 600
        }
    }
    var label: String {
        switch self {
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .deep: return "Deep"
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @AppStorage("username") var username: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("strength") var strengthRaw: String = AnalysisStrength.normal.rawValue
    @AppStorage("quizMode") var quizModeRaw: String = QuizMode.key.rawValue
    /// The mode the review screen's Questions switch restores when turned back on.
    @AppStorage("quizModeWhenOn") var quizModeWhenOnRaw: String = QuizMode.key.rawValue

    @AppStorage("pieceStyle") var pieceStyleRaw: String = PieceStyle.cat.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage("gamesTimeClass") var gamesTimeClass: String = "" {
        didSet { objectWillChange.send() }
    }
    var pieceStyle: PieceStyle {
        get { PieceStyle(rawValue: pieceStyleRaw) ?? .cat }
        set { pieceStyleRaw = newValue.rawValue }
    }

    @Published private(set) var pendingReviews: Set<String> = []
    /// Recent games whose automatic review failed; they open normally so the review can be retried.
    @Published private(set) var failedReviews: Set<String> = []
    private var loadingUser: String?
    private var reviewingRecent = false
    private var automaticallyAttempted: Set<String> = []

    @Published var games: [ChessComGame] = []
    @Published var analyses: [String: GameAnalysis] = [:]
    /// Which games are being reviewed. Changes only when a review starts or ends.
    @Published var progress: [String: Double] = [:]
    /// How far each running review is. Kept out of Store's own updates so progress ticks redraw only
    /// the progress bars; redrawing whole screens mid-tap was cancelling taps on the games tabs.
    let reviewProgress = ReviewProgress()
    @Published var loadingGames = false
    @Published var errorMessage: String?
    @Published var answers: [String: QuizAnswer] = [:]
    @Published var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "games"
    @Published var solvedPuzzles: Set<String> = []

    var quizMode: QuizMode {
        get { QuizMode(rawValue: quizModeRaw) ?? .key }
        set {
            quizModeRaw = newValue.rawValue
            if newValue != .off { quizModeWhenOnRaw = newValue.rawValue }
            objectWillChange.send()
        }
    }
    var quizModeWhenOn: QuizMode { QuizMode(rawValue: quizModeWhenOnRaw).flatMap { $0 == .off ? nil : $0 } ?? .key }

    var strength: AnalysisStrength {
        get { AnalysisStrength(rawValue: strengthRaw) ?? .normal }
        set { strengthRaw = newValue.rawValue; objectWillChange.send() }
    }

    private let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("analyses", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var gamesCacheURL: URL { folder.deletingLastPathComponent().appendingPathComponent("games.json") }
    private var answersURL: URL { folder.deletingLastPathComponent().appendingPathComponent("answers.json") }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        loadSaved()
        #if DEBUG
        if UITesting.enabled && ProcessInfo.processInfo.arguments.contains("-uiTestFixtures") {
            games = UITesting.fixtureGames()
            if let data = try? JSONEncoder().encode(games) { try? data.write(to: gamesCacheURL) }
        }
        #endif
        startRecentAnalysis()
    }

    /// Wipes saved games, reviews, answers, settings and AI keys so UI tests start like a fresh install.
    static func eraseEverything() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for f in (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        Keychain.save("", account: "llm")
        Keychain.save("", account: "jev")
    }

    private func loadSaved() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let a = try? Engine.decoder.decode(GameAnalysis.self, from: data) {
                // Reviews from before move ideas existed get redone so every screen has full data.
                if a.moves.first?.ideasText == nil && !a.moves.isEmpty {
                    try? FileManager.default.removeItem(at: f)
                    continue
                }
                analyses[f.deletingPathExtension().lastPathComponent] = a
            }
        }
        if let data = try? Data(contentsOf: answersURL),
           let saved = try? JSONDecoder().decode([String: QuizAnswer].self, from: data) {
            answers = saved
        }
        solvedPuzzles = Set(UserDefaults.standard.stringArray(forKey: "solvedPuzzles") ?? [])
        if let data = try? Data(contentsOf: gamesCacheURL),
           let cached = try? JSONDecoder().decode([ChessComGame].self, from: data) {
            games = cached
        }
    }

    // MARK: Chess.com

    private enum ChessComLoadError: Error, Equatable {
        case notFound
        case failed
    }

    /// Saves a Chess.com username and reloads that player's games.
    func replaceUsername(_ raw: String) {
        let name = ChessComUsername.normalize(raw)
        guard !name.isEmpty else { return }
        username = name
        games = []
        errorMessage = nil
        Task { await refreshGames() }
    }

    func refreshGames() async {
        let user = ChessComUsername.normalize(username).lowercased()
        guard !user.isEmpty, loadingUser != user else { return }
        loadingUser = user
        loadingGames = true
        errorMessage = nil
        defer {
            if loadingUser == user { loadingUser = nil; loadingGames = false }
        }
        do {
            let archives: ChessComArchives = try await fetch("https://api.chess.com/pub/player/\(user)/games/archives")
            var collected: [ChessComGame] = []
            // Most recent months first, until we have a decent number of games.
            // Chess.com lists the current month even when it has no games yet, and that URL 404s: skip it.
            // Any other failure stops the load so a partial list never replaces the cached games.
            for url in archives.archives.reversed() {
                let month: ChessComMonth
                do { month = try await fetch(url) } catch ChessComLoadError.notFound { continue }
                collected += month.games.filter { ($0.rules ?? "chess") == "chess" && $0.pgn != nil }
                if collected.count >= 40 { break }
            }
            // The username changed while this was loading: keep the newer user's games.
            guard loadingUser == user else { return }
            games = collected.sorted { ($0.endTime ?? 0) > ($1.endTime ?? 0) }
            startRecentAnalysis()
            if let data = try? JSONEncoder().encode(games) { try? data.write(to: gamesCacheURL) }
        } catch let error as ChessComLoadError {
            guard loadingUser == user else { return }
            errorMessage = error == .notFound
                ? "There's no Chess.com player named \(user)."
                : Self.gamesLoadError(for: user)
        } catch {
            guard loadingUser == user else { return }
            errorMessage = Self.gamesLoadError(for: user)
        }
    }

    private static func gamesLoadError(for user: String) -> String {
        "Couldn't load games for \(user). Check the username and your connection."
    }

    private func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw ChessComLoadError.failed }
        var req = URLRequest(url: url)
        req.setValue("MeowChess-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 404 { throw ChessComLoadError.notFound }
            if http.statusCode != 200 { throw ChessComLoadError.failed }
        }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: data)
    }

    // MARK: Analysis

    func isAnalyzing(_ game: ChessComGame) -> Bool { progress[game.id] != nil }

    func analyze(_ game: ChessComGame) async {
        guard let pgn = game.pgn, analyses[game.id] == nil, progress[game.id] == nil else { return }
        progress[game.id] = 0
        defer { progress[game.id] = nil; reviewProgress.values[game.id] = nil }
        let id = game.id
        do {
            let (analysis, data) = try await Engine.analyze(
                pgn: pgn, username: username, msPerMove: strength.msPerMove
            ) { p in
                Task { @MainActor in
                    guard self.progress[id] != nil else { return }
                    let old = self.reviewProgress.values[id] ?? 0
                    if p - old >= 0.02 || p >= 1 { self.reviewProgress.values[id] = p }
                }
            }
            try data.write(to: folder.appendingPathComponent("\(id).json"), options: .atomic)
            analyses[id] = analysis
            failedReviews.remove(id)
        } catch {
            failedReviews.insert(id)
            errorMessage = error.localizedDescription
        }
    }

    private func startRecentAnalysis() {
        let missing = games.prefix(10).filter {
            analyses[$0.id] == nil && !automaticallyAttempted.contains($0.id)
        }
        guard !missing.isEmpty else { return }
        automaticallyAttempted.formUnion(missing.map(\.id))
        pendingReviews.formUnion(missing.map(\.id))
        Task { await analyzeRecent(10) }
    }

    func analyzeRecent(_ count: Int) async {
        pendingReviews.formUnion(games.prefix(count).filter { analyses[$0.id] == nil }.map(\.id))
        guard !reviewingRecent else { return }
        reviewingRecent = true
        defer { reviewingRecent = false }
        // Re-read games after each await so a refresh can add newly downloaded games.
        while let game = games.first(where: { pendingReviews.contains($0.id) }) {
            await analyze(game)
            pendingReviews.remove(game.id)
        }
        pendingReviews = []
    }

    func reviewIsRequired(_ game: ChessComGame) -> Bool {
        analyses[game.id] == nil && !failedReviews.contains(game.id) && (games.prefix(10).contains { $0.id == game.id } || isAnalyzing(game))
    }

    // MARK: Idea quiz and puzzles

    static func answerKey(game: String, ply: Int) -> String { "\(game)#\(ply)" }

    func saveAnswer(_ a: QuizAnswer, game: String, ply: Int) {
        answers[Self.answerKey(game: game, ply: ply)] = a
        if let data = try? JSONEncoder().encode(answers) { try? data.write(to: answersURL) }
    }

    func markSolved(_ id: String) {
        solvedPuzzles.insert(id)
        UserDefaults.standard.set(Array(solvedPuzzles), forKey: "solvedPuzzles")
    }

    /// Puzzles built from the player's own mistakes and blunders, newest games first.
    var puzzles: [Puzzle] {
        #if DEBUG
        if UITesting.enabled && ProcessInfo.processInfo.arguments.contains("-uiTestPractice") {
            return UITesting.practicePuzzles()
        }
        #endif
        var out: [Puzzle] = []
        for game in games {
            guard let a = analyses[game.id], let white = a.userIsWhite(username) else { continue }
            for m in a.moves where m.isWhite == white && (m.grade == .mistake || m.grade == .blunder) && !m.playedIsBest {
                out.append(Puzzle(id: Self.answerKey(game: game.id, ply: m.ply), move: m, userIsWhite: white,
                                  opponent: white ? a.black : a.white))
            }
        }
        return out
    }

    func deleteAllAnalyses() {
        for id in analyses.keys {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).json"))
        }
        analyses = [:]
    }
}

@MainActor
final class ReviewProgress: ObservableObject {
    @Published var values: [String: Double] = [:]
}

/// A progress bar that observes only review progress, not the whole Store.
struct ReviewProgressBar: View {
    @ObservedObject var progress: ReviewProgress
    let id: String
    var body: some View { ProgressView(value: progress.values[id] ?? 0) }
}

enum UITesting {
    #if DEBUG
    /// Small offline positions; every move and continuation is applied by the real engine.
    static func practicePuzzles() -> [Puzzle] {
        let positions = [
            ("6k1/8/8/3q4/8/8/8/3R2K1 w - - 0 1", "d1d5", ["g8h8", "d5d8"],
             [Idea(kind: "capture", text: "wins the black queen on d5 for free"),
              Idea(kind: "save_piece", text: "moves the attacked rook to safety"),
              Idea(kind: "defend", text: "stops the queen's threat")]),
            ("7k/8/5KQ1/8/8/8/8/8 w - - 0 1", "g6g7", [],
             [Idea(kind: "checkmate", text: "delivers checkmate")])
        ]
        return positions.enumerated().compactMap { index, entry in
            let (fen, uci, rest, ideas) = entry
            let moves = Engine.legalMoves(fen: fen)
            guard let best = moves.first(where: { $0.uci == uci }),
                  let wrong = moves.first(where: { $0.uci != uci }) else { return nil }
            var line = [LineMove(san: best.san, uci: best.uci, fen: best.fen)]
            for next in rest {
                guard let move = Engine.legalMoves(fen: line.last?.fen ?? best.fen).first(where: { $0.uci == next }) else { break }
                line.append(LineMove(san: move.san, uci: move.uci, fen: move.fen))
            }
            let json: [String: Any] = ["ply": 1, "move_number": 1, "color": "white",
                "san": wrong.san, "uci": wrong.uci, "from": wrong.from, "to": wrong.to,
                "fen_before": fen, "fen_after": wrong.fen, "eval_before": ["cp": 0], "eval_after": ["cp": -500],
                "best_san": best.san, "best_uci": best.uci, "best_line": line.map(\.san), "reply_line": [],
                "class": "blunder", "win_drop": 0.3, "accuracy": 20, "phase": "endgame",
                "headline": "A better move", "explanation": "Look for checks and captures.", "tags": [],
                "best_text": ideas.map(\.text).joined(separator: ". ") + ".",
                "best_ideas": ideas.map { ["kind": $0.kind, "text": $0.text] },
                "best_line_moves": line.map { ["san": $0.san, "uci": $0.uci, "fen": $0.fen] }]
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let move = try? Engine.decoder.decode(MoveReview.self, from: data) else { return nil }
            return Puzzle(id: "practice-fixture-\(index)", move: move, userIsWhite: true, opponent: "PracticeCat")
        }
    }

    static func fixtureGames() -> [ChessComGame] {
        (0..<12).map { i in
            let timeClass = i == 11 && ProcessInfo.processInfo.arguments.contains("-uiTestDaily")
                ? "daily" : ["rapid", "bullet", "blitz"][i % 3]
            let opponent = timeClass.capitalized + "Cat"
            let pgn = """
            [White "julius201"]
            [Black "\(opponent)"]
            [Result "1-0"]

            1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
            """
            return ChessComGame(url: "https://www.chess.com/game/live/fixture-\(i)", pgn: pgn,
                timeControl: "600", endTime: 1_799_000_000 - i, rated: true, timeClass: timeClass,
                rules: "chess", white: ChessComPlayer(username: "julius201", rating: 500, result: "win"),
                black: ChessComPlayer(username: opponent, rating: 500, result: "checkmated"))
        }
    }
    #endif

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static var resetRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestReset") }
}

enum QuizMode: String, CaseIterable, Identifiable {
    case all, key, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All my moves"
        case .key: return "Key moments"
        case .off: return "Off"
        }
    }
}

struct QuizAnswer: Codable, Hashable {
    /// IdeaCategory raw value, or "unsure".
    var choice: String
    /// Whether the move really does what the player said.
    var matched: Bool?
    /// The player's own words, when typed (classified by the Jev decision model).
    var typed: String? = nil
    var confidence: Double? = nil
}

struct Puzzle: Identifiable, Hashable {
    let id: String
    let move: MoveReview
    let userIsWhite: Bool
    let opponent: String
}


enum PieceStyle: String, CaseIterable, Identifiable {
    case cat, classic
    var id: String { rawValue }
    var label: String { self == .cat ? "Cat pieces" : "Classic pieces" }
}
