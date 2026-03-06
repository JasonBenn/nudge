import Foundation

// MARK: - Request

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [ClaudeMessage]
    let stream: Bool?
}

struct ClaudeMessage: Codable {
    let role: String  // "user" or "assistant"
    let content: String
}

// MARK: - Non-streaming response

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let stop_reason: String?
}

struct ContentBlock: Decodable {
    let type: String
    let text: String?
}

// MARK: - Streaming

struct StreamEvent: Decodable {
    let type: String
    let delta: StreamDelta?
}

struct StreamDelta: Decodable {
    let type: String?
    let text: String?
}

// MARK: - Check-in output

struct CheckInData: Decodable {
    let nudge: String
    let trigger_options: [String]
    let replacement_options: [String]
}
