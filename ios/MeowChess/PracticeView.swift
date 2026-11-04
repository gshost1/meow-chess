import SwiftUI

struct PracticeView: View {
    @EnvironmentObject var store: Store
    @State private var currentId: String?
    @State private var round = 0
    @State private var mode = PuzzleMode.all

    /// Each puzzle with its modes, computed once per render.
    private func classified() -> [(puzzle: Puzzle, modes: Set<PuzzleMode>)] {
        store.puzzles.map { ($0, PuzzleMode.classify($0.move)) }
    }
    private func list(_ available: [Puzzle]) -> [Puzzle] {
        let unsolved = available.filter { !store.solvedPuzzles.contains($0.id) || $0.id == currentId }
        return unsolved.isEmpty ? available : unsolved
    }

    var body: some View {
        let all = classified()
        let available = all.filter { $0.modes.contains(mode) }.map(\.puzzle)
        NavigationStack {
            VStack(spacing: 8) {
                if !all.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PuzzleMode.allCases) { item in
                                let inMode = all.filter { $0.modes.contains(item) }.map(\.puzzle)
                                let count = inMode.count
                                if count > 0 {
                                    Button {
                                        mode = item
                                        currentId = (inMode.first { !store.solvedPuzzles.contains($0.id) } ?? inMode.first)?.id
                                        round += 1
                                    } label: {
                                        Text("\(item.label) · \(count)")
                                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                                            .background(mode == item ? Color.accentColor : Color(white: 0.16), in: Capsule())
                                            .foregroundStyle(mode == item ? Color.black : Color.white)
                                    }
                                    .accessibilityIdentifier("puzzle-mode-\(item.rawValue)")
                                    .accessibilityAddTraits(mode == item ? .isSelected : [])
                                }
                            }
                        }.padding(.horizontal)
                    }
                    .accessibilityIdentifier("puzzle-modes")
                }
                let puzzles = list(available)
                if puzzles.isEmpty {
                    Spacer()
                    ChessPiece(piece: "N", mood: .happy).frame(width: 90, height: 90)
                    Text("No puzzles yet").font(.title3.bold())
                    Text("Review some games and Meowy turns your mistakes into puzzles, so you can find the moves you missed.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
                    Button("Review my last 10 games") { Task { await store.analyzeRecent(10) } }
                        .buttonStyle(.borderedProminent).disabled(!store.progress.isEmpty)
                    Spacer()
                } else {
                    let i = currentId.flatMap { id in puzzles.firstIndex { $0.id == id } } ?? 0
                    PuzzleBoard(puzzle: puzzles[i], number: i + 1, total: puzzles.count, round: round, mode: mode) {
                        // Always use the current filtered list after a solve.
                        let next = puzzles[(i + 1) % puzzles.count]
                        currentId = next.id
                        round += 1
                    }
                    // The board is not rebuilt per puzzle, so keep currentId pointing at what is shown.
                    .onChange(of: puzzles[i].id, initial: true) { _, id in if currentId != id { currentId = id } }
                }
            }
            .navigationTitle("Practice").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Solved \(store.solvedPuzzles.intersection(all.map(\.puzzle.id)).count)/\(all.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityIdentifier("solved-count")
                }
            }
            .onChange(of: available.isEmpty) { _, empty in if empty { mode = .all } }
        }
    }
}

struct PuzzleBoard: View {
    @EnvironmentObject var store: Store
    let puzzle: Puzzle
    let number: Int
    let total: Int
    let round: Int
    let mode: PuzzleMode
    let next: () -> Void

    enum Status { case solving, wrong, hint, solved, revealed }
    @State private var fen = ""
    @State private var legal: [LegalMove] = []
    @State private var selected: Square?
    @State private var status = Status.solving
    @State private var animation: BoardAnimation?
    @State private var animKey = 0
    @State private var lastMove: (Square, Square)?
    @State private var resultSquare: Square?
    @State private var reason = ""
    @State private var busy = false
    @State private var work: Task<Void, Never>?
    @State private var showLine = false
    @State private var lineStep = 1
    @State private var playing = false
    @State private var previousFen: String?
    @State private var displayedFlipped: Bool?
    @State private var previousFlipped = false
    @State private var previousOpacity = 0.0
    @State private var textOpacity = 1.0
    @State private var loadedSession: String?
    /// The move that solved it, when it was a different checkmate than the engine's.
    @State private var solvedSan: String?

