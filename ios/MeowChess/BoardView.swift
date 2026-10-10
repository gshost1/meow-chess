import SwiftUI

/// Square index 0 = a1 ... 63 = h8, matching the Rust engine.
struct Square: Hashable {
    let index: Int
    var file: Int { index % 8 }
    var rank: Int { index / 8 }

    init(_ index: Int) { self.index = index }

    init?(_ name: Substring) {
        let chars = Array(name.utf8)
        guard chars.count == 2 else { return nil }
        let f = Int(chars[0]) - 97
        let r = Int(chars[1]) - 49
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        index = r * 8 + f
    }
}

struct Arrow: Hashable {
    let from: Square
    let to: Square
    let color: Color
}

/// Parses the piece-placement part of a FEN into 64 optional piece letters.
func parseBoard(_ fen: String) -> [Character?] {
    var squares = [Character?](repeating: nil, count: 64)
    let placement = fen.split(separator: " ").first ?? ""
    var rank = 7, file = 0
    for c in placement {
        if c == "/" {
            rank -= 1; file = 0
        } else if let n = c.wholeNumberValue {
            file += n
        } else if rank >= 0, file < 8 {
            squares[rank * 8 + file] = c
            file += 1
        }
    }
    return squares
}

/// Squares from a UCI move string like "e2e4".
func uciSquares(_ uci: String?) -> (Square, Square)? {
    guard let uci, uci.count >= 4 else { return nil }
    let s = Substring(uci)
    guard let a = Square(s.prefix(2)), let b = Square(s.dropFirst(2).prefix(2)) else { return nil }
    return (a, b)
}

enum BoardTheme {
    static let light = Color(red: 0.93, green: 0.93, blue: 0.82)
    static let dark = Color(red: 0.46, green: 0.59, blue: 0.34)
    static let highlight = Color(red: 0.97, green: 0.85, blue: 0.25).opacity(0.55)
}

extension Grade {
    var color: Color {
        switch self {
        case .forced, .best: return Color(red: 0.36, green: 0.69, blue: 0.29)
        case .excellent: return Color(red: 0.45, green: 0.75, blue: 0.45)
        case .good: return Color(red: 0.55, green: 0.65, blue: 0.55)
        case .inaccuracy: return Color(red: 0.95, green: 0.75, blue: 0.20)
        case .mistake: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .blunder: return Color(red: 0.86, green: 0.24, blue: 0.22)
        }
    }
}

/// A piece that should fly in from another square (the piece is already on `to` in the FEN).
struct Slide: Hashable {
    let from: Square
    let to: Square
}

/// What to animate when the board appears: sliding pieces and a captured piece going "poof".
struct BoardAnimation: Equatable {
    var key: Int
    var slides: [Slide] = []
    var poof: Poof? = nil
}

struct Poof: Hashable {
    let piece: Character
    let square: Square
}

