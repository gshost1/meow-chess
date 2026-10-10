import SwiftUI

@main
struct ChessCoachApp: App {
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
    @State private var tab = UserDefaults.standard.string(forKey: "tab") ?? "games"

    var body: some View {
        if store.username.isEmpty {
            WelcomeView()
        } else {
            TabView(selection: $tab) {
                GamesView()
                    .tabItem { Label("Games", systemImage: "list.bullet.rectangle") }
                    .tag("games")
                HabitsView()
                    .tabItem { Label("My Habits", systemImage: "chart.bar.xaxis") }
                    .tag("habits")
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
            Text("♞\u{FE0E}").font(.system(size: 96))
            Text("Chess Coach").font(.largeTitle.bold())
            Text("Reviews your Chess.com games with a chess engine built in Rust, and explains your mistakes in plain English.")
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
