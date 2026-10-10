import Foundation
import Security

/// Optional, bring-your-own-key AI features. The app works fully without them.
///
/// - Meowy chat: any OpenAI-compatible `/chat/completions` endpoint (OpenAI, OpenRouter, a local server).
/// - Jev: TypeSafe's decision model via OpenRouter's Decisions API, used to understand ideas the
///   player types in their own words.
enum AIConfig {
    static let defaultBaseURL = "https://openrouter.ai/api/v1"
    static let defaultDecisionsURL = "https://openrouter.ai/api/alpha/decisions"
    static let defaultJevModel = "typesafe/jev-1.13"

    static var baseURL: String { string("aiBaseURL", defaultBaseURL) }
    static var chatModel: String { string("aiModel", "") }
    static var decisionsURL: String { string("jevURL", defaultDecisionsURL) }
    static var jevModel: String { string("jevModel", defaultJevModel) }
    static var jevEnabled: Bool { UserDefaults.standard.bool(forKey: "jevEnabled") }

    static var chatKey: String { Keychain.read("llm") ?? "" }
    /// Jev uses its own key if set, otherwise the chat key (one OpenRouter key covers both).
    static var jevKey: String { Keychain.read("jev").flatMap { $0.isEmpty ? nil : $0 } ?? chatKey }

    /// Local servers often need no key, so only a model name is required.
    static var chatReady: Bool { !chatModel.trimmingCharacters(in: .whitespaces).isEmpty }
    static var jevReady: Bool { jevEnabled && !jevKey.isEmpty }

    private static func string(_ key: String, _ fallback: String) -> String {
        let v = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? fallback : v
    }
}

enum Keychain {
    private static let service = "com.julius201.meowchess.ai"

    static func save(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ChatMessage: Codable, Hashable, Identifiable {
    var id = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

enum AIError: LocalizedError {
    case notConfigured, http(Int, String), empty

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a model in Settings → Meowy AI first."
        case .http(let code, let body): return "The AI service answered with error \(code). \(body.prefix(160))"
        case .empty: return "The AI service sent an empty answer."
        }
    }
}

enum AIService {
    // MARK: Meowy chat (OpenAI-compatible)

    static func chat(_ messages: [ChatMessage]) async throws -> String {
        guard AIConfig.chatReady else { throw AIError.notConfigured }
        let base = AIConfig.baseURL.hasSuffix("/") ? String(AIConfig.baseURL.dropLast()) : AIConfig.baseURL
        guard let url = URL(string: base + "/chat/completions") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !AIConfig.chatKey.isEmpty {
            req.setValue("Bearer \(AIConfig.chatKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("Meow Chess", forHTTPHeaderField: "X-Title")
        let body: [String: Any] = [
            "model": AIConfig.chatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.6,
            "max_tokens": 700,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            let choices: [Choice]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let text = reply.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw AIError.empty }
        return text
    }

    static func systemPrompt(rating: Int?) -> String {
        let level = rating.map { "about \($0)" } ?? "a beginner"
        return """
        You are Meowy, a warm, encouraging cat who coaches chess beginners (rated \(level)) in the app Meow Chess.
        Rules:
        - Use ONLY the engine facts you are given. Never invent moves, lines, or evaluations. If the facts don't answer a question, say so.
        - Write for a beginner: short sentences, plain words, explain any chess term you use.
        - Keep answers under 150 words unless asked for more. At most one small cat pun.
        - Always end with one concrete thing the player can practice or remember.
        """
    }

    /// Engine facts about one move, for Meowy to explain.
    static func moveFacts(_ m: MoveReview, analysis: GameAnalysis, userIsWhite: Bool) -> String {
        let mover = m.isWhite == userIsWhite ? "the player (you)" : "the opponent"
        var lines = [
            "Game: \(analysis.white) (White) vs \(analysis.black) (Black). The player is \(userIsWhite ? "White" : "Black").",
            "Move \(m.numberLabel) \(m.san), played by \(mover).",
            "Engine grade: \(m.grade.label). Evaluation before: \(m.evalBefore.text), after: \(m.evalAfter.text) (positive = White is better).",
            "What the move does: \(m.ideasText ?? "unknown")",
            "Engine's explanation: \(m.headline). \(m.explanation)",
        ]
        if let t = m.opponentThreat { lines.append("Threat before the move: \(t)") }
        if !m.playedIsBest, let b = m.bestText { lines.append("Better move: \(b)") }
        if let r = m.replyLine.first { lines.append("Opponent's best reply: \(m.replyLine.prefix(4).joined(separator: " ")) (starts with \(r))") }
        lines.append("Position before the move (FEN): \(m.fenBefore)")
        return lines.joined(separator: "\n")
    }

    // MARK: Jev decision model

    struct IntentDecision {
        let category: IdeaCategory
        let probability: Double
        let confidence: Double
        /// Probability that the move really achieves what the player said.
        let achieves: Double
    }

    /// Turns the player's own words ("I wanted to trap his queen") into an idea category, and checks it.
    static func classifyIntent(_ typed: String, move m: MoveReview) async throws -> IntentDecision {
        guard AIConfig.jevReady, let url = URL(string: AIConfig.decisionsURL) else { throw AIError.notConfigured }
        var criteria: [String: String] = [:]
        for c in IdeaCategory.allCases { criteria[c.rawValue] = "The player wanted to \(c.verb)" }
        let body: [String: Any] = [
            "model": AIConfig.jevModel,
            "state": [
                "player_said": typed,
                "move": m.san,
                "what_the_move_does": m.ideasText ?? "",
            ],
            "questions": [
                "intent": [
                    "type": "choice",
                    "instructions": "In `player_said`, a chess player explains what they were trying to do with `move`. Which goal did they describe?",
                    "criteria": criteria,
                ],
                "achieves": [
                    "type": "noul",
                    "instructions": "According to `what_the_move_does`, does the move actually accomplish the goal described in `player_said`?",
                ],
            ],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(AIConfig.jevKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = json["answers"] as? [String: Any],
              let intent = answers["intent"] as? [String: Any],
              let choice = intent["choice"] as? String,
              let category = IdeaCategory(rawValue: choice) else { throw AIError.empty }
        let probs = intent["probabilities"] as? [String: Double] ?? [:]
        let achieves = (answers["achieves"] as? [String: Any])?["noul"] as? Double ?? 0.5
        return IntentDecision(category: category, probability: probs[choice] ?? 0,
                              confidence: intent["confidence"] as? Double ?? 0, achieves: achieves)
    }
}
