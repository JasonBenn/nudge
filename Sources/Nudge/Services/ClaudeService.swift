import Foundation

actor ClaudeService {
    private let session = URLSession.shared
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
}

enum ClaudeError: Error {
    case emptyResponse
}
