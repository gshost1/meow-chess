import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var confirmReset = false

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
                    Button("Delete all reviews", role: .destructive) { confirmReset = true }
                }
                Section("About") {
                    Text("The chess engine is written from scratch in Rust and runs entirely on your phone. Games come from Chess.com's public API.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { name = store.username }
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
}
