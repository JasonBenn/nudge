import Foundation
import SwiftData

@Model
final class Response {
    var text: String
    var type: String  // "trigger" or "replacement"
    var createdAt: Date

    init(text: String, type: String) {
        self.text = text
        self.type = type
        self.createdAt = Date()
    }
}

@Model
final class NudgeEvent {
    var timestamp: Date
    var siteURL: String
    var siteTitle: String
    var nudge: String
    var triggerResponse: Response?
    var replacementResponse: Response?
    @Relationship(inverse: \Conversation.event) var conversation: Conversation?

    init(siteURL: String, siteTitle: String, nudge: String) {
        self.timestamp = Date()
        self.siteURL = siteURL
        self.siteTitle = siteTitle
        self.nudge = nudge
    }
}

@Model
final class Conversation {
    var event: NudgeEvent?
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var messages: [Message]

    init() {
        self.createdAt = Date()
        self.messages = []
    }
}

@Model
final class Message {
    var conversation: Conversation?
    var role: String  // "user" or "assistant"
    var content: String
    var createdAt: Date

    init(role: String, content: String) {
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
