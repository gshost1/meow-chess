import SwiftUI
import AppKit

// Draws the app icon: the king cat from CatPieces.swift on a green checkerboard.
// Usage (from the repo root):
//   swiftc -parse-as-library -o /tmp/make_icon ios/MeowChess/CatPieces.swift scripts/make_icon.swift
//   /tmp/make_icon ios/MeowChess/Assets.xcassets/AppIcon.appiconset/icon.png
// App Store Connect rejects icons with an alpha channel, so the PNG is written without one.

/// The icon: a cat piece on the board.
struct IconView: View {
    let piece: Character
    let mood: PieceMood
    let light = Color(red: 154 / 255, green: 154 / 255, blue: 136 / 255)
    let dark = Color(red: 76 / 255, green: 98 / 255, blue: 57 / 255)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<4) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<4) { c in
                            Rectangle().fill((r + c) % 2 == 0 ? light : dark)
                        }
                    }
                }
            }
            CatPiece(piece: piece, mood: mood)
                .frame(width: 760, height: 760)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                .offset(y: 20)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func save(_ piece: Character, _ mood: PieceMood, _ path: String) {
    let r = ImageRenderer(content: IconView(piece: piece, mood: mood))
    r.scale = 1
    guard let cg = r.cgImage,
          let opaque = cg.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!),
          let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("render failed") }
    ctx.draw(opaque, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@main
struct MakeIcon {
    @MainActor static func main() {
        save("K", .happy, CommandLine.arguments[1])
    }
}
