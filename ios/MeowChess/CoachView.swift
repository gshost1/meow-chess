import Charts
import SwiftUI


struct HabitInfo {
    let title: String
    let tip: String
    let icon: String

    /// A concrete exercise for the training plan.
    static func drill(_ tag: String) -> String {
        switch tag {
        case "hung_piece":
            return "Blunder check: before every move, touch nothing until you've asked \"after this, what can they capture?\""
        case "ignored_threat":
            return "Threat check: after each opponent move, say out loud what it attacks before you think about your own plan."
        case "allowed_mate", "missed_mate":
            return "Checks first: every move, list all checks for both sides. Do 10 mate-in-1 puzzles a day."
        case "missed_win":
            return "Free piece scan: each move, look at every enemy piece and ask \"is it protected?\""
        case "allowed_fork", "missed_fork", "allowed_pin":
            return "Tactics practice: solve your own mistake puzzles in Practice, then 10 fork/pin puzzles a day."
        case "early_queen":
            return "Opening rule: move a knight or bishop on each of your first 5 moves before the queen."
        case "early_king_move", "weakened_king":
            return "Castle by move 10 in your next 5 games."
        default:
            return "Slow down on quiet moves: find your worst-placed piece and improve it."
        }
    }

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

/// Meowy, the coach: playing strength, style, plans, habits and a training plan.
struct CoachView: View {
    @EnvironmentObject var store: Store
    @State private var aiPlan: String?
    @State private var aiLoading = false
    @State private var aiError: String?

    struct Stats {
        var games = 0
        var mistakes = 0
        var moves = 0
        var cpLoss = 0
        var tagCounts: [String: Int] = [:]
        var phaseCounts: [String: Int] = [:]
        var categoryCounts: [IdeaCategory: Int] = [:]
        var styleCounts: [String: Int] = [:]
        var focusCounts: [String: Int] = [:]
        var castledByTen = 0
        var blunders = 0
        var accuracies: [(Date, Double)] = []
        var ratings: [(Date, Int)] = []
        var plans: [(String, PlanSummary)] = []
        var quizRight = 0
        var quizWrong = 0
        var quizUnsure = 0
        var chessComRating: Int?
    }

    static func rating(acpl: Double) -> Int {
        // Must match rating_from_acpl in core/src/analysis.rs.
        let r = 4000 * exp(-0.035 * acpl)
        return Int(min(2800, max(100, (r / 25).rounded() * 25)))
    }

