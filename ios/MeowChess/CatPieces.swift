import SwiftUI

enum PieceMood {
    case normal, happy, sad, worried, shocked, dizzy
}

/// A chess piece drawn as a cat. The hat tells you which piece it is:
/// pawn = kitten, knight = plumed helmet, bishop = mitre, rook = castle tower, queen = tiara, king = crown.
struct CatPiece: View {
    /// FEN letter: uppercase = White, lowercase = Black.
    let piece: Character
    var mood: PieceMood = .normal

    var body: some View {
        Canvas { ctx, size in
            CatPainter(size: size, piece: piece, mood: mood).draw(&ctx)
        }
        .accessibilityLabel(Text(CatPainter.name(piece)))
    }
}

private struct Palette {
    let fur, furShade, outline, innerEar, eye, iris, nose, line, whisker, blush: Color

    static let white = Palette(
        fur: Color(red: 1.0, green: 0.965, blue: 0.9),
        furShade: Color(red: 0.95, green: 0.89, blue: 0.79),
        outline: Color(red: 0.47, green: 0.33, blue: 0.22),
        innerEar: Color(red: 0.97, green: 0.66, blue: 0.72),
        eye: Color(red: 0.17, green: 0.15, blue: 0.2),
        iris: Color(red: 0.17, green: 0.15, blue: 0.2),
        nose: Color(red: 0.95, green: 0.56, blue: 0.65),
        line: Color(red: 0.42, green: 0.29, blue: 0.18),
        whisker: Color(red: 0.55, green: 0.42, blue: 0.3),
        blush: Color(red: 1.0, green: 0.6, blue: 0.65)
    )
    static let black = Palette(
        fur: Color(red: 0.3, green: 0.3, blue: 0.36),
        furShade: Color(red: 0.22, green: 0.22, blue: 0.27),
        outline: Color(red: 0.08, green: 0.08, blue: 0.1),
        innerEar: Color(red: 0.85, green: 0.5, blue: 0.6),
        eye: Color(red: 0.05, green: 0.05, blue: 0.06),
        iris: Color(red: 0.8, green: 0.9, blue: 0.3),
        nose: Color(red: 0.9, green: 0.55, blue: 0.65),
        line: Color(red: 0.08, green: 0.08, blue: 0.1),
        whisker: Color(white: 0.78),
        blush: Color(red: 1.0, green: 0.55, blue: 0.65)
    )
}

private let gold = Color(red: 0.98, green: 0.78, blue: 0.26)
private let goldDark = Color(red: 0.72, green: 0.52, blue: 0.08)

struct CatPainter {
    let size: CGSize
    let piece: Character
    let mood: PieceMood

    static func name(_ p: Character) -> String {
        let color = p.isUppercase ? "White" : "Black"
        let kind: String
        switch p.lowercased() {
        case "k": kind = "king"
        case "q": kind = "queen"
        case "r": kind = "rook"
        case "b": kind = "bishop"
        case "n": kind = "knight"
        default: kind = "pawn"
        }
        return "\(color) \(kind) cat"
    }

