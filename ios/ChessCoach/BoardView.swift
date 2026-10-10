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

struct BoardView: View {
    let fen: String
    var flipped = false
    var highlights: [Square] = []
    var arrows: [Arrow] = []
    var badge: (Square, Grade)? = nil

    private static let glyphs: [Character: String] = [
        "k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟",
    ]
    private static let outlines: [Character: String] = [
        "k": "♔", "q": "♕", "r": "♖", "b": "♗", "n": "♘", "p": "♙",
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8
            let board = parseBoard(fen)
            ZStack(alignment: .topLeading) {
                ForEach(0..<64, id: \.self) { i in
                    let sq = Square(i)
                    let pos = position(sq, cell)
                    ZStack {
                        Rectangle().fill((sq.file + sq.rank) % 2 == 0 ? BoardTheme.dark : BoardTheme.light)
                        if highlights.contains(sq) {
                            Rectangle().fill(BoardTheme.highlight)
                        }
                        coordinates(sq, cell)
                        if let p = board[i] {
                            piece(p, cell)
                        }
                    }
                    .frame(width: cell, height: cell)
                    .position(x: pos.x, y: pos.y)
                }
                ForEach(arrows, id: \.self) { a in
                    ArrowShape(from: position(a.from, cell), to: position(a.to, cell), width: cell * 0.18)
                        .fill(a.color.opacity(0.8))
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
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func position(_ sq: Square, _ cell: CGFloat) -> CGPoint {
        let col = flipped ? 7 - sq.file : sq.file
        let row = flipped ? sq.rank : 7 - sq.rank
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    @ViewBuilder
    private func piece(_ p: Character, _ cell: CGFloat) -> some View {
        let lower = Character(p.lowercased())
        // U+FE0E forces text (not emoji) presentation of the chess glyphs.
        let solid = (Self.glyphs[lower] ?? "") + "\u{FE0E}"
        let outline = (Self.outlines[lower] ?? "") + "\u{FE0E}"
        let font = Font.system(size: cell * 0.82)
        if p.isUppercase {
            ZStack {
                Text(solid).font(font).foregroundStyle(.white)
                Text(outline).font(font).foregroundStyle(.black)
            }
            .shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
        } else {
            Text(solid).font(font).foregroundStyle(Color(white: 0.12))
                .shadow(color: .white.opacity(0.3), radius: 0.5)
        }
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