    private var stats: Stats {
        var s = Stats()
        let user = store.username
        for game in store.games {
            if s.chessComRating == nil { s.chessComRating = game.me(user).rating }
            guard let a = store.analyses[game.id], let white = a.userIsWhite(user) else { continue }
            s.games += 1
            let summary = white ? a.whiteSummary : a.blackSummary
            if let c = summary.castledOnMove, c <= 10 { s.castledByTen += 1 }
            s.blunders += summary.blunder
            let date = game.endDate ?? .now
            s.accuracies.append((date, summary.accuracy))
            let mine = a.moves.filter { $0.isWhite == white }
            if !mine.isEmpty {
                // Recomputed rather than read from the saved review so older reviews use the current formula.
                let loss = mine.reduce(0) { $0 + ($1.cpLoss ?? 0) }
                s.ratings.append((date, Self.rating(acpl: Double(loss) / Double(mine.count))))
            }
            if let plan = summary.plan {
                s.styleCounts[plan.style, default: 0] += 1
                s.focusCounts[plan.focus, default: 0] += 1
                if s.plans.count < 3 { s.plans.append((white ? a.black : a.white, plan)) }
            }
            for m in a.moves where m.isWhite == white {
                s.moves += 1
                s.cpLoss += m.cpLoss ?? 0
                for c in Set((m.ideas ?? []).map(\.category)) { s.categoryCounts[c, default: 0] += 1 }
                if let ans = store.answers[Store.answerKey(game: game.id, ply: m.ply)] {
                    if ans.choice == "unsure" { s.quizUnsure += 1 }
                    else if ans.matched == true { s.quizRight += 1 }
                    else if ans.matched == false { s.quizWrong += 1 }
                }
                guard m.grade == .mistake || m.grade == .blunder else { continue }
                s.mistakes += 1
                s.phaseCounts[m.phase, default: 0] += 1
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
                Section {
                    HStack(spacing: 12) {
                        CatPiece(piece: "Q", mood: .happy).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hi, I'm Meowy!").font(.title3.bold())
                            Text(s.games == 0
                                 ? "Review a few games and I'll tell you how strong you play, what your style is, and what to practice."
                                 : "I looked at \(s.games) of your games. Here's what I found.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if s.games == 0 { analyzeButton }
                }
                if s.games > 0 && s.moves > 0 {
                    strengthSection(s)
                    styleSection(s)
                    if !s.plans.isEmpty { plansSection(s) }
                    habitsSection(s)
                    trainingSection(s)
                    if s.quizRight + s.quizWrong + s.quizUnsure > 0 { quizSection(s) }
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
            .navigationTitle("Meowy")
            .task {
                let n = UserDefaults.standard.integer(forKey: "autoReview")
                if n > 0 {
                    if store.games.isEmpty { await store.refreshGames() }
                    await store.analyzeRecent(n)
                }
            }
        }
    }

    private func strengthSection(_ s: Stats) -> some View {
        let acpl = Double(s.cpLoss) / Double(max(s.moves, 1))
        let est = Self.rating(acpl: acpl)
        return Section("Your playing strength") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("~\(est)").font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("how you actually play").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let r = s.chessComRating {
                    VStack(alignment: .trailing) {
                        Text("\(r)").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("your Chess.com rating").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let r = s.chessComRating {
                Text(est > r + 100
                     ? "You're playing better than your rating shows. Cut down the blunders and your rating will catch up."
                     : est < r - 100
                     ? "Your rating is ahead of your accuracy right now. Slowing down before each move will help."
                     : "Your rating matches how you play. Fixing your top habit below is the fastest way up.")
                    .font(.callout)
            }
            Text(String(format: "A rough guess from an average loss of %.0f centipawns (hundredths of a pawn) per move across %d moves. Single games swing a lot; it gets steadier as you review more.", acpl, s.moves))
                .font(.caption).foregroundStyle(.secondary)
            if s.ratings.count >= 2 {
                Chart(Array(s.ratings.sorted { $0.0 < $1.0 }.enumerated()), id: \.offset) { i, p in
                    LineMark(x: .value("Game", i + 1), y: .value("Strength", p.1))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Game", i + 1), y: .value("Strength", p.1))
                }
                .frame(height: 120)
            }
        }
    }

    private func styleSection(_ s: Stats) -> some View {
        let style = s.styleCounts.max { $0.value < $1.value }?.key ?? "Balanced"
        let focus = s.focusCounts.max { $0.value < $1.value }?.key ?? "the center"
        let top = s.categoryCounts.sorted { $0.value > $1.value }.prefix(6)
        let blurb: String = switch style {
        case "Attacker": "You love to create threats and go after your opponent's pieces."
        case "Defender": "You spend a lot of moves protecting and saving pieces."
        case "Builder": "You like to develop, castle and improve your pieces before fighting."
        default: "You mix attacking and defending."
        }
        return Section("Your style") {
            HStack {
                Text(style).font(.title3.bold())
                Spacer()
                Text("Most action: \(focus)").font(.caption).foregroundStyle(.secondary)
            }
            Text(blurb).font(.callout)
            Text("What your moves were about").font(.caption.bold()).foregroundStyle(.secondary)
            Chart(Array(top), id: \.key) { c, n in
                BarMark(x: .value("Moves", n), y: .value("Idea", c.label))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: CGFloat(top.count) * 28 + 10)
        }
    }

    private func plansSection(_ s: Stats) -> some View {
        Section("Your plans in recent games") {
            ForEach(Array(s.plans.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("vs \(item.0) · \(item.1.style)").font(.subheadline.bold())
                    ForEach(item.1.highlights, id: \.self) { Text("• \($0)").font(.caption) }
                }
            }
        }
    }

    private func habitsSection(_ s: Stats) -> some View {
        let sorted = s.tagCounts.sorted { $0.value > $1.value }
        let total = max(s.mistakes, 1)
        return Section("What costs you the most") {
            ForEach(sorted.prefix(5), id: \.key) { tag, count in
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
                        ProgressView(value: Double(count), total: Double(total)).tint(Grade.mistake.color)
                    }
                    Text(info.tip).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func trainingSection(_ s: Stats) -> some View {
        let top = s.tagCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        return Section("Your training plan") {
            ForEach(Array(top.enumerated()), id: \.offset) { i, tag in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.headline).frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor.opacity(0.3)))
                    Text(HabitInfo.drill(tag)).font(.callout)
                }
            }
            Button {
                store.tab = "practice"
            } label: {
                Label("Practice puzzles from your own mistakes (\(store.puzzles.count))", systemImage: "puzzlepiece.extension")
            }
            if AIConfig.chatReady {
                if let aiPlan {
                    Text(aiPlan).font(.callout).textSelection(.enabled)
                }
                Button {
                    Task { await askPlan(s, top: top) }
                } label: {
                    HStack {
                        Label(aiPlan == nil ? "Ask Meowy AI for a personal plan" : "Ask again", systemImage: "sparkles")
                        if aiLoading { Spacer(); ProgressView() }
                    }
                }
                .disabled(aiLoading)
                if let aiError { Text(aiError).font(.caption).foregroundStyle(.red) }
            }
        }
    }

    private func quizSection(_ s: Stats) -> some View {
        let answered = s.quizRight + s.quizWrong
        return Section("Knowing your own ideas") {
            if answered > 0 {
                Text("You described your own idea correctly \(s.quizRight * 100 / answered)% of the time (\(answered) answers).")
            }
            if s.quizUnsure > 0 {
                Text("You weren't sure about \(s.quizUnsure) move\(s.quizUnsure == 1 ? "" : "s"). Try to have a reason for every move, even a simple one.")
                    .font(.callout)
            }
            Text("Strong players always know why they play a move. When your idea and the move's real effect don't match, that's where blunders hide.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func askPlan(_ s: Stats, top: [String]) async {
        aiLoading = true
        aiError = nil
        let acpl = Double(s.cpLoss) / Double(max(s.moves, 1))
        let style = s.styleCounts.max { $0.value < $1.value }?.key ?? "Balanced"
        var facts = [
            "Games reviewed: \(s.games). Estimated playing strength: ~\(Self.rating(acpl: acpl)). Chess.com rating: \(s.chessComRating.map(String.init) ?? "unknown").",
            "Blunders per game: \(String(format: "%.1f", Double(s.blunders) / Double(max(s.games, 1)))). Style: \(style).",
            "Castled by move 10 in \(s.castledByTen) of \(s.games) games.",
            "Mistakes by phase: " + ["opening", "middlegame", "endgame"].map { "\($0) \(s.phaseCounts[$0] ?? 0)" }.joined(separator: ", ") + ".",
            "Most common problems: " + top.map { "\(HabitInfo.of($0).title) (\(s.tagCounts[$0] ?? 0))" }.joined(separator: ", ") + ".",
        ]
        if s.quizRight + s.quizWrong > 0 {
            facts.append("Correctly described their own move ideas \(s.quizRight) of \(s.quizRight + s.quizWrong) times.")
        }
        let messages = [
            ChatMessage(role: "system", content: AIService.systemPrompt(rating: Self.rating(acpl: acpl)) + "\n\nPlayer facts:\n" + facts.joined(separator: "\n")),
            ChatMessage(role: "user", content: "Write me a one-week training plan with 3 daily habits, based on my facts. Keep it short and encouraging."),
        ]
        do {
            aiPlan = try await AIService.chat(messages)
        } catch {
            aiError = error.localizedDescription
        }
        aiLoading = false
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
}