    private var kind: Character { Character(piece.lowercased()) }
    private var isWhite: Bool { piece.isUppercase }
    private var pal: Palette { isWhite ? .white : .black }
    private var w: CGFloat { size.width }
    private var lw: CGFloat { w * 0.024 }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * w) }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
        CGRect(x: x * w, y: y * w, width: rw * w, height: rh * w)
    }
    private func ellipse(cx: CGFloat, cy: CGFloat, rw: CGFloat, rh: CGFloat) -> Path {
        Path(ellipseIn: rect(cx - rw / 2, cy - rh / 2, rw, rh))
    }
    private func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.move(to: p(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { path.addLine(to: p(q.0, q.1)) }
        path.closeSubpath()
        return path
    }

    func draw(_ ctx: inout GraphicsContext) {
        var c = ctx
        if kind == "p" {
            // Kittens are smaller; shrink around the bottom center.
            c.translateBy(x: w * 0.5, y: w * 0.97)
            c.scaleBy(x: 0.84, y: 0.84)
            c.translateBy(x: -w * 0.5, y: -w * 0.97)
        }
        // Soft shadow.
        c.fill(ellipse(cx: 0.5, cy: 0.93, rw: 0.58, rh: 0.08), with: .color(.black.opacity(0.22)))

        drawBody(&c)
        if kind == "n" { drawHelmet(&c) }
        drawEars(&c)
        drawHead(&c)
        drawFace(&c)
        switch kind {
        case "k": drawCrown(&c)
        case "q": drawTiara(&c)
        case "r": drawTower(&c)
        case "b": drawMitre(&c)
        case "n": drawPlume(&c)
        default: drawTuft(&c)
        }
    }

    // MARK: Body

    private func drawBody(_ c: inout GraphicsContext) {
        let base = ellipse(cx: 0.5, cy: 0.81, rw: 0.62, rh: 0.25)
        c.fill(base, with: .color(pal.furShade))
        c.stroke(base, with: .color(pal.outline), lineWidth: lw)
        for x in [0.38, 0.62] as [CGFloat] {
            let paw = ellipse(cx: x, cy: 0.89, rw: 0.15, rh: 0.09)
            c.fill(paw, with: .color(pal.fur))
            c.stroke(paw, with: .color(pal.outline), lineWidth: lw * 0.8)
        }
    }

    private func drawEars(_ c: inout GraphicsContext) {
        let left = poly([(0.2, 0.44), (0.25, 0.17), (0.43, 0.33)])
        let right = poly([(0.8, 0.44), (0.75, 0.17), (0.57, 0.33)])
        for ear in [left, right] {
            c.fill(ear, with: .color(pal.fur))
            c.stroke(ear, with: .color(pal.outline), style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        }
        c.fill(poly([(0.245, 0.39), (0.27, 0.24), (0.37, 0.335)]), with: .color(pal.innerEar))
        c.fill(poly([(0.755, 0.39), (0.73, 0.24), (0.63, 0.335)]), with: .color(pal.innerEar))
    }

    private func headPath() -> Path { ellipse(cx: 0.5, cy: 0.56, rw: 0.64, rh: 0.52) }

    private func drawHead(_ c: inout GraphicsContext) {
        let head = headPath()
        c.fill(head, with: .color(pal.fur))
        if isWhite {
            // A calico patch, clipped to the head.
            var patch = c
            patch.clip(to: head)
            patch.fill(ellipse(cx: 0.3, cy: 0.38, rw: 0.3, rh: 0.26), with: .color(Color(red: 0.96, green: 0.7, blue: 0.4)))
        } else {
            var stripes = c
            stripes.clip(to: head)
            for dx in [-0.06, 0.0, 0.06] as [CGFloat] {
                var s = Path()
                s.move(to: p(0.5 + dx, 0.31))
                s.addLine(to: p(0.5 + dx * 1.2, 0.39))
                stripes.stroke(s, with: .color(pal.furShade), style: StrokeStyle(lineWidth: lw * 1.3, lineCap: .round))
            }
        }
        c.stroke(head, with: .color(pal.outline), lineWidth: lw)
    }

    // MARK: Face

    private func drawFace(_ c: inout GraphicsContext) {
        // Blush and whiskers.
        for x in [0.3, 0.7] as [CGFloat] {
            c.fill(ellipse(cx: x, cy: 0.655, rw: 0.1, rh: 0.055), with: .color(pal.blush.opacity(mood == .sad ? 0.25 : 0.5)))
        }
        for (a, b) in [((0.3, 0.64), (0.13, 0.6)), ((0.3, 0.67), (0.12, 0.69)),
                       ((0.7, 0.64), (0.87, 0.6)), ((0.7, 0.67), (0.88, 0.69))] {
            var wh = Path()
            wh.move(to: p(a.0, a.1))
            wh.addLine(to: p(b.0, b.1))
            c.stroke(wh, with: .color(pal.whisker), style: StrokeStyle(lineWidth: lw * 0.5, lineCap: .round))
        }

        for (i, x) in ([0.385, 0.615] as [CGFloat]).enumerated() {
            drawEye(&c, x: x, y: 0.565, left: i == 0)
        }
        if kind == "q" && (mood == .normal || mood == .happy) {
            // Eyelashes for the queen.
            for (x, dir) in [(0.345, -1.0), (0.655, 1.0)] as [(CGFloat, CGFloat)] {
                var l = Path()
                l.move(to: p(x, 0.53))
                l.addLine(to: p(x + dir * 0.035, 0.505))
                c.stroke(l, with: .color(pal.line), style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
            }
        }

        c.fill(poly([(0.47, 0.625), (0.53, 0.625), (0.5, 0.655)]), with: .color(pal.nose))
        drawMouth(&c)

        if mood == .worried {
            // Sweat drop.
            var d = Path()
            d.move(to: p(0.79, 0.4))
            d.addQuadCurve(to: p(0.79, 0.49), control: p(0.73, 0.47))
            d.addQuadCurve(to: p(0.79, 0.4), control: p(0.85, 0.47))
            c.fill(d, with: .color(Color(red: 0.55, green: 0.8, blue: 1.0)))
        }
    }

    private func drawEye(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, left: Bool) {
        let stroke = StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round)
        switch mood {
        case .happy:
            var arc = Path()
            arc.move(to: p(x - 0.045, y + 0.01))
            arc.addQuadCurve(to: p(x + 0.045, y + 0.01), control: p(x, y - 0.06))
            c.stroke(arc, with: .color(pal.line), style: stroke)
        case .dizzy:
            for (a, b) in [((-0.035, -0.035), (0.035, 0.035)), ((-0.035, 0.035), (0.035, -0.035))] {
                var l = Path()
                l.move(to: p(x + a.0, y + a.1))
                l.addLine(to: p(x + b.0, y + b.1))
                c.stroke(l, with: .color(pal.line), style: stroke)
            }
        case .shocked:
            let white = ellipse(cx: x, cy: y, rw: 0.11, rh: 0.12)
            c.fill(white, with: .color(.white))
            c.stroke(white, with: .color(pal.line), lineWidth: lw * 0.8)
            c.fill(ellipse(cx: x, cy: y, rw: 0.035, rh: 0.035), with: .color(pal.eye))
        default:
            if isWhite {
                c.fill(ellipse(cx: x, cy: y, rw: 0.085, rh: 0.11), with: .color(pal.eye))
            } else {
                c.fill(ellipse(cx: x, cy: y, rw: 0.095, rh: 0.115), with: .color(pal.iris))
                c.fill(ellipse(cx: x, cy: y, rw: 0.035, rh: 0.095), with: .color(pal.eye))
            }
            c.fill(ellipse(cx: x + 0.015, cy: y - 0.025, rw: 0.032, rh: 0.032), with: .color(.white))
            if mood == .sad {
                // Droopy eyelid.
                var lid = Path()
                lid.addRect(rect(x - 0.06, y - 0.075, 0.12, 0.065))
                c.fill(lid, with: .color(pal.fur))
                var edge = Path()
                edge.move(to: p(x - 0.05, y - (left ? 0.0 : 0.025)))
                edge.addLine(to: p(x + 0.05, y - (left ? 0.025 : 0.0)))
                c.stroke(edge, with: .color(pal.line), style: stroke)
                if left {
                    var tear = Path()
                    tear.move(to: p(x - 0.03, y + 0.05))
                    tear.addQuadCurve(to: p(x - 0.03, y + 0.12), control: p(x - 0.075, y + 0.11))
                    tear.addQuadCurve(to: p(x - 0.03, y + 0.05), control: p(x + 0.015, y + 0.11))
                    c.fill(tear, with: .color(Color(red: 0.5, green: 0.78, blue: 1.0)))
                }
            }
            if mood == .worried {
                var brow = Path()
                brow.move(to: p(x + (left ? -0.05 : 0.05), y - 0.075))
                brow.addLine(to: p(x + (left ? 0.035 : -0.035), y - 0.1))
                c.stroke(brow, with: .color(pal.line), style: stroke)
            }
        }
    }

    private func drawMouth(_ c: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round)
        var m = Path()
        switch mood {
        case .happy:
            m.move(to: p(0.45, 0.67))
            m.addQuadCurve(to: p(0.55, 0.67), control: p(0.5, 0.76))
            m.closeSubpath()
            c.fill(m, with: .color(Color(red: 0.55, green: 0.15, blue: 0.2)))
            c.fill(ellipse(cx: 0.5, cy: 0.705, rw: 0.04, rh: 0.025), with: .color(Color(red: 1.0, green: 0.55, blue: 0.6)))
            c.stroke(m, with: .color(pal.line), style: stroke)
            return
        case .shocked:
            let o = ellipse(cx: 0.5, cy: 0.715, rw: 0.05, rh: 0.065)
            c.fill(o, with: .color(Color(red: 0.4, green: 0.1, blue: 0.15)))
            c.stroke(o, with: .color(pal.line), lineWidth: lw * 0.7)
            return
        case .sad:
            m.move(to: p(0.46, 0.715))
            m.addQuadCurve(to: p(0.54, 0.715), control: p(0.5, 0.67))
        case .dizzy:
            m.move(to: p(0.44, 0.7))
            m.addQuadCurve(to: p(0.48, 0.7), control: p(0.46, 0.675))
            m.addQuadCurve(to: p(0.52, 0.7), control: p(0.5, 0.725))
            m.addQuadCurve(to: p(0.56, 0.7), control: p(0.54, 0.675))
        case .worried:
            m.move(to: p(0.465, 0.7))
            m.addQuadCurve(to: p(0.5, 0.695), control: p(0.48, 0.685))
            m.addQuadCurve(to: p(0.535, 0.7), control: p(0.52, 0.71))
        case .normal:
            m.move(to: p(0.45, 0.67))
            m.addQuadCurve(to: p(0.5, 0.67), control: p(0.475, 0.705))
            m.addQuadCurve(to: p(0.55, 0.67), control: p(0.525, 0.705))
        }
        c.stroke(m, with: .color(pal.line), style: stroke)
    }

    // MARK: Hats

    private func drawCrown(_ c: inout GraphicsContext) {
        let crown = poly([(0.33, 0.33), (0.33, 0.15), (0.415, 0.235), (0.5, 0.11), (0.585, 0.235), (0.67, 0.15), (0.67, 0.33)])
        c.fill(crown, with: .color(gold))
        c.stroke(crown, with: .color(goldDark), style: StrokeStyle(lineWidth: lw * 0.9, lineJoin: .round))
        var band = Path()
        band.addRect(rect(0.33, 0.28, 0.34, 0.05))
        c.fill(band, with: .color(goldDark.opacity(0.5)))
        c.fill(ellipse(cx: 0.5, cy: 0.27, rw: 0.055, rh: 0.055), with: .color(Color(red: 0.9, green: 0.15, blue: 0.25)))
        for x in [0.4, 0.6] as [CGFloat] {
            c.fill(ellipse(cx: x, cy: 0.29, rw: 0.035, rh: 0.035), with: .color(Color(red: 0.25, green: 0.55, blue: 0.95)))
        }
        var cross = Path()
        cross.addRect(rect(0.485, 0.025, 0.03, 0.095))
        cross.addRect(rect(0.455, 0.05, 0.09, 0.028))
        c.fill(cross, with: .color(gold))
        c.stroke(cross, with: .color(goldDark), lineWidth: lw * 0.6)
    }

    private func drawTiara(_ c: inout GraphicsContext) {
        let tiara = poly([(0.35, 0.33), (0.37, 0.19), (0.435, 0.26), (0.5, 0.13), (0.565, 0.26), (0.63, 0.19), (0.65, 0.33)])
        c.fill(tiara, with: .color(gold))
        c.stroke(tiara, with: .color(goldDark), style: StrokeStyle(lineWidth: lw * 0.9, lineJoin: .round))
        for (x, y) in [(0.37, 0.19), (0.5, 0.13), (0.63, 0.19)] as [(CGFloat, CGFloat)] {
            let pearl = ellipse(cx: x, cy: y, rw: 0.05, rh: 0.05)
            c.fill(pearl, with: .color(Color(red: 1.0, green: 0.92, blue: 0.96)))
            c.stroke(pearl, with: .color(goldDark), lineWidth: lw * 0.5)
        }
        c.fill(ellipse(cx: 0.5, cy: 0.285, rw: 0.06, rh: 0.05), with: .color(Color(red: 1.0, green: 0.4, blue: 0.7)))
    }

    private func drawTower(_ c: inout GraphicsContext) {
        let stone = Color(red: 0.68, green: 0.68, blue: 0.75)
        let stoneDark = Color(red: 0.4, green: 0.4, blue: 0.48)
        var tower = Path()
        tower.addRect(rect(0.35, 0.15, 0.3, 0.18))
        for x in [0.35, 0.4625, 0.575] as [CGFloat] {
            tower.addRect(rect(x, 0.08, 0.075, 0.075))
        }
        c.fill(tower, with: .color(stone))
        c.stroke(tower, with: .color(stoneDark), style: StrokeStyle(lineWidth: lw * 0.8, lineJoin: .round))
        var bricks = Path()
        bricks.move(to: p(0.35, 0.21)); bricks.addLine(to: p(0.65, 0.21))
        bricks.move(to: p(0.35, 0.27)); bricks.addLine(to: p(0.65, 0.27))
        bricks.move(to: p(0.42, 0.15)); bricks.addLine(to: p(0.42, 0.21))
        bricks.move(to: p(0.58, 0.21)); bricks.addLine(to: p(0.58, 0.27))
        c.stroke(bricks, with: .color(stoneDark.opacity(0.6)), lineWidth: lw * 0.5)
        var door = Path()
        door.move(to: p(0.475, 0.33))
        door.addLine(to: p(0.475, 0.255))
        door.addQuadCurve(to: p(0.525, 0.255), control: p(0.5, 0.225))
        door.addLine(to: p(0.525, 0.33))
        c.fill(door, with: .color(stoneDark))
    }

    private func drawMitre(_ c: inout GraphicsContext) {
        let lilac = Color(red: 0.66, green: 0.55, blue: 0.9)
        var hat = Path()
        hat.move(to: p(0.37, 0.33))
        hat.addQuadCurve(to: p(0.5, 0.05), control: p(0.35, 0.12))
        hat.addQuadCurve(to: p(0.63, 0.33), control: p(0.65, 0.12))
        hat.closeSubpath()
        c.fill(hat, with: .color(lilac))
        c.stroke(hat, with: .color(Color(red: 0.36, green: 0.27, blue: 0.6)), style: StrokeStyle(lineWidth: lw * 0.9, lineJoin: .round))
        var slit = Path()
        slit.move(to: p(0.545, 0.13))
        slit.addLine(to: p(0.465, 0.25))
        c.stroke(slit, with: .color(Color(red: 0.3, green: 0.22, blue: 0.5)), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        var band = Path()
        band.addRect(rect(0.37, 0.295, 0.26, 0.04))
        c.fill(band, with: .color(gold))
        c.fill(ellipse(cx: 0.5, cy: 0.05, rw: 0.05, rh: 0.05), with: .color(gold))
    }

    private func drawHelmet(_ c: inout GraphicsContext) {
        let steel = Color(red: 0.75, green: 0.79, blue: 0.84)
        var dome = Path()
        dome.move(to: p(0.27, 0.42))
        dome.addQuadCurve(to: p(0.73, 0.42), control: p(0.5, 0.0))
        dome.closeSubpath()
        c.fill(dome, with: .color(steel))
        c.stroke(dome, with: .color(Color(red: 0.4, green: 0.45, blue: 0.52)), style: StrokeStyle(lineWidth: lw, lineJoin: .round))
        var ridge = Path()
        ridge.move(to: p(0.5, 0.21))
        ridge.addLine(to: p(0.5, 0.36))
        c.stroke(ridge, with: .color(Color(red: 0.55, green: 0.6, blue: 0.66)), lineWidth: lw * 0.8)
    }

    private func drawPlume(_ c: inout GraphicsContext) {
        var plume = Path()
        plume.move(to: p(0.5, 0.22))
        plume.addQuadCurve(to: p(0.74, 0.02), control: p(0.5, 0.02))
        plume.addQuadCurve(to: p(0.56, 0.24), control: p(0.7, 0.18))
        plume.closeSubpath()
        c.fill(plume, with: .color(Color(red: 0.92, green: 0.32, blue: 0.38)))
        c.stroke(plume, with: .color(Color(red: 0.6, green: 0.12, blue: 0.18)), style: StrokeStyle(lineWidth: lw * 0.7, lineJoin: .round))
    }

    private func drawTuft(_ c: inout GraphicsContext) {
        var tuft = Path()
        tuft.move(to: p(0.46, 0.31))
        tuft.addQuadCurve(to: p(0.5, 0.22), control: p(0.44, 0.24))
        tuft.addQuadCurve(to: p(0.55, 0.31), control: p(0.56, 0.24))
        c.fill(tuft, with: .color(pal.fur))
        c.stroke(tuft, with: .color(pal.outline), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round, lineJoin: .round))
    }
}

#Preview {
    VStack {
        HStack { ForEach(Array("KQRBNP"), id: \.self) { CatPiece(piece: $0).frame(width: 60, height: 60) } }
        HStack { ForEach(Array("kqrbnp"), id: \.self) { CatPiece(piece: $0).frame(width: 60, height: 60) } }
        HStack {
            CatPiece(piece: "Q", mood: .happy)
            CatPiece(piece: "N", mood: .sad)
            CatPiece(piece: "B", mood: .worried)
            CatPiece(piece: "k", mood: .shocked)
            CatPiece(piece: "K", mood: .dizzy)
        }
        .frame(height: 60)
    }
    .padding()
    .background(Color(white: 0.2))
}
