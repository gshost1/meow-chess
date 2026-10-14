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
    @AppStorage("quizMode") var quizModeRaw: String = QuizMode.all.rawValue

    @Published var games: [ChessComGame] = []
    @Published var analyses: [String: GameAnalysis] = [:]
    @Published var progress: [String: Double] = [:]
    @Published var loadingGames = false
    @Published var errorMessage: String?
    @Published var answers: [String: QuizAnswer] = [:]
    @Published var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "games"
    @Published var solvedPuzzles: Set<String> = []

    var quizMode: QuizMode {
        get { QuizMode(rawValue: quizModeRaw) ?? .all }
        set { quizModeRaw = newValue.rawValue; objectWillChange.send() }
    }

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
        if UITesting.resetRequested { Self.eraseEverything() }
        loadSaved()
    }

    /// Wipes saved games, reviews, answers, settings and AI keys so UI tests start like a fresh install.
    private static func eraseEverything() {
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

    func refreshGames() async {
        let user = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !user.isEmpty else { return }
        loadingGames = true
        errorMessage = nil
        defer { loadingGames = false }
        do {
            let archives: ChessComArchives = try await fetch("https://api.chess.com/pub/player/\(user)/games/archives")
            var collected: [ChessComGame] = []
            // Most recent months first, until we have a decent number of games.
            for url in archives.archives.reversed() {
                let month: ChessComMonth = try await fetch(url)
                collected += month.games.filter { ($0.rules ?? "chess") == "chess" && $0.pgn != nil }
                if collected.count >= 40 { break }
            }
            games = collected.sorted { ($0.endTime ?? 0) > ($1.endTime ?? 0) }
            if let data = try? JSONEncoder().encode(games) { try? data.write(to: gamesCacheURL) }
        } catch {
            errorMessage = "Couldn't load games for \(user). Check the username and your connection."
        }
    }

    private func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("MeowChess-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: data)
    }

    // MARK: Analysis

    func isAnalyzing(_ game: ChessComGame) -> Bool { progress[game.id] != nil }

    func analyze(_ game: ChessComGame) async {
        guard let pgn = game.pgn, progress[game.id] == nil else { return }
        progress[game.id] = 0
        defer { progress[game.id] = nil }
        let id = game.id
        do {
            let (analysis, data) = try await Engine.analyze(
                pgn: pgn, username: username, msPerMove: strength.msPerMove
            ) { p in
                Task { @MainActor in
                    if self.progress[id] != nil { self.progress[id] = p }
                }
            }
            try? data.write(to: folder.appendingPathComponent("\(id).json"))
            analyses[id] = analysis
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func analyzeRecent(_ count: Int) async {
        for game in games.prefix(count) where analyses[game.id] == nil {
            await analyze(game)
        }
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

enum UITesting {
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
