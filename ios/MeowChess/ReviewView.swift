import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var store: Store
    let analysis: GameAnalysis
    let userIsWhite: Bool
    let gameId: String

    /// 0 = starting position; n = position after move n.
    @State private var index = 0
    @State private var showBest = false
    /// While showing the best move: 0 = arrow on the original position, k = after the k-th move of the line.
    @State private var lineStep = 0
    @State private var animation: BoardAnimation?
    @State private var animKey = 0
    @State private var showSummary = false
    @State private var showChat = false

    private var current: MoveReview? { index > 0 ? analysis.moves[index - 1] : nil }

    private var myMistakeIndices: [Int] {
        analysis.moves.enumerated().compactMap { i, m in
            m.isWhite == userIsWhite && m.grade.isBad ? i + 1 : nil
        }
    }

    private var mySummary: SideSummary { userIsWhite ? analysis.whiteSummary : analysis.blackSummary }

    var body: some View {
        VStack(spacing: 8) {
            playerStrip(white: !userIsWhite)
            HStack(spacing: 6) {
                EvalBar(eval: displayedEval, flipped: !userIsWhite)
                boardView
                    .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                        if v.translation.width < -30 { step(1) } else if v.translation.width > 30 { step(-1) }
                    })
            }
            .padding(.horizontal, 8)
            playerStrip(white: userIsWhite)
            moveStrip
            ScrollView {
                infoCard.padding(.horizontal)
            }
            .accessibilityIdentifier("info-scroll")
            controls
        }
        .padding(.top, 4)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    toggleBest()
                } label: {
                    Image(systemName: showBest ? "lightbulb.fill" : "lightbulb")
                }
                .disabled(current == nil)
                .accessibilityLabel("Best move")
                .accessibilityIdentifier("toolbar-best")
                Button { showSummary = true } label: { Image(systemName: "chart.pie") }
                    .accessibilityLabel("Game summary")
                    .accessibilityIdentifier("toolbar-summary")
            }
        }
        .sheet(isPresented: $showSummary) {
            SummarySheet(analysis: analysis, userIsWhite: userIsWhite) { target in
                jump(to: target)
                showSummary = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChat) {
            if let m = current {
                MeowyChatView(
                    title: "\(m.numberLabel) \(m.san)",
                    facts: AIService.moveFacts(m, analysis: analysis, userIsWhite: userIsWhite),
                    rating: mySummary.playedLikeRating,
                    opening: "Explain move \(m.numberLabel) \(m.san) to me. What was it trying to do, what went right or wrong, and what should I learn from it?"
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if index == 0, let first = myMistakeIndices.first, ProcessInfo.processInfo.arguments.contains("-jumpToMistake") {
                index = first
            }
            if ProcessInfo.processInfo.arguments.contains("-showSummary") { showSummary = true }
            if ProcessInfo.processInfo.arguments.contains("-showBest") { showBest = true }
        }
    }

    // MARK: Board

    private var displayedEval: Eval {
        guard let m = current else { return analysis.moves.first?.evalBefore ?? Eval(cp: 0, mate: nil) }
        return showBest ? m.evalBefore : m.evalAfter
    }

    @ViewBuilder
    private var boardView: some View {
        let flipped = !userIsWhite
        if let m = current, showBest {
            let line = m.bestLineMoves ?? []
            if lineStep == 0 || line.isEmpty {
                let sq = uciSquares(m.bestUci)
                BoardView(fen: m.fenBefore, flipped: flipped,
                          highlights: sq.map { [$0.0, $0.1] } ?? [],
                          arrows: sq.map { [Arrow(from: $0.0, to: $0.1, color: Grade.best.color)] } ?? [],
                          moods: moods(fen: m.fenBefore, moved: nil, grade: nil, san: nil))
            } else {
                let lm = line[min(lineStep, line.count) - 1]
                let sq = uciSquares(lm.uci)
                BoardView(fen: lm.fen, flipped: flipped,
                          highlights: sq.map { [$0.0, $0.1] } ?? [],
                          moods: moods(fen: lm.fen, moved: sq?.1, grade: lineStep == 1 ? .best : nil, san: lm.san),
                          animation: animation)
            }
        } else if let m = current {
            let squares = uciSquares(m.uci)
            let reply = m.grade.isBad ? uciSquares(m.replyUci) : nil
            BoardView(
                fen: m.fenAfter,
                flipped: flipped,
                highlights: squares.map { [$0.0, $0.1] } ?? [],
                arrows: reply.map { [Arrow(from: $0.0, to: $0.1, color: Grade.blunder.color)] } ?? [],
                badge: squares.map { ($0.1, m.grade) },
                moods: moods(fen: m.fenAfter, moved: squares?.1, grade: m.grade, san: m.san),
                animation: animation
            )
        } else {
            BoardView(fen: analysis.startFen, flipped: flipped, animation: animation)
        }
    }

    /// Faces for the cats: the moved piece reacts to its grade, a king in check is shocked, a mated king is dizzy.
    private func moods(fen: String, moved: Square?, grade: Grade?, san: String?) -> [Square: PieceMood] {
        var out: [Square: PieceMood] = [:]
        if let moved, let grade {
            switch grade {
            case .best, .excellent, .forced: out[moved] = .happy
            case .good: out[moved] = .normal
            case .inaccuracy, .mistake: out[moved] = .worried
            case .blunder: out[moved] = .sad
            }
        }
        if let san, san.hasSuffix("+") || san.hasSuffix("#") {
            let whiteToMove = fen.split(separator: " ").dropFirst().first == "w"
            let board = parseBoard(fen)
            if let k = board.firstIndex(of: whiteToMove ? "K" : "k") {
                out[Square(k)] = san.hasSuffix("#") ? .dizzy : .shocked
            }
            if san.hasSuffix("#"), let moved { out[moved] = .happy }
        }
        return out
    }

    private func rookSlide(_ from: Square, _ to: Square, san: String) -> Slide? {
        guard san.hasPrefix("O-O") else { return nil }
        let rank = from.rank
        if to.file == 6 { return Slide(from: Square(rank * 8 + 7), to: Square(rank * 8 + 5)) }
        if to.file == 2 { return Slide(from: Square(rank * 8 + 0), to: Square(rank * 8 + 3)) }
        return nil
    }

    private func forwardAnimation(uci: String, san: String, fenBefore: String) -> BoardAnimation? {
        guard let (from, to) = uciSquares(uci) else { return nil }
        animKey += 1
        var anim = BoardAnimation(key: animKey, slides: [Slide(from: from, to: to)])
        if let rook = rookSlide(from, to, san: san) { anim.slides.append(rook) }
        let before = parseBoard(fenBefore)
        if san.contains("x") {
            if let victim = before[to.index] {
                anim.poof = Poof(piece: victim, square: to)
            } else {
                // En passant: the captured pawn sits beside the destination.
                let sq = Square(from.rank * 8 + to.file)
                if let victim = before[sq.index] { anim.poof = Poof(piece: victim, square: sq) }
            }
        }
        return anim
    }

    private func backwardAnimation(_ m: MoveReview) -> BoardAnimation? {
        guard let (from, to) = uciSquares(m.uci) else { return nil }
        animKey += 1
        var anim = BoardAnimation(key: animKey, slides: [Slide(from: to, to: from)])
        if let rook = rookSlide(from, to, san: m.san) { anim.slides.append(Slide(from: rook.to, to: rook.from)) }
        return anim
    }

    // MARK: Navigation

    private func step(_ d: Int) {
        if showBest {
            let count = current?.bestLineMoves?.count ?? 0
            let next = min(max(lineStep + d, 0), count)
            guard next != lineStep, let m = current else { return }
            if next > lineStep, let line = m.bestLineMoves {
                let lm = line[next - 1]
                let fenBefore = next >= 2 ? line[next - 2].fen : m.fenBefore
                animation = forwardAnimation(uci: lm.uci, san: lm.san, fenBefore: fenBefore)
                SoundPlayer.shared.play(lm.san.hasSuffix("#") ? .checkmate : lm.san.hasSuffix("+") ? .check : lm.san.contains("x") ? .capture : .move)
            } else {
                animation = nil
            }
            lineStep = next
            return
        }
        let newIndex = min(max(index + d, 0), analysis.moves.count)
        guard newIndex != index else { return }
        if newIndex == index + 1 {
            let m = analysis.moves[newIndex - 1]
            animation = forwardAnimation(uci: m.uci, san: m.san, fenBefore: m.fenBefore)
            SoundPlayer.shared.play(for: m)
        } else if newIndex == index - 1, let m = current {
            animation = backwardAnimation(m)
        } else {
            animation = nil
        }
        index = newIndex
    }

    private func jump(to target: Int) {
        animation = nil
        showBest = false
        lineStep = 0
        index = target
        if let m = current { SoundPlayer.shared.play(for: m) }
    }

    private func toggleBest() {
        animation = nil
        lineStep = 0
        withAnimation(.easeInOut(duration: 0.2)) { showBest.toggle() }
        if showBest { SoundPlayer.shared.play(.best) }
    }

    // MARK: Pieces of the layout

    private func playerStrip(white: Bool) -> some View {
        let name = white ? analysis.white : analysis.black
        let elo = white ? analysis.whiteElo : analysis.blackElo
        let summary = white ? analysis.whiteSummary : analysis.blackSummary
        return HStack(spacing: 8) {
            CatPiece(piece: white ? "K" : "k").frame(width: 24, height: 24)
            Text(name).font(.subheadline.bold())
            if let elo { Text("(\(elo))").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            Text(String(format: "Accuracy %.1f%%", summary.accuracy))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    private var moveStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(analysis.moves) { m in
                        Button { jump(to: m.ply) } label: {
                            HStack(spacing: 2) {
                                if m.isWhite { Text("\(m.moveNumber).").foregroundStyle(.secondary) }
                                Text(m.san)
                                if m.grade.isBad { Text(m.grade.symbol).foregroundStyle(m.grade.color).bold() }
                            }
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(m.ply == index ? Color.accentColor.opacity(0.35) : Color(white: 0.16))
                            )
                        }
                        .buttonStyle(.plain)
                        .id(m.ply)
                    }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: index) { _, new in
                withAnimation { proxy.scrollTo(max(new, 1), anchor: .center) }
            }
        }
    }

    private func quizApplies(_ m: MoveReview) -> Bool {
        guard m.isWhite == userIsWhite else { return false }
        switch store.quizMode {
        case .off: return false
        case .all: return true
        case .key:
            let tactical: Set<String> = ["fork", "pin", "capture", "checkmate", "king_attack"]
            return m.grade.isBad || (m.ideas ?? []).contains { tactical.contains($0.kind) }
        }
    }

    @ViewBuilder
    private var infoCard: some View {
        if let m = current {
            let mine = m.isWhite == userIsWhite
            let answer = store.answers[Store.answerKey(game: gameId, ply: m.ply)]
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(m.grade.symbol)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(m.grade.color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(m.numberLabel) \(m.san)  ·  \(mine ? "Your move" : "Opponent")")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("move-label")
                        Text(m.headline).font(.headline)
                    }
                    Spacer()
                }

                if quizApplies(m) && answer == nil {
                    IdeaQuiz(move: m) { a in
                        store.saveAnswer(a, game: gameId, ply: m.ply)
                        if a.choice != "skipped" {
                            SoundPlayer.shared.play(a.matched == true ? .correct : .mistake)
                        }
                    }
                } else {
                    if let answer, answer.choice != "skipped" {
                        QuizFeedback(move: m, answer: answer)
                    }
                    explanationSections(m)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CatPiece(piece: "Q", mood: .happy).frame(width: 36, height: 36)
                    Text("Meowy's game review").font(.headline)
                }
                Text("You made \(mySummary.blunder) blunder\(mySummary.blunder == 1 ? "" : "s"), \(mySummary.mistake) mistake\(mySummary.mistake == 1 ? "" : "s") and \(mySummary.inaccuracy) inaccurac\(mySummary.inaccuracy == 1 ? "y" : "ies").")
                    .font(.callout)
                if let r = mySummary.playedLikeRating {
                    Text("This game you played like a ~\(r) player.").font(.callout).foregroundStyle(.secondary)
                }
                Text("Swipe the board or tap → to step through. Tap 💡 any time to see the best move.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
        }
    }

    @ViewBuilder
    private func explanationSections(_ m: MoveReview) -> some View {
        if let ideas = m.ideasText {
            section("What it does", icon: "eye") { Text(ideas) }
        }
        if m.grade.isBad {
            section("What went wrong", icon: "exclamationmark.triangle", tint: m.grade.color) { Text(m.explanation) }
        }
        if let threat = m.opponentThreat {
            section("Before this move", icon: "bolt.fill", tint: Grade.mistake.color) { Text(threat) }
        }
        section("Best move", icon: "lightbulb.fill", tint: Grade.best.color) {
            VStack(alignment: .leading, spacing: 8) {
                if m.playedIsBest {
                    Text("★ \(m.san) was the engine's top choice.")
                } else if let best = m.bestText {
                    Text(best)
                } else {
                    Text("\(m.bestSan) was the engine's choice.")
                }
                HStack(spacing: 10) {
                    Button { toggleBest() } label: {
                        Label(showBest ? "Back to the game" : "Show \(m.bestSan)",
                              systemImage: showBest ? "arrow.uturn.backward" : "lightbulb")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(showBest ? .gray : Grade.best.color)
                    .accessibilityIdentifier("show-best")
                    if showBest, let line = m.bestLineMoves, !line.isEmpty {
                        Text(lineStep == 0 ? "Tap → to play the line" : "Move \(lineStep) of \(line.count): \(line[lineStep - 1].san)")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("best-line-status")
                    }
                }
            }
        }
        Button { showChat = true } label: {
            HStack {
                CatPiece(piece: "Q", mood: .happy).frame(width: 26, height: 26)
                Text("Ask Meowy about this move").font(.subheadline.bold())
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ask-meowy")
    }

    private func section<Content: View>(_ title: String, icon: String, tint: Color = .secondary,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(tint)
            content().font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            iconButton("backward.end.fill", "First position") { jump(to: 0) }
            iconButton("chevron.left", "Previous move") { step(-1) }
            Button {
                if let next = myMistakeIndices.first(where: { $0 > index }) ?? myMistakeIndices.first {
                    jump(to: next)
                }
            } label: {
                Label("Next mistake", systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(Grade.mistake.color)
            .disabled(myMistakeIndices.isEmpty)
            .accessibilityIdentifier("next-mistake")
            iconButton("chevron.right", "Next move") { step(1) }
            iconButton("forward.end.fill", "Last position") { jump(to: analysis.moves.count) }
        }
        .padding(.bottom, 8)
    }

    private func iconButton(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.title3).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - "What was your idea?" quiz

struct IdeaQuiz: View {
    let move: MoveReview
    let onAnswer: (QuizAnswer) -> Void

    @State private var typed = ""
    @State private var asking = false
    @State private var error: String?

    private var actual: [IdeaCategory] {
        var seen: [IdeaCategory] = []
        for i in move.ideas ?? [] where !seen.contains(i.category) { seen.append(i.category) }
        return seen
    }

    /// The move's real ideas plus a few plausible wrong answers, in a stable order per move.
    private var options: [IdeaCategory] {
        var rng = SeededRandom(seed: UInt64(move.ply * 7919 + 17))
        let real = Array(actual.prefix(2))
        let others = IdeaCategory.allCases.filter { !actual.contains($0) }.shuffled(using: &rng)
        return (real + others.prefix(4 - real.count)).shuffled(using: &rng)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CatPiece(piece: "Q", mood: .normal).frame(width: 30, height: 30)
                Text("Meowy asks: what was your idea with \(move.san)?").font(.subheadline.bold())
                    .accessibilityIdentifier("quiz-question")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(options) { c in
                    Button {
                        onAnswer(QuizAnswer(choice: c.rawValue, matched: actual.contains(c)))
                    } label: {
                        Label(c.label, systemImage: c.icon)
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("quiz-\(c.rawValue)")
                }
            }
            if AIConfig.jevReady {
                HStack {
                    TextField("Or say it in your own words…", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit(askJev)
                        .accessibilityIdentifier("quiz-typed")
                    Button(action: askJev) {
                        if asking { ProgressView() } else { Image(systemName: "paperplane.fill") }
                    }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || asking)
                    .accessibilityLabel("Send to Jev")
                    .accessibilityIdentifier("quiz-send")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button("Not sure") { onAnswer(QuizAnswer(choice: "unsure", matched: nil)) }
                    .accessibilityIdentifier("quiz-unsure")
                Spacer()
                Button("Skip") { onAnswer(QuizAnswer(choice: "skipped", matched: nil)) }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("quiz-skip")
            }
            .font(.footnote)
        }
    }

    private func askJev() {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        asking = true
        error = nil
        Task {
            do {
                let d = try await AIService.classifyIntent(text, move: move)
                let matched = actual.contains(d.category) || d.achieves >= 0.5
                onAnswer(QuizAnswer(choice: d.category.rawValue, matched: matched, typed: text, confidence: d.probability))
            } catch {
                self.error = error.localizedDescription
            }
            asking = false
        }
    }
}

struct QuizFeedback: View {
    let move: MoveReview
    let answer: QuizAnswer

    var body: some View {
        let (title, body, good) = feedback
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(good ? Grade.best.color : Grade.inaccuracy.color)
            if let typed = answer.typed {
                Text("You said: “\(typed)”" + (answer.confidence.map { String(format: " (Jev is %.0f%% sure you meant: %@)", $0 * 100, IdeaCategory(rawValue: answer.choice)?.label.lowercased() ?? "") } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill((good ? Grade.best.color : Grade.inaccuracy.color).opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-feedback")
    }

    private var feedback: (String, String, Bool) {
        let ideas = move.ideasText ?? move.san
        guard let cat = IdeaCategory(rawValue: answer.choice) else {
            return ("No problem!", "Here's what the move does: \(ideas)", true)
        }
        let goodMove = !move.grade.isBad
        let bestMatch = (move.bestIdeas ?? []).first { $0.category == cat }
        if answer.matched == true {
            if goodMove {
                return ("😺 Spot on!", "You read your own move right, and it was a good idea. \(ideas)", true)
            }
            // Headlines look like "Mistake: loses the rook"; keep only the part after the grade.
            let what = move.headline.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? move.headline
            let lowered = what.prefix(1).lowercased() + what.dropFirst()
            var text = "You read your move right: it does try to \(cat.verb). But the idea backfired: \(lowered)\(lowered.hasSuffix(".") ? "" : ".")"
            if !move.playedIsBest {
                text += bestMatch.map { " \(move.bestSan) also \($0.text), and does it safely." } ?? " \(move.bestSan) was the better move here."
            }
            return ("😼 Right idea, wrong moment", text, false)
        }
        var text = "\(move.san) doesn't really \(cat.verb). What it actually does: \(ideas)"
        if let bestMatch, !move.playedIsBest {
            text += " If you wanted to \(cat.verb), \(move.bestSan) was the way: it \(bestMatch.text)."
        }
        return ("🙀 Not quite", text, false)
    }
}

/// Small deterministic random generator so the quiz options don't reshuffle on every redraw.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Summary

struct SummarySheet: View {
    let analysis: GameAnalysis
    let userIsWhite: Bool
    let jump: (Int) -> Void

    var body: some View {
        let mine = userIsWhite ? analysis.whiteSummary : analysis.blackSummary
        let theirs = userIsWhite ? analysis.blackSummary : analysis.whiteSummary
        let worst = analysis.moves
            .filter { $0.isWhite == userIsWhite && $0.grade.isBad }
            .sorted { $0.winDrop > $1.winDrop }
            .prefix(3)
        NavigationStack {
            List {
                Section {
                    HStack {
                        accuracyBlock("Your", mine.accuracy, mine.playedLikeRating)
                        Spacer()
                        accuracyBlock("Opponent's", theirs.accuracy, theirs.playedLikeRating)
                    }
                }
                if let plan = mine.plan {
                    Section("Your plan this game") {
                        HStack {
                            Text(plan.style).font(.headline)
                            Spacer()
                            Text("Focus: \(plan.focus)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(plan.styleDetail).font(.callout)
                        ForEach(plan.highlights, id: \.self) { Text("• \($0)").font(.callout) }
                    }
                }
                Section("Your moves") {
                    row(.best, mine.best)
                    row(.excellent, mine.excellent)
                    row(.good, mine.good)
                    row(.inaccuracy, mine.inaccuracy)
                    row(.mistake, mine.mistake)
                    row(.blunder, mine.blunder)
                }
                if !worst.isEmpty {
                    Section("Biggest moments") {
                        ForEach(Array(worst)) { m in
                            Button { jump(m.ply) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(m.numberLabel) \(m.san) — \(m.headline)").font(.subheadline.bold())
                                    Text(m.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                    }
                }
                if let t = analysis.termination {
                    Section { Text(t).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func accuracyBlock(_ title: String, _ value: Double, _ rating: Int?) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", value)).font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(title) accuracy").font(.caption).foregroundStyle(.secondary)
            if let rating { Text("played like ~\(rating)").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ g: Grade, _ n: Int) -> some View {
        HStack {
            Text(g.symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(g.color))
            Text(g.label)
            Spacer()
            Text("\(n)").font(.body.monospacedDigit().bold())
        }
    }
}
