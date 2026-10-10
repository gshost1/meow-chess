import SwiftUI

@main
struct MeowChessApp: App {
    @StateObject private var store = Store()

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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            HStack(spacing: -10) {
                CatPiece(piece: "N", mood: .happy).frame(width: 90, height: 90)
                CatPiece(piece: "Q", mood: .happy).frame(width: 110, height: 110)
                CatPiece(piece: "p", mood: .normal).frame(width: 80, height: 80)
            }
            Text("Meow Chess").font(.largeTitle.bold())
            Text("Meowy, your cat coach, reviews your Chess.com games with a chess engine built in Rust and explains every move in plain English.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            TextField("Chess.com username", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)))
                .padding(.horizontal, 32)
            Button {
                store.username = name.trimmingCharacters(in: .whitespaces)
                Task { await store.refreshGames() }
            } label: {
                Text("Get my games").bold().frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
    }
}
