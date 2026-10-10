import Charts
import SwiftUI

struct HabitInfo {
    let title: String
    let tip: String
    let icon: String

    static func of(_ tag: String) -> HabitInfo {
        switch tag {
        case "hung_piece":
            return .init(title: "Leaving pieces unprotected",
                         tip: "Before you let go of a piece, ask: can it be captured for free on its new square? Is anything it was guarding now loose?",
                         icon: "shield.slash")
        case "ignored_threat":
            return .init(title: "Not noticing attacks",
                         tip: "After every opponent move, ask: what does that move attack? Deal with the threat before making your own plans.",
                         icon: "eye.slash")
        case "allowed_mate":
            return .init(title: "Missing checkmate threats",
                         tip: "Look at every check your opponent could give after your move, especially on your back rank and near f7/f2.",
                         icon: "crown")
        case "missed_mate":
            return .init(title: "Missing your own checkmates",
                         tip: "Each move, look at all your checks first. Checks are the most forcing moves on the board.",
                         icon: "flag.checkered")
        case "missed_win":
            return .init(title: "Missing free pieces",
                         tip: "Scan your opponent's pieces each move: is anything undefended? Free material wins games at every level.",
                         icon: "gift")
        case "allowed_fork", "missed_fork":
            return .init(title: "Forks",
                         tip: "Knights and queens love to attack two things at once. Avoid leaving your king and queen (or two rooks) a knight's jump apart.",
                         icon: "arrow.triangle.branch")
        case "allowed_pin":
            return .init(title: "Pins and skewers",
                         tip: "Be careful when a valuable piece sits behind another on a line a bishop, rook or queen could use.",
                         icon: "pin")
        case "lost_material":
            return .init(title: "Losing material to tactics",
                         tip: "Before moving, picture your opponent's strongest reply, not just the one you hope for.",
                         icon: "minus.circle")
        case "early_queen":
            return .init(title: "Bringing the queen out early",
                         tip: "Develop knights and bishops first. An early queen gets chased around, and your opponent develops while attacking it.",
                         icon: "figure.walk")
        case "early_king_move", "weakened_king":
            return .init(title: "King safety",
                         tip: "Castle early, usually in the first 10 moves, and avoid pushing the pawns in front of your king.",
                         icon: "house")
        default:
            return .init(title: "Slightly weaker moves",
                         tip: "No direct tactic here, just a better plan. Improve your worst piece and control the centre.",
                         icon: "slider.horizontal.3")
        }
    }
}

struct HabitsView: View {
    @EnvironmentObject var store: Store

    private struct Stats {
        var games = 0
        var mistakes = 0
        var tagCounts: [String: Int] = [:]
        var phaseCounts: [String: Int] = [:]
        var castledByTen = 0
        var accuracies: [(Date, Double)] = []
        var blunders = 0
    }

    private var stats: Stats {
        var s = Stats()
        let user = store.username
        for game in store.games {
            guard let a = store.analyses[game.id], let white = a.userIsWhite(user) else { continue }
            s.games += 1
            let summary = white ? a.whiteSummary : a.blackSummary
            if let c = summary.castledOnMove, c <= 10 { s.castledByTen += 1 }
            s.blunders += summary.blunder
            s.accuracies.append((game.endDate ?? .now, summary.accuracy))
            for m in a.moves where m.isWhite == white && (m.grade == .mistake || m.grade == .blunder) {
                s.mistakes += 1
                s.phaseCounts[m.phase, default: 0] += 1
                // Group the related tags under one habit.
                let tag = m.tags.first { $0 != "early_queen" && $0 != "early_king_move" } ?? "positional"
                let key = tag == "missed_fork" ? "allowed_fork" : (tag == "weakened_king" ? "early_king_move" : tag)
                s.tagCounts[key, default: 0] += 1
            }
            for m in a.moves where m.isWhite == white && m.tags.contains("early_queen") {
                s.tagCounts["early_queen", default: 0] += 1
            }
        }
        return s
    }

    var body: some View {
        NavigationStack {
            let s = stats
            List {
                if s.games == 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Review a few games to see your patterns.").font(.headline)
                            Text("Chess Coach looks across all your reviewed games to find the mistakes you make most often.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        analyzeButton
                    }
                } else {
                    Section {
                        HStack {
                            metric("\(s.games)", "games reviewed")
                            metric(String(format: "%.0f%%", s.accuracies.map(\.1).reduce(0, +) / Double(s.games)), "avg accuracy")
                            metric(String(format: "%.1f", Double(s.blunders) / Double(s.games)), "blunders / game")
                        }
                    }
                    if s.accuracies.count >= 2 {
                        Section("Accuracy over time") {
                            Chart(Array(s.accuracies.sorted { $0.0 < $1.0 }.enumerated()), id: \.offset) { i, p in
                                LineMark(x: .value("Game", i + 1), y: .value("Accuracy", p.1))
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Game", i + 1), y: .value("Accuracy", p.1))
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 140)
                        }
                    }
                    Section("What costs you the most") {
                        let sorted = s.tagCounts.sorted { $0.value > $1.value }
                        let total = max(s.mistakes, 1)
                        ForEach(sorted.prefix(6), id: \.key) { tag, count in
                            let info = HabitInfo.of(tag)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: info.icon).frame(width: 22)
                                    Text(info.title).font(.headline)
                                    Spacer()
                                    Text(tag == "early_queen" ? "\(count)×" : "\(count * 100 / total)%")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(Grade.mistake.color)
                                }
                                if tag != "early_queen" {
                                    ProgressView(value: Double(count), total: Double(total))
                                        .tint(Grade.mistake.color)
                                }
                                Text(info.tip).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section("When your mistakes happen") {
                        Chart(["opening", "middlegame", "endgame"], id: \.self) { phase in
                            BarMark(x: .value("Phase", phase.capitalized), y: .value("Mistakes", s.phaseCounts[phase] ?? 0))
                                .foregroundStyle(Grade.mistake.color)
                        }
                        .frame(height: 120)
                    }
                    Section("King safety") {
                        Text("You castled by move 10 in \(s.castledByTen) of \(s.games) games.")
                        if s.castledByTen * 2 < s.games {
                            Text("Try to castle earlier: an uncastled king in the middle is the easiest target on the board.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section { analyzeButton }
                }
            }
            .navigationTitle("My habits")
            .task {
                let n = UserDefaults.standard.integer(forKey: "autoReview")
                if n > 0 {
                    if store.games.isEmpty { await store.refreshGames() }
                    await store.analyzeRecent(n)
                }
            }
        }
    }

    private var analyzeButton: some View {
        let pending = store.games.prefix(10).filter { store.analyses[$0.id] == nil }.count
        let running = !store.progress.isEmpty
        return Button {
            Task { await store.analyzeRecent(10) }
        } label: {
            HStack {
                Label(running ? "Reviewing…" : "Review my last 10 games", systemImage: "wand.and.stars")
                Spacer()
                if running { ProgressView() } else if pending > 0 { Text("\(pending) new").foregroundStyle(.secondary) }
            }
        }
        .disabled(running || pending == 0)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
