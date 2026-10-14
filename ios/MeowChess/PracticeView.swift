import SwiftUI

/// Puzzles made from the player's own mistakes: find the move you missed.
struct PracticeView: View {
    @EnvironmentObject var store: Store
    /// The puzzle on screen. It stays in the list after being solved so its feedback can be read.
    @State private var currentId: String?
    /// Bumped to restart the same puzzle when it is the only one left.
    @State private var round = 0
    @State private var onlyUnsolved = true

    private var list: [Puzzle] {
        let all = store.puzzles
        let unsolved = all.filter { !store.solvedPuzzles.contains($0.id) || $0.id == currentId }
        return onlyUnsolved && !unsolved.isEmpty ? unsolved : all
    }

    var body: some View {
        NavigationStack {
            let puzzles = list
            Group {
                if puzzles.isEmpty {
                    VStack(spacing: 14) {
                        CatPiece(piece: "N", mood: .happy).frame(width: 90, height: 90)
                        Text("No puzzles yet").font(.title3.bold())
                        Text("Review some games and Meowy turns your mistakes into puzzles, so you can find the moves you missed.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
                        Button("Review my last 10 games") { Task { await store.analyzeRecent(10) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!store.progress.isEmpty)
                    }
                } else {
                    let i = currentId.flatMap { id in puzzles.firstIndex { $0.id == id } } ?? 0
                    PuzzleBoard(puzzle: puzzles[i], number: i + 1, total: puzzles.count) {
                        let next = puzzles[(i + 1) % puzzles.count]
                        if next.id == puzzles[i].id { round += 1 }
                        currentId = next.id
                    }
                    .id("\(puzzles[i].id)-\(round)")
                    .onAppear { currentId = puzzles[i].id }
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Solved \(store.solvedPuzzles.intersection(store.puzzles.map(\.id)).count)/\(store.puzzles.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityIdentifier("solved-count")
                }
            }
        }
    }
}

struct PuzzleBoard: View {
    @EnvironmentObject var store: Store
    let puzzle: Puzzle
    let number: Int
    let total: Int
    let next: () -> Void

    enum Status { case solving, wrong, hint, solved, revealed }

    @State private var fen = ""
    @State private var legal: [LegalMove] = []
    @State private var selected: Square?
    @State private var status = Status.solving
    @State private var attempts = 0
    @State private var animation: BoardAnimation?
    @State private var moods: [Square: PieceMood] = [:]
    @State private var lastMove: (Square, Square)?

    private var m: MoveReview { puzzle.move }
    private var best: (Square, Square)? { uciSquares(m.bestUci) }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Puzzle \(number) of \(total) · vs \(puzzle.opponent)").font(.caption).foregroundStyle(.secondary)
                Text(prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("puzzle-prompt")
                if UITesting.enabled {
                    // Lets UI tests play the right move without knowing chess.
                    Text(m.bestUci).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("puzzle-answer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            BoardView(
                fen: fen.isEmpty ? m.fenBefore : fen,
                flipped: !puzzle.userIsWhite,
                highlights: highlights,
                arrows: status == .revealed ? best.map { [Arrow(from: $0.0, to: $0.1, color: Grade.best.color)] } ?? [] : [],
                moods: moods,
                animation: animation,
                selected: selected,
                targets: targets,
                onTap: tap
            )
            .padding(.horizontal, 8)

            feedback.padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("puzzle-feedback")
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if status == .solved || status == .revealed {
                    Button("Next puzzle") { next() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Hint") {
                        status = .hint
                        SoundPlayer.shared.play(.inaccuracy)
                    }
                    .buttonStyle(.bordered)
                    .disabled(status == .hint)
                    Button("Show answer") {
                        status = .revealed
                        selected = nil
                    }
                    .buttonStyle(.bordered)
                    Button("Skip") { next() }.foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
        .onAppear {
            fen = m.fenBefore
            legal = Engine.legalMoves(fen: m.fenBefore)
        }
    }

    private var prompt: String {
        let side = puzzle.userIsWhite ? "White" : "Black"
        return "You're \(side). In your game you played \(m.san) here (\(m.grade.label.lowercased())). Find a better move."
    }

    private var highlights: [Square] {
        if let lastMove { return [lastMove.0, lastMove.1] }
        if status == .hint, let best { return [best.0] }
        return []
    }

    private var targets: Set<Square> {
        guard let selected, status != .solved, status != .revealed else { return [] }
        return Set(legal.filter { Square(Substring($0.from)) == selected }.compactMap { Square(Substring($0.to)) })
    }

    @ViewBuilder
    private var feedback: some View {
        switch status {
        case .solving:
            Text("Tap one of your pieces, then tap where it should go.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        case .wrong:
            Label("Not that one. Try again! (\(attempts) tr\(attempts == 1 ? "y" : "ies"))", systemImage: "arrow.counterclockwise")
                .font(.callout.bold()).foregroundStyle(Grade.mistake.color).frame(maxWidth: .infinity, alignment: .leading)
        case .hint:
            Text("Hint: the highlighted piece is the one to move.")
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
        case .solved, .revealed:
            VStack(alignment: .leading, spacing: 6) {
                Text(status == .solved ? "😺 Purrfect! \(m.bestSan) is the move." : "The answer was \(m.bestSan).")
                    .font(.headline).foregroundStyle(status == .solved ? Grade.best.color : .primary)
                if let text = m.bestText { Text(text).font(.callout) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
        }
    }

    private func isOwnPiece(_ sq: Square) -> Bool {
        guard let p = parseBoard(fen)[sq.index] else { return false }
        return p.isUppercase == puzzle.userIsWhite
    }

    private func tap(_ sq: Square) {
        guard status != .solved, status != .revealed else { return }
        if let from = selected, targets.contains(sq) {
            let candidates = legal.filter { Square(Substring($0.from)) == from && Square(Substring($0.to)) == sq }
            guard let move = candidates.first(where: { $0.uci.hasSuffix("q") }) ?? candidates.first else { return }
            selected = nil
            if move.uci == m.bestUci {
                animation = BoardAnimation(key: Int.random(in: 1...1_000_000), slides: [Slide(from: from, to: sq)],
                                           poof: parseBoard(fen)[sq.index].map { Poof(piece: $0, square: sq) })
                fen = move.fen
                lastMove = (from, sq)
                moods = [sq: .happy]
                status = .solved
                store.markSolved(puzzle.id)
                SoundPlayer.shared.play(.correct)
            } else {
                attempts += 1
                status = .wrong
                moods = [from: .sad]
                SoundPlayer.shared.play(.wrong)
            }
            return
        }
        if isOwnPiece(sq) {
            selected = sq
            moods = [:]
            SoundPlayer.shared.play(.move)
        } else {
            selected = nil
        }
    }
}
