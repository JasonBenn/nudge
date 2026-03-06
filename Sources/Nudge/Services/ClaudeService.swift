import Foundation

private let systemPrompt = """
You are a gentle, perceptive mindfulness coach embedded in a distraction watcher.
When the user visits a distracting site during work hours, you generate a short nudge
and two sets of multiple-choice options for an interactive check-in.

You will receive the user's last 50 distraction events, including:
- The site they visited and when
- What they selected in previous check-in flows (trigger and replacement responses)

Your job:
1. Write a short, warm nudge (1-2 sentences). Reference patterns you notice — frequency,
   time of day, specific sites, recurring triggers. Be specific, not generic.
   Examples: "Third time on Twitter in the last hour — something bugging you?"
   "YouTube again right after that long focus block. Decompressing or avoiding something?"

2. Generate exactly 5 trigger options for Q1: "What's going on?"
   These should be common reasons for distraction, personalized based on their history.
   Mix recurring patterns you see with fresh possibilities.
   Examples: "Bored with current task", "Anxious about deadline", "Just tired",
   "Avoiding a hard conversation", "Procrastinating on [specific thing from history]"

3. Generate exactly 5 replacement options for Q2: "What would you rather do instead?"
   These should be wholesome, motivating alternatives personalized to what they've
   previously said they'd rather do (from their history). Mix familiar favorites
   with fresh suggestions.
   Examples: "Get back to deep work", "Take a 5-min walk", "Read that book chapter",
   "Do a quick workout", "Write in journal for 5 minutes"

Respond in JSON only:
{
  "nudge": "...",
  "trigger_options": ["...", "...", "...", "...", "..."],
  "replacement_options": ["...", "...", "...", "...", "..."]
}
"""

actor ClaudeService {
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private func makeRequest(body: ClaudeRequest) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    // MARK: - Non-streaming check-in

    func generateCheckIn(context: String) async throws -> CheckInData {
        let body = ClaudeRequest(
            model: Config.claudeModel,
            max_tokens: 1024,
            system: systemPrompt,
            messages: [ClaudeMessage(role: "user", content: context)],
            stream: nil
        )
        let request = try makeRequest(body: body)
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ClaudeResponse.self, from: data)

        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.emptyResponse
        }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.split(separator: "\n", maxSplits: 1).dropFirst().joined(separator: "\n")
            if let fence = cleaned.range(of: "```") {
                cleaned = String(cleaned[cleaned.startIndex..<fence.lowerBound])
            }
        }
        return try decoder.decode(CheckInData.self, from: Data(cleaned.utf8))
    }

    // MARK: - Raw non-streaming call

    func generateRawResponse(body: ClaudeRequest) async throws -> String {
        let request = try makeRequest(body: body)
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ClaudeResponse.self, from: data)
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.emptyResponse
        }
        return text
    }

    // MARK: - Streaming chat

    func streamChat(messages: [ClaudeMessage], system: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = ClaudeRequest(
                        model: Config.claudeModel,
                        max_tokens: 1024,
                        system: system,
                        messages: messages,
                        stream: true
                    )
                    let request = try self.makeRequest(body: body)
                    let (asyncBytes, _) = try await self.session.bytes(for: request)

                    for try await line in asyncBytes.lines {
                        guard !line.isEmpty else { continue }
                        if let parsed = SSEParser.parse(line: line) {
                            if parsed.isEmpty {
                                // stream done
                                break
                            }
                            continuation.yield(parsed)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Summarize conversation

    func summarizeConversation(messages: [ClaudeMessage]) async throws -> String {
        let body = ClaudeRequest(
            model: Config.claudeModel,
            max_tokens: 128,
            system: "Summarize this conversation in one short sentence.",
            messages: messages,
            stream: nil
        )
        let request = try makeRequest(body: body)
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ClaudeResponse.self, from: data)

        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClaudeError: Error {
    case emptyResponse
}
