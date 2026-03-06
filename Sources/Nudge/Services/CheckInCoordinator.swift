import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class CheckInCoordinator {
    var chatMessages: [ChatMessage] = []
    var streamingText = ""
    var checkInData: CheckInData?
    var isLoading = false

    private let claude = ClaudeService()
    private let contextGatherer = ContextGatherer()
    private let panel = FloatingPanel()
    private var currentSiteURL = ""
    private var currentSiteTitle = ""
    private var currentNudge = ""
    private var modelContext: ModelContext?

    func setModelContext(_ ctx: ModelContext) {
        self.modelContext = ctx
    }

    // MARK: - Trigger flow

    func handleDistraction(url: String, title: String) {
        currentSiteURL = url
        currentSiteTitle = title
        isLoading = true
        chatMessages = []
        streamingText = ""
        checkInData = nil

        Task {
            do {
                let context = buildContext(url: url, title: title)
                let data = try await claude.generateCheckIn(context: context)
                self.checkInData = data
                self.currentNudge = data.nudge
                self.isLoading = false
                showPanel()
            } catch {
                print("[Nudge] Failed to generate check-in: \(error)")
                // Fallback
                let fallback = CheckInData(
                    nudge: "Noticed you switched to a distracting site. What's going on?",
                    trigger_options: ["Bored", "Anxious", "Tired", "Avoiding something", "Just a habit"],
                    replacement_options: ["Get back to deep work", "Take a walk", "Read something", "Quick stretch", "Journal for 5 min"]
                )
                self.checkInData = fallback
                self.currentNudge = fallback.nudge
                self.isLoading = false
                showPanel()
            }
        }
    }

    // MARK: - Panel

    private func showPanel() {
        guard let data = checkInData else { return }
        let view = CheckInView(
            data: data,
            coordinator: self,
            onComplete: { [weak self] trigger, replacement in
                self?.saveEvent(trigger: trigger, replacement: replacement)
                self?.dismissPanel()
            },
            onDismiss: { [weak self] in
                self?.dismissPanel()
            }
        )
        panel.show(view)
    }

    func dismissPanel() {
        panel.dismiss()
        chatMessages = []
        streamingText = ""
        checkInData = nil
    }

    // MARK: - Chat

    func sendChatMessage(_ text: String) {
        chatMessages.append(ChatMessage(role: .user, content: text))

        Task {
            let claudeMessages = chatMessages.map {
                ClaudeMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
            }
            let system = "You are a warm, perceptive mindfulness coach. The user was just caught visiting a distracting site and wants to talk about what's going on. Be brief, warm, and insightful. Ask follow-up questions if helpful."

            var accumulated = ""
            do {
                let stream = await claude.streamChat(messages: claudeMessages, system: system)
                for try await chunk in stream {
                    accumulated += chunk
                    self.streamingText = accumulated
                }
                // Finalize: move streaming text to a proper message
                self.chatMessages.append(ChatMessage(role: .assistant, content: accumulated))
                self.streamingText = ""
            } catch {
                print("[Nudge] Chat stream error: \(error)")
                if !accumulated.isEmpty {
                    self.chatMessages.append(ChatMessage(role: .assistant, content: accumulated))
                    self.streamingText = ""
                }
            }
        }
    }

    func generateRevisedQ2(triggerSummary: String) async -> [String]? {
        let prompt = """
        The user just had a conversation about why they got distracted. Here's what they said:

        Trigger: \(triggerSummary)

        Conversation:
        \(chatMessages.map { "\($0.role == .user ? "User" : "Coach"): \($0.content)" }.joined(separator: "\n"))

        Based on this conversation, generate exactly 5 personalized suggestions for what they could do instead right now. Make them specific to what they shared — not generic. Return JSON only:
        {"replacement_options": ["...", "...", "...", "...", "..."]}
        """
        do {
            let body = ClaudeRequest(
                model: Config.claudeModel,
                max_tokens: 512,
                system: nil,
                messages: [ClaudeMessage(role: "user", content: prompt)],
                stream: nil
            )
            // Use claude service directly
            let data = try await claude.generateRawResponse(body: body)
            var cleaned = data.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                cleaned = cleaned.split(separator: "\n", maxSplits: 1).dropFirst().joined(separator: "\n")
                if let fence = cleaned.range(of: "```") {
                    cleaned = String(cleaned[cleaned.startIndex..<fence.lowerBound])
                }
            }
            struct Q2Response: Decodable { let replacement_options: [String] }
            let parsed = try JSONDecoder().decode(Q2Response.self, from: Data(cleaned.utf8))
            return parsed.replacement_options
        } catch {
            print("[Nudge] Failed to generate revised Q2: \(error)")
            return nil
        }
    }

    func summarizeAndComplete() async -> String {
        guard !chatMessages.isEmpty else { return "" }
        let claudeMessages = chatMessages.map {
            ClaudeMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }
        do {
            return try await claude.summarizeConversation(messages: claudeMessages)
        } catch {
            print("[Nudge] Summarization error: \(error)")
            return chatMessages.last?.content ?? ""
        }
    }

    // MARK: - Persistence

    private func saveEvent(trigger: String, replacement: String) {
        guard let ctx = modelContext else { return }

        let event = NudgeEvent(siteURL: currentSiteURL, siteTitle: currentSiteTitle, nudge: currentNudge)

        if !trigger.isEmpty {
            let triggerResp = getOrCreateResponse(ctx: ctx, text: trigger, type: "trigger")
            event.triggerResponse = triggerResp
        }
        if !replacement.isEmpty {
            let replacementResp = getOrCreateResponse(ctx: ctx, text: replacement, type: "replacement")
            event.replacementResponse = replacementResp
        }

        // Save conversation if there are chat messages
        if !chatMessages.isEmpty {
            let conversation = Conversation()
            conversation.event = event
            event.conversation = conversation
            ctx.insert(conversation)

            for msg in chatMessages {
                let message = Message(role: msg.role == .user ? "user" : "assistant", content: msg.content)
                message.conversation = conversation
                conversation.messages.append(message)
                ctx.insert(message)
            }
        }

        ctx.insert(event)
        try? ctx.save()
        print("[Nudge] Event saved — trigger: \(trigger), replacement: \(replacement)")
    }

    private func getOrCreateResponse(ctx: ModelContext, text: String, type: String) -> Response {
        let predicate = #Predicate<Response> { r in
            r.text == text && r.type == type
        }
        let descriptor = FetchDescriptor<Response>(predicate: predicate)
        if let existing = try? ctx.fetch(descriptor).first {
            return existing
        }
        let response = Response(text: text, type: type)
        ctx.insert(response)
        return response
    }

    // MARK: - Context

    private func buildContext(url: String, title: String) -> String {
        var context = "Just visited: \(url) (\(title))\n"
        if let ctx = modelContext {
            context += contextGatherer.gatherContext(modelContext: ctx)
        }
        return context
    }
}
