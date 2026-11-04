import SwiftUI

struct GamesView: View {
    @EnvironmentObject var store: Store
    @State private var path: [ChessComGame] = []

    private var timeClasses: [String] {
        ["all", "bullet", "blitz", "rapid"] + (store.games.contains { $0.timeClass == "daily" } ? ["daily"] : [])
    }
    private var selectedTimeClass: String {
        if timeClasses.contains(store.gamesTimeClass) { return store.gamesTimeClass }
        return "all"
    }
    private var shownGames: [ChessComGame] {
        selectedTimeClass == "all" ? store.games : store.games.filter { $0.timeClass == selectedTimeClass }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error = store.errorMessage, !store.games.isEmpty {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
                if store.games.isEmpty && !store.loadingGames {
                    if let error = store.errorMessage {
                        ContentUnavailableView("Couldn't load games", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        ContentUnavailableView("No games yet", systemImage: "magnifyingglass",
                                               description: Text("Pull down to load your Chess.com games."))
                    }
                } else if !store.games.isEmpty && shownGames.isEmpty {
                    ContentUnavailableView("No \(selectedTimeClass) games in your recent games.",
                                           systemImage: "magnifyingglass")
                }
                ForEach(shownGames) { game in
                    NavigationLink(value: game) {
                        GameRow(game: game)
                    }
                    .disabled(store.reviewIsRequired(game))
                    .opacity(store.reviewIsRequired(game) ? 0.45 : 1)
                    .accessibilityIdentifier("game-\(game.id)")
                }
                if !store.failedReviews.isEmpty {
                    Button("Retry unfinished reviews") { Task { await store.analyzeRecent(10) } }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Time control", selection: Binding(get: { selectedTimeClass }, set: { store.gamesTimeClass = $0 })) {
                    ForEach(timeClasses, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("games-time-control")
                .padding(.horizontal).padding(.vertical, 6)
                .background(.background)
            }
            .listStyle(.plain)
            .navigationTitle("Your games")
            // A small title keeps the time-control tabs at the top instead of below a large blank title area.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChessComGame.self) { game in
                GameDetailView(game: game)
            }
            .refreshable { await store.refreshGames() }
            .overlay {
                if store.loadingGames && store.games.isEmpty { ProgressView("Loading games…") }
            }
            .task {
                if store.games.isEmpty { await store.refreshGames() }
                // Launch argument `-openGame N` opens the Nth game directly (handy for demos and screenshots).
                if UserDefaults.standard.object(forKey: "openGame") != nil {
                    let i = UserDefaults.standard.integer(forKey: "openGame")
                    if store.games.indices.contains(i) { path = [store.games[i]] }
                }
            }
        }
    }
}

struct GameRow: View {
    @EnvironmentObject var store: Store
    let game: ChessComGame

    var body: some View {
        let user = store.username
        let opp = game.opponent(of: user)
        let outcome = game.outcome(for: user)
        HStack(spacing: 12) {
            outcomeBadge(outcome)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(game.userColorIsWhite(user) ? Color.white : Color.black)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                        .frame(width: 10, height: 10)
                    Text("vs \(opp.username)").font(.headline).lineLimit(1)
                    if let r = opp.rating { Text("(\(r))").foregroundStyle(.secondary).font(.subheadline) }
                }
                HStack(spacing: 6) {
                    Text((game.timeClass ?? "").capitalized)
                    if let d = game.endDate {
                        Text("·")
                        Text(d, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.reviewIsRequired(game) {
                VStack(spacing: 3) {
                    Text(store.isAnalyzing(game) ? "Reviewing…" : "Waiting…").font(.caption2)
                    ReviewProgressBar(progress: store.reviewProgress, id: game.id).frame(width: 60)
                }
                .accessibilityIdentifier("review-progress")
            } else if let a = store.analyses[game.id] {
                let mine = game.userColorIsWhite(user) ? a.whiteSummary : a.blackSummary
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "Acc %.0f", mine.accuracy)).font(.headline.monospacedDigit())
                    if mine.blunder > 0 {
                        Text("\(mine.blunder) blunder\(mine.blunder == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(Grade.blunder.color)
                    } else {
                        Text("no blunders").font(.caption2).foregroundStyle(Grade.best.color)
                    }
                }
            } else {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func outcomeBadge(_ o: ChessComGame.Outcome) -> some View {
        let (text, color): (String, Color) = switch o {
        case .win: ("W", Grade.best.color)
        case .loss: ("L", Grade.blunder.color)
        case .draw: ("D", .gray)
        }
        return Text(text)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(color))
    }
}

/// Shows progress while a game is analysed, then the review.
struct GameDetailView: View {
    @EnvironmentObject var store: Store
    let game: ChessComGame

    var body: some View {
        Group {
            if let analysis = store.analyses[game.id] {
                ReviewView(analysis: analysis, userIsWhite: game.userColorIsWhite(store.username), gameId: game.id)
            } else {
                VStack(spacing: 18) {
                    ChessPiece(piece: "N", mood: .normal).frame(width: 80, height: 80)
                    Text("Meowy is reviewing your game…").font(.title3.bold())
                    ReviewProgressBar(progress: store.reviewProgress, id: game.id)
                        .padding(.horizontal, 48)
                    Text("The Rust engine is checking every position and working out the idea behind each move.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .task { await store.analyze(game) }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("vs \(game.opponent(of: store.username).username)")
    }
}
