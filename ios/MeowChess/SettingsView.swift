import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var confirmReset = false

    @AppStorage("soundOn") private var soundOn = true
    @AppStorage("aiBaseURL") private var aiBaseURL = AIConfig.defaultBaseURL
    @AppStorage("aiModel") private var aiModel = ""
    @AppStorage("jevEnabled") private var jevEnabled = false
    @AppStorage("jevModel") private var jevModel = AIConfig.defaultJevModel
    @AppStorage("jevURL") private var jevURL = AIConfig.defaultDecisionsURL
    @State private var chatKey = ""
    @State private var jevKey = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Chess.com account") {
                    TextField("Username", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(save)
                    Button("Save and reload games", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    Picker("Analysis strength", selection: Binding(get: { store.strength }, set: { store.strength = $0 })) {
                        ForEach(AnalysisStrength.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Engine")
                } footer: {
                    Text("Deep looks further ahead but takes longer. Normal is plenty for games under 1500.")
                }

                Section {
                    Toggle("Meow sounds", isOn: $soundOn)
                    Button("Play a meow") { SoundPlayer.shared.play(.check) }.disabled(!soundOn)
                    Picker("Ask \"what was your idea?\"", selection: Binding(get: { store.quizMode }, set: { store.quizMode = $0 })) {
                        ForEach(QuizMode.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Review")
                } footer: {
                    Text("Meowy can ask what you were trying to do on your own moves, then tell you whether the move really does that.")
                }

                Section {
                    TextField("Server URL", text: $aiBaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Model name (from your provider)", text: $aiModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key (leave empty for local models)", text: $chatKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Keychain.save(chatKey, account: "llm") }
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Save and test")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(aiModel.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                    if let testResult { Text(testResult).font(.caption) }
                } header: {
                    Text("Meowy AI (optional)")
                } footer: {
                    Text("Works with any OpenAI-compatible service: OpenAI (https://api.openai.com/v1), OpenRouter (the default), or a model on your own computer such as Ollama (http://<your-mac>:11434/v1). Meowy uses it for chat and personal training plans. Your key is stored in the iPhone Keychain and sent only to the server above.")
                }

                Section {
                    Toggle("Use Jev to understand your ideas", isOn: $jevEnabled)
                    if jevEnabled {
                        TextField("Jev model", text: $jevModel)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Decisions URL", text: $jevURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("OpenRouter key (empty = use the Meowy AI key)", text: $jevKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { Keychain.save(jevKey, account: "jev") }
                        Button("Save key") { Keychain.save(jevKey, account: "jev") }
                    }
                } header: {
                    Text("Decision model (optional)")
                } footer: {
                    Text("Jev is TypeSafe's decision model. Instead of writing text, it picks from fixed options and says how sure it is. When it's on, you can type your idea for a move in your own words (\"I wanted to trap the queen\"); Jev works out which kind of idea you meant and whether the move really does it. Costs a tiny fraction of a cent per answer on OpenRouter.")
                }

                Section {
                    Button("Delete all reviews", role: .destructive) { confirmReset = true }
                }
                Section("About") {
                    Text("Meow Chess: the chess engine is written from scratch in Rust and runs entirely on your phone. The cat pieces and meows are drawn and synthesized by the app itself. Games come from Chess.com's public API.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                name = store.username
                chatKey = Keychain.read("llm") ?? ""
                jevKey = Keychain.read("jev") ?? ""
            }
            .onDisappear {
                Keychain.save(chatKey, account: "llm")
                Keychain.save(jevKey, account: "jev")
            }
            .confirmationDialog("Delete all saved reviews?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteAllAnalyses() }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store.username = n
        store.games = []
        Task { await store.refreshGames() }
    }

    private func test() async {
        Keychain.save(chatKey, account: "llm")
        testing = true
        testResult = nil
        do {
            let reply = try await AIService.chat([
                ChatMessage(role: "system", content: "You are Meowy, a cat chess coach. Reply in one short sentence."),
                ChatMessage(role: "user", content: "Say hello to a new player."),
            ])
            testResult = "✅ Connected. Meowy says: \(reply)"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
        testing = false
    }
}