    private var m: MoveReview { puzzle.move }
    private var completed: Bool { status == .solved || status == .revealed }
    private var line: [LineMove] { m.bestLineMoves ?? [] }
    private var session: String { "\(puzzle.id)-\(round)" }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Puzzle \(number) of \(total) · vs \(puzzle.opponent)").font(.caption).foregroundStyle(.secondary)
                    Text(prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("puzzle-prompt")
                    if UITesting.enabled {
                        Text(m.bestUci).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("puzzle-answer")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
                .padding(.horizontal).opacity(textOpacity)

                ZStack {
                    BoardView(fen: fen.isEmpty ? m.fenBefore : fen, flipped: displayedFlipped ?? !puzzle.userIsWhite,
                              highlights: highlights, moods: resultSquare.map { [$0: status == .wrong ? .sad : .happy] } ?? [:],
                              animation: animation, selected: selected,
                              feedback: resultSquare.map { ($0, status != .wrong) }, targets: targets, onTap: tap)
                    if let previousFen {
                        BoardView(fen: previousFen, flipped: previousFlipped)
                            .opacity(previousOpacity).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: boardSize(geo), height: boardSize(geo))
                .frame(maxWidth: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        feedback.accessibilityElement(children: .combine).accessibilityIdentifier("puzzle-feedback")
                        if completed && !line.isEmpty {
                            if !showLine {
                                Button("Show the line") { showLine = true; lineStep = 1 }
                                    .accessibilityIdentifier("puzzle-show-line")
                            } else {
                                lineControls
                            }
                        }
                        if completed, let text = m.bestText { Text(text).font(.callout) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }
                .opacity(textOpacity)
                HStack(spacing: 12) {
                    if completed {
                        Button("Next puzzle", action: next).buttonStyle(.borderedProminent)
                    } else {
                        Button("Hint") { status = .hint; SoundPlayer.shared.play(.inaccuracy) }
                            .buttonStyle(.bordered).disabled(status == .hint || busy)
                        Button("Show answer", action: reveal).buttonStyle(.bordered).disabled(busy)
                        Button("Skip", action: next).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 8)
            }
        }
        .task(id: session) {
            if loadedSession == session { resume() } else { await reset() }
        }
        .onDisappear { work?.cancel(); playing = false }
    }

    private func boardSize(_ geo: GeometryProxy) -> CGFloat {
        min(geo.size.width - 16, max(180, geo.size.height - 310))
    }
    private var prompt: String {
        let kind = mode == .all ? PuzzleMode.primary(m) : mode
        return "\(kind == .all ? "Practice" : kind.label) · You're \(puzzle.userIsWhite ? "White" : "Black"). \(kind.prompt)"
    }
    private var highlights: [Square] {
        if status == .hint, let best = uciSquares(m.bestUci) { return [best.0] }
        if let lastMove { return [lastMove.0, lastMove.1] }
        return []
    }
    private var targets: Set<Square> {
        guard let selected, !completed, !busy else { return [] }
        return Set(legal.filter { Square(Substring($0.from)) == selected }.compactMap { Square(Substring($0.to)) })
    }

    @ViewBuilder private var feedback: some View {
        if completed {
            VStack(alignment: .leading, spacing: 5) {
                Text(status == .solved ? "😺 Purrfect! \(solvedSan ?? m.bestSan) is the move." : "The answer was \(m.bestSan).")
                    .font(.headline).foregroundStyle(status == .solved ? Grade.best.color : .primary)
            }
        } else if status == .wrong {
            Text(reason).font(.callout).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.48))
        } else if status == .hint {
            Text("Hint: the highlighted piece is the one to move.").font(.callout)
        } else {
            Text("Tap one of your pieces, then tap where it should go.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var lineControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line.prefix(lineStep).map(\.san).joined(separator: "  "))
                .font(.callout.monospaced()).accessibilityIdentifier("puzzle-line-moves")
            HStack {
                Button { stopPlayback(); stepLine(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(lineStep == 0).accessibilityLabel("Line back")
                Spacer()
                Button(playing ? "Pause" : "Play line") { playing ? stopPlayback() : playLine() }
                Spacer()
                Text("\(lineStep)/\(line.count)").font(.caption.monospacedDigit())
                    .accessibilityIdentifier("puzzle-line-step")
                Button { stopPlayback(); stepLine(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(lineStep == line.count).accessibilityLabel("Line forward")
            }.buttonStyle(.bordered)
        }
    }

    /// Back on screen after a tab switch: keep the puzzle, but undo a demonstration that was cut off.
    private func resume() {
        previousFen = nil
        previousOpacity = 0
        textOpacity = 1
        guard busy else { return }
        animation = nil
        fen = m.fenBefore
        selected = nil
        status = .solving
        busy = false
        lastMove = nil
        resultSquare = nil
        reason = ""
    }

    @MainActor private func reset() async {
        loadedSession = session
        work?.cancel()
        playing = false
        if !fen.isEmpty {
            previousFen = fen
            previousFlipped = displayedFlipped ?? !puzzle.userIsWhite
            previousOpacity = 1
            textOpacity = 0
        }
        animation = nil
        fen = m.fenBefore
        displayedFlipped = !puzzle.userIsWhite
        legal = Engine.legalMoves(fen: fen)
        selected = nil
        status = .solving
        busy = false
        showLine = false
        lineStep = 1
        lastMove = nil
        resultSquare = nil
        solvedSan = nil
        reason = ""
        // Let the old board render over the new one before fading it out.
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        withAnimation(.easeOut(duration: 0.18)) { previousOpacity = 0; textOpacity = 1 }
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        previousFen = nil
    }

    private func tap(_ sq: Square) {
        guard !completed, !busy else { return }
        if selected == sq { selected = nil; return }
        if let from = selected, targets.contains(sq) {
            let candidates = legal.filter { Square(Substring($0.from)) == from && Square(Substring($0.to)) == sq }
            guard let move = candidates.first(where: { $0.uci == m.bestUci })
                    ?? candidates.first(where: { $0.uci.hasSuffix("q") }) ?? candidates.first else { return }
            selected = nil
            apply(LineMove(san: move.san, uci: move.uci, fen: move.fen))
            resultSquare = sq
            if move.uci == m.bestUci || move.san.hasSuffix("#") {
                status = .solved
                solvedSan = move.san
                store.markSolved(puzzle.id)
                SoundPlayer.shared.play(.correct)
            } else {
                demonstrate(move)
            }
        } else {
            let piece = parseBoard(fen)[sq.index]
            selected = piece.map { $0.isUppercase == puzzle.userIsWhite } == true ? sq : nil
        }
    }

    private func apply(_ move: LineMove, backwardsTo before: String? = nil) {
        animKey += 1
        animation = BoardAnimation.move(key: animKey, uci: move.uci, san: move.san,
                                        before: before ?? fen, backwards: before != nil)
        fen = before ?? move.fen
        lastMove = uciSquares(move.uci).map { before == nil ? $0 : ($0.1, $0.0) }
    }

    private func reveal() {
        selected = nil
        status = .revealed
        if let answer = legal.first(where: { $0.uci == m.bestUci }) {
            apply(LineMove(san: answer.san, uci: answer.uci, fen: answer.fen))
            resultSquare = uciSquares(answer.uci)?.1
        }
    }

    private func demonstrate(_ attempt: LegalMove) {
        busy = true
        status = .wrong
        reason = "Let's see how your opponent can reply…"
        SoundPlayer.shared.play(.wrong)
        let start = m.fenBefore
        work?.cancel()
        work = Task { @MainActor in
            do {
                let reply = try await Engine.bestMove(fen: attempt.fen)
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(650))
                if let reply {
                    reason = replyReason(reply, before: attempt.fen)
                    let attemptSquare = resultSquare
                    if uciSquares(reply.uci)?.1 == attemptSquare { resultSquare = nil }
                    apply(reply)
                    SoundPlayer.shared.play(SoundPlayer.meow(forSAN: reply.san))
                    try await Task.sleep(for: .milliseconds(1800))
                    apply(reply, backwardsTo: attempt.fen)
                    resultSquare = attemptSquare
                    try await Task.sleep(for: .milliseconds(350))
                } else {
                    reason = "This ends the line. Try \(m.bestSan) instead."
                    try await Task.sleep(for: .milliseconds(1200))
                }
            } catch {
                guard !Task.isCancelled else { return }
                reason = "Couldn't load a reply. You can try again."
                do { try await Task.sleep(for: .milliseconds(1000)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            apply(LineMove(san: attempt.san, uci: attempt.uci, fen: attempt.fen), backwardsTo: start)
            resultSquare = nil
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            lastMove = nil
            busy = false
            reason = "Try again. Look for checks, captures and threats."
        }
    }

    private func replyReason(_ reply: LineMove, before: String) -> String {
        if reply.san.hasSuffix("#") { return "Your opponent can play \(reply.san) — checkmate. Your king has no escape." }
        if reply.san.contains("x"), let (_, to) = uciSquares(reply.uci) {
            let board = parseBoard(before)
            let victim = board[to.index].map { pieceName($0).replacingOccurrences(of: "white ", with: "").replacingOccurrences(of: "black ", with: "") } ?? "pawn"
            return "Your opponent can play \(reply.san), taking your \(victim)."
        }
        if reply.san.hasSuffix("+") { return "Your opponent can play \(reply.san), putting your king in check." }
        return "Your opponent can reply \(reply.san). Compare this with the answer when you're ready."
    }

    private func stepLine(_ delta: Int) {
        let next = min(max(lineStep + delta, 0), line.count)
        guard next != lineStep else { return }
        if next > lineStep {
            apply(line[lineStep])
            SoundPlayer.shared.play(SoundPlayer.meow(forSAN: line[lineStep].san))
        } else {
            apply(line[next], backwardsTo: next == 0 ? m.fenBefore : line[next - 1].fen)
        }
        lineStep = next
        resultSquare = lineStep == 1 ? uciSquares(m.bestUci)?.1 : nil
    }
    private func stopPlayback() { work?.cancel(); playing = false }
    private func playLine() {
        work?.cancel()
        playing = true
        work = Task { @MainActor in
            if lineStep == line.count {
                while lineStep > 0 {
                    stepLine(-1)
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                }
            }
            while lineStep < line.count {
                stepLine(1)
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            }
            playing = false
        }
    }
}
