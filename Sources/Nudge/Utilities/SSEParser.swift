import Foundation

enum SSEParser {
    /// Parse a single SSE line and return the text delta if present, or nil.
    /// Returns an empty string to signal stream completion (message_stop).
    static func parse(line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { return "" }

        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
        else { return nil }

        switch event.type {
        case "content_block_delta":
            return event.delta?.text
        case "message_stop":
            return ""
        default:
            return nil
        }
    }
}