struct BoardView: View {
    let fen: String
    var flipped = false
    var highlights: [Square] = []
    var arrows: [Arrow] = []
    var badge: (Square, Grade)? = nil
    var moods: [Square: PieceMood] = [:]
    var animation: BoardAnimation? = nil
    var selected: Square? = nil
    var targets: Set<Square> = []
    var onTap: ((Square) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8
            let board = parseBoard(fen)
            ZStack(alignment: .topLeading) {
                ForEach(0..<64, id: \.self) { i in
                    squareView(Square(i), cell, occupied: board[i] != nil)
                }
                ForEach(0..<64, id: \.self) { i in
                    if let p = board[i] {
                        pieceView(p, Square(i), cell)
                    }
                }
                .allowsHitTesting(false)
                if let poof = animation?.poof {
                    PoofView(piece: poof.piece, cell: cell)
                        .id("poof-\(animation?.key ?? 0)")
                        .position(position(poof.square, cell))
                        .allowsHitTesting(false)
                }
                ForEach(arrows, id: \.self) { a in
                    ArrowShape(from: position(a.from, cell), to: position(a.to, cell), width: cell * 0.18)
                        .fill(a.color.opacity(0.8))
                        .allowsHitTesting(false)
                }
                if let (sq, grade) = badge {
                    let p = position(sq, cell)
                    Text(grade.symbol)
                        .font(.system(size: cell * 0.26, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: cell * 0.42, height: cell * 0.42)
                        .background(Circle().fill(grade.color))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(radius: 1)
                        .position(x: p.x + cell * 0.38, y: p.y - cell * 0.38)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func squareView(_ sq: Square, _ cell: CGFloat, occupied: Bool) -> some View {
        ZStack {
            Rectangle().fill((sq.file + sq.rank) % 2 == 0 ? BoardTheme.dark : BoardTheme.light)
            if highlights.contains(sq) {
                Rectangle().fill(BoardTheme.highlight)
            }
            if selected == sq {
                Rectangle().fill(Color.accentColor.opacity(0.45))
            }
            coordinates(sq, cell)
            if targets.contains(sq) {
                if occupied {
                    Circle().stroke(Color.black.opacity(0.28), lineWidth: cell * 0.08).padding(cell * 0.06)
                } else {
                    Circle().fill(Color.black.opacity(0.22)).frame(width: cell * 0.3, height: cell * 0.3)
                }
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(sq) }
        .position(position(sq, cell))
    }

    @ViewBuilder
    private func pieceView(_ p: Character, _ sq: Square, _ cell: CGFloat) -> some View {
        let mood = moods[sq] ?? .normal
        if let anim = animation, let slide = anim.slides.first(where: { $0.to == sq }) {
            let from = position(slide.from, cell)
            let to = position(sq, cell)
            SlidingPiece(piece: p, mood: mood, cell: cell, dx: from.x - to.x, dy: from.y - to.y)
                .id("slide-\(anim.key)-\(sq.index)")
                .position(to)
        } else {
            CatPiece(piece: p, mood: mood)
                .frame(width: cell, height: cell)
                .position(position(sq, cell))
        }
    }

    private func position(_ sq: Square, _ cell: CGFloat) -> CGPoint {
        let col = flipped ? 7 - sq.file : sq.file
        let row = flipped ? sq.rank : 7 - sq.rank
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    @ViewBuilder
    private func coordinates(_ sq: Square, _ cell: CGFloat) -> some View {
        let textColor = (sq.file + sq.rank) % 2 == 0 ? BoardTheme.light : BoardTheme.dark
        let showRank = flipped ? sq.file == 7 : sq.file == 0
        let showFile = flipped ? sq.rank == 7 : sq.rank == 0
        ZStack {
            if showRank {
                Text("\(sq.rank + 1)")
                    .font(.system(size: cell * 0.2, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }
            if showFile {
                Text(String(UnicodeScalar(UInt8(97 + sq.file))))
                    .font(.system(size: cell * 0.2, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }
        }
    }
}

/// Moves a piece from an offset back to its square with a little hop.
struct HopEffect: GeometryEffect {
    var t: CGFloat
    let dx: CGFloat
    let dy: CGFloat
    let lift: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let k = min(max(t, 0), 1)
        let hop = sin(.pi * k)
        let s = 1 + 0.18 * hop
        var tr = CGAffineTransform(translationX: dx * (1 - k), y: dy * (1 - k) - lift * hop)
        tr = tr.translatedBy(x: size.width / 2, y: size.height / 2)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(tr)
    }
}

struct SlidingPiece: View {
    let piece: Character
    let mood: PieceMood
    let cell: CGFloat
    let dx: CGFloat
    let dy: CGFloat
    @State private var t: CGFloat = 0

    var body: some View {
        CatPiece(piece: piece, mood: mood)
            .frame(width: cell, height: cell)
            .modifier(HopEffect(t: t, dx: dx, dy: dy, lift: cell * 0.35))
            .zIndex(1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.36)) { t = 1 }
            }
    }
}

/// A captured piece puffs away in a little cloud of sparkles.
struct PoofView: View {
    let piece: Character
    let cell: CGFloat
    @State private var p: CGFloat = 0

    var body: some View {
        ZStack {
            CatPiece(piece: piece, mood: .dizzy)
                .frame(width: cell, height: cell)
                .scaleEffect(1 + 0.4 * p)
                .opacity(Double(1 - p))
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6 * 2 * .pi
                Text("✦")
                    .font(.system(size: cell * 0.22))
                    .foregroundStyle(i.isMultiple(of: 2) ? Color.yellow : Color.white)
                    .offset(x: cos(angle) * cell * 0.55 * p, y: sin(angle) * cell * 0.55 * p)
                    .opacity(Double(p < 0.15 ? p / 0.15 : 1 - p))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.22)) { p = 1 }
        }
    }
}

struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux
        let head = width * 2.2
        let start = CGPoint(x: from.x + ux * width * 1.2, y: from.y + uy * width * 1.2)
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        let w = width / 2
        var p = Path()
        p.move(to: CGPoint(x: start.x + px * w, y: start.y + py * w))
        p.addLine(to: CGPoint(x: base.x + px * w, y: base.y + py * w))
        p.addLine(to: CGPoint(x: base.x + px * head * 0.6, y: base.y + py * head * 0.6))
        p.addLine(to: to)
        p.addLine(to: CGPoint(x: base.x - px * head * 0.6, y: base.y - py * head * 0.6))
        p.addLine(to: CGPoint(x: base.x - px * w, y: base.y - py * w))
        p.addLine(to: CGPoint(x: start.x - px * w, y: start.y - py * w))
        p.closeSubpath()
        return p
    }
}

struct EvalBar: View {
    let eval: Eval
    var flipped = false

    var body: some View {
        GeometryReader { geo in
            // Map pawns to a 0...1 share for White using a soft curve.
            let share = 0.5 + 0.5 * tanh(eval.whitePawns / 4)
            let whiteHeight = geo.size.height * share
            ZStack(alignment: flipped ? .top : .bottom) {
                Rectangle().fill(Color(white: 0.2))
                Rectangle().fill(Color(white: 0.95)).frame(height: whiteHeight)
                Text(eval.text)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(share >= 0.5 ? Color.black : Color.white)
                    .padding(.vertical, 3)
                    .frame(maxHeight: .infinity, alignment: (share >= 0.5) != flipped ? .bottom : .top)
            }
            .animation(.easeInOut(duration: 0.25), value: share)
        }
        .frame(width: 22)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
