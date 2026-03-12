import Foundation
import SwiftData

@Model
final class NudgeEvent {
    var timestamp: Date
    var siteURL: String
    var siteTitle: String
    /// JSON blob capturing the full check-in interaction
    var interactionJSON: String

    init(siteURL: String, siteTitle: String, interaction: Interaction) {
        self.timestamp = Date()
        self.siteURL = siteURL
        self.siteTitle = siteTitle
        self.interactionJSON = (try? String(data: JSONEncoder().encode(interaction), encoding: .utf8)) ?? "{}"
    }

    var interaction: Interaction? {
        guard let data = interactionJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Interaction.self, from: data)
    }
}

struct Interaction: Codable {
    var nudge: String
    var triggerSelection: String
    var replacementSelection: String
    var tabAction: String
    var conversation: [ConversationMessage]
    var completedAt: Date?

    struct ConversationMessage: Codable {
        var role: String
        var content: String
    }
}
