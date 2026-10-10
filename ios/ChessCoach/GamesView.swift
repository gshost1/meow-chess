import SwiftUI

struct GamesView: View {
    @EnvironmentObject var store: Store
    @State private var path: [ChessComGame] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
                if store.games.isEmpty && !store.loadingGames {
                    ContentUnavailableView("No games yet", systemImage: "magnifyingglass",
                                           description: Text("Pull down to load your Chess.com games."))
                }
                ForEach(store.games) { game in
                    NavigationLink(value: game) {
                        GameRow(game: game)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Your games")
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
            if let p = store.progress[game.id] {
                ProgressView(value: p).frame(width: 50)
            } else if let a = store.analyses[game.id] {
                let mine = game.userColorIsWhite(user) ? a.whiteSummary : a.blackSummary
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", mine.accuracy)).font(.headline.monospacedDigit())
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
                ReviewView(analysis: analysis, userIsWhite: game.userColorIsWhite(store.username))
            } else {
                VStack(spacing: 18) {
                    Text("♞\u{FE0E}").font(.system(size: 64))
                    Text("Reviewing your game…").font(.title3.bold())
                    ProgressView(value: store.progress[game.id] ?? 0)
                        .padding(.horizontal, 48)
                    Text("The Rust engine is checking every position.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .task { await store.analyze(game) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("vs \(game.opponent(of: store.username).username)")
    }
}
