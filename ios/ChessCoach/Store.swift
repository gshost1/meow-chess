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

    @Published var games: [ChessComGame] = []
    @Published var analyses: [String: GameAnalysis] = [:]
    @Published var progress: [String: Double] = [:]
    @Published var loadingGames = false
    @Published var errorMessage: String?

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

    init() {
        loadSaved()
    }

    private func loadSaved() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let a = try? Engine.decoder.decode(GameAnalysis.self, from: data) {
                analyses[f.deletingPathExtension().lastPathComponent] = a
            }
        }
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
        req.setValue("ChessCoach-iOS/1.0", forHTTPHeaderField: "User-Agent")
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

    func deleteAllAnalyses() {
        for id in analyses.keys {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).json"))
        }
        analyses = [:]
    }
}
