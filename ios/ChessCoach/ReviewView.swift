import SwiftUI

struct ReviewView: View {
    let analysis: GameAnalysis
    let userIsWhite: Bool

    /// 0 = starting position; n = position after move n.
    @State private var index = 0
    @State private var showBetter = false
    @State private var showSummary = false

    private var current: MoveReview? { index > 0 ? analysis.moves[index - 1] : nil }

    private var myMistakeIndices: [Int] {
        analysis.moves.enumerated().compactMap { i, m in
            m.isWhite == userIsWhite && m.grade.isBad ? i + 1 : nil
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            playerStrip(white: !userIsWhite)
            HStack(spacing: 6) {
                EvalBar(eval: displayedEval, flipped: !userIsWhite)
                board
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
            controls
        }
        .padding(.top, 4)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSummary = true } label: { Image(systemName: "chart.pie") }
            }
        }
        .sheet(isPresented: $showSummary) {
            SummarySheet(analysis: analysis, userIsWhite: userIsWhite) { target in
                index = target
                showBetter = false
                showSummary = false
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            // Jump straight to the first lesson when there is one.
            if index == 0, let first = myMistakeIndices.first, ProcessInfo.processInfo.arguments.contains("-jumpToMistake") {
                index = first
            }
            if ProcessInfo.processInfo.arguments.contains("-showSummary") { showSummary = true }
        }
    }

    private var displayedEval: Eval {
        guard let m = current else { return analysis.moves.first?.evalBefore ?? Eval(cp: 0, mate: nil) }
        return showBetter ? m.evalBefore : m.evalAfter
    }

    @ViewBuilder
    private var board: some View {
        if let m = current {
            if showBetter, let (bf, bt) = uciSquares(m.bestUci) {
                BoardView(fen: m.fenBefore, flipped: !userIsWhite, highlights: [bf, bt],
                          arrows: [Arrow(from: bf, to: bt, color: Grade.best.color)])
            } else {
                let squares = uciSquares(m.uci)
                let reply = m.grade.isBad ? uciSquares(m.replyUci) : nil
                BoardView(
                    fen: m.fenAfter,
                    flipped: !userIsWhite,
                    highlights: squares.map { [$0.0, $0.1] } ?? [],
                    arrows: reply.map { [Arrow(from: $0.0, to: $0.1, color: Grade.blunder.color)] } ?? [],
                    badge: squares.map { ($0.1, m.grade) }
                )
            }
        } else {
            BoardView(fen: analysis.startFen, flipped: !userIsWhite)
        }
    }

    private func playerStrip(white: Bool) -> some View {
        let name = white ? analysis.white : analysis.black
        let elo = white ? analysis.whiteElo : analysis.blackElo
        let summary = white ? analysis.whiteSummary : analysis.blackSummary
        return HStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(white ? Color.white : Color.black)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.gray))
                .frame(width: 16, height: 16)
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
                        Button {
                            index = m.ply
                            showBetter = false
                        } label: {
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

    @ViewBuilder
    private var infoCard: some View {
        if let m = current {
            let mine = m.isWhite == userIsWhite
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(m.grade.symbol)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(m.grade.color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(m.numberLabel) \(m.san)  ·  \(mine ? "Your move" : "Opponent")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(m.headline).font(.headline)
                    }
                    Spacer()
                }
                Text(m.explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if m.grade.isBad {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showBetter.toggle() }
                        } label: {
                            Label(showBetter ? "Show my move" : "Show better move: \(m.bestSan)",
                                  systemImage: showBetter ? "arrow.uturn.backward" : "lightbulb")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(showBetter ? .gray : Grade.best.color)
                        Spacer()
                    }
                    if !showBetter, let reply = m.replyLine.first {
                        Text("Red arrow: the opponent's best answer, \(reply).")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if showBetter, m.bestLine.count > 1 {
                        Text("Best line: \(m.bestLine.prefix(5).joined(separator: " "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Game review").font(.headline)
                let mine = userIsWhite ? analysis.whiteSummary : analysis.blackSummary
                Text("You made \(mine.blunder) blunder\(mine.blunder == 1 ? "" : "s"), \(mine.mistake) mistake\(mine.mistake == 1 ? "" : "s") and \(mine.inaccuracy) inaccurac\(mine.inaccuracy == 1 ? "y" : "ies"). Tap → or swipe the board to step through, or jump to your next mistake.")
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            iconButton("backward.end.fill") { index = 0; showBetter = false }
            iconButton("chevron.left") { step(-1) }
            Button {
                if let next = myMistakeIndices.first(where: { $0 > index }) ?? myMistakeIndices.first {
                    index = next
                    showBetter = false
                }
            } label: {
                Label("Next mistake", systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(Grade.mistake.color)
            .disabled(myMistakeIndices.isEmpty)
            iconButton("chevron.right") { step(1) }
            iconButton("forward.end.fill") { index = analysis.moves.count; showBetter = false }
        }
        .padding(.bottom, 8)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.title3).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func step(_ d: Int) {
        index = min(max(index + d, 0), analysis.moves.count)
        showBetter = false
    }
}

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
                        accuracyBlock("Your", mine.accuracy)
                        Spacer()
                        accuracyBlock("Opponent's", theirs.accuracy)
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

    private func accuracyBlock(_ title: String, _ value: Double) -> some View {
        VStack {
            Text(String(format: "%.1f", value)).font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(title) accuracy").font(.caption).foregroundStyle(.secondary)
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
