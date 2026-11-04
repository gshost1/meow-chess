import SwiftUI

/// Shared by the board, move animations, captured pieces, and piece previews.
struct ChessPiece: View {
    @EnvironmentObject var store: Store
    let piece: Character
    var mood: PieceMood = .normal

    var body: some View {
        Group {
            if store.pieceStyle == .classic {
                Image("classic-\(piece.isUppercase ? "w" : "b")\(piece.uppercased())")
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(pieceName(piece))
            } else {
                CatPiece(piece: piece, mood: mood)
            }
        }
    }
}

struct PieceStylePicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                ForEach(PieceStyle.allCases) { style in
                    HStack(spacing: 2) {
                        ForEach(Array("Nq"), id: \.self) { piece in
                            if style == .cat {
                                CatPiece(piece: piece).frame(width: 38, height: 38)
                            } else {
                                Image("classic-\(piece.isUppercase ? "w" : "b")\(piece.uppercased())")
                                    .resizable().scaledToFit().frame(width: 38, height: 38)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
            Picker("Piece style", selection: Binding(get: { store.pieceStyle }, set: { store.pieceStyle = $0 })) {
                ForEach(PieceStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("piece-style")
        }
    }
}
