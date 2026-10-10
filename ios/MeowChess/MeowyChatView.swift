import SwiftUI

/// Chat with Meowy, the AI coach. Needs an OpenAI-compatible model set up in Settings (optional).
struct MeowyChatView: View {
    let title: String
    /// Engine facts Meowy must stick to.
    let facts: String
    let rating: Int?
    /// First question sent automatically when the chat opens.
    let opening: String

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if AIConfig.chatReady {
                    chat
                } else {
                    setupCard
                }
            }
            .navigationTitle("Meowy · \(title)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.filter { $0.role != "system" }.dropFirst()) { m in
                            bubble(m).id(m.id)
                        }
                        if thinking {
                            HStack {
                                CatPiece(piece: "Q", mood: .normal).frame(width: 28, height: 28)
                                ProgressView()
                                Text("Meowy is thinking…").font(.caption).foregroundStyle(.secondary)
                            }
                            .id("thinking")
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }
            HStack {
                TextField("Ask Meowy a follow-up…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button(action: send) { Image(systemName: "paperplane.fill").font(.title3) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
            }
            .padding()
        }
        .task {
            guard messages.isEmpty else { return }
            messages = [
                ChatMessage(role: "system", content: AIService.systemPrompt(rating: rating) + "\n\nEngine facts:\n" + facts),
                ChatMessage(role: "user", content: opening),
            ]
            await ask()
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if m.role == "assistant" {
                CatPiece(piece: "Q", mood: .happy).frame(width: 30, height: 30)
            } else {
                Spacer(minLength: 40)
            }
            Text(m.content)
                .font(.callout)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(m.role == "assistant" ? Color(white: 0.16) : Color.accentColor.opacity(0.3)))
                .textSelection(.enabled)
            if m.role == "assistant" { Spacer(minLength: 20) }
        }
    }

    private var setupCard: some View {
        VStack(spacing: 16) {
            CatPiece(piece: "Q", mood: .happy).frame(width: 90, height: 90)
            Text("Meowy's AI chat is optional").font(.title3.bold())
            Text("Everything else in Meow Chess works without it. To chat with Meowy, open Settings → Meowy AI and add any OpenAI-compatible service: OpenAI, OpenRouter, or a model running on your own computer. You use your own API key.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(ChatMessage(role: "user", content: text))
        Task { await ask() }
    }

    private func ask() async {
        thinking = true
        error = nil
        do {
            let reply = try await AIService.chat(messages)
            messages.append(ChatMessage(role: "assistant", content: reply))
            SoundPlayer.shared.play(.move)
        } catch {
            self.error = error.localizedDescription
        }
        thinking = false
    }
}
