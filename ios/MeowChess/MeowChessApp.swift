import SwiftUI

@main
struct MeowChessApp: App {
    @StateObject private var store: Store

    init() {
        // Reset before constructing any AppStorage wrappers, so their cached values are fresh.
        if UITesting.resetRequested { Store.eraseEverything() }
        _store = StateObject(wrappedValue: Store())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.47, green: 0.75, blue: 0.35))
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if store.username.isEmpty {
            WelcomeView()
        } else {
            TabView(selection: $store.tab) {
                GamesView()
                    .tabItem { Label("Games", systemImage: "list.bullet.rectangle") }
                    .tag("games")
                CoachView()
                    .tabItem { Label("Meowy", systemImage: "pawprint.fill") }
                    .tag("coach")
                PracticeView()
                    .tabItem { Label("Practice", systemImage: "puzzlepiece.extension.fill") }
                    .tag("practice")
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag("settings")
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var keyboardUp = false

    var body: some View {
        VStack(spacing: keyboardUp ? 12 : 24) {
            Spacer(minLength: 8)
            if !keyboardUp {
                HStack(spacing: -10) {
                    ChessPiece(piece: "N", mood: .happy).frame(width: 90, height: 90)
                    ChessPiece(piece: "Q", mood: .happy).frame(width: 110, height: 110)
                    ChessPiece(piece: "p", mood: .normal).frame(width: 80, height: 80)
                }
            }
            Text("Meow Chess").font(.largeTitle.bold())
            Text("Meowy, your cat coach, reviews your Chess.com games with a chess engine built in Rust and explains every move in plain English.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            TextField("Chess.com username", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)))
                .padding(.horizontal, 32)
                .onChange(of: name) { _, new in fixDashes(new) }
            if let hint = ChessComUsername.hint(name) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PieceStylePicker()
                .padding(.horizontal, 32)
            Button {
                store.replaceUsername(name)
            } label: {
                Text("Get my games").bold().frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .disabled(ChessComUsername.normalize(name).isEmpty)
            Spacer(minLength: 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }

    /// iOS replaces a typed `--` with an em dash. Put the dashes back while the field is open.
    private func fixDashes(_ new: String) {
        let fixed = ChessComUsername.fixDashes(new)
        if fixed != new { name = fixed }
    }
}
