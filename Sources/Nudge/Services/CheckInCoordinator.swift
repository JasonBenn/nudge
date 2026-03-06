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
    var animationIcon = "eye"

    private static let eyeFrames = ["eye", "eye.fill", "eye.circle", "eye.circle.fill", "eye.fill", "eye"]
    private var animationTimer: Timer?
    private var animationFrame = 0

    private let claude = ClaudeService()
    private let contextGatherer = ContextGatherer()
    private let panel = FloatingPanel()
    private var currentSiteURL = ""
    private var currentSiteTitle = ""
    private var currentNudge = ""
    private var modelContext: ModelContext?
    private weak var detector: DistractionDetector?
    private var currentEvent: NudgeEvent?

    func setup(modelContext ctx: ModelContext, detector: DistractionDetector) {
        self.modelContext = ctx
        self.detector = detector
    }

    // MARK: - Trigger flow

    func handleDistraction(url: String, title: String) {
        if isLoading || panel.isVisible {
            print("[Nudge] Skipping — already showing check-in")
            return
        }
        currentSiteURL = url
        currentSiteTitle = title
        startAnimation()
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
                self.stopAnimation()
                self.saveInitialEvent(data: data)
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
                self.stopAnimation()
                self.saveInitialEvent(data: fallback)
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
            onComplete: { [weak self] trigger, replacement, tabAction in
                self?.updateEvent(triggerSelection: trigger, replacementSelection: replacement, tabAction: tabAction.rawValue)
                self?.handleTabAction(tabAction)
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
        currentEvent = nil
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
                self.updateEvent()
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

    private func saveInitialEvent(data: CheckInData) {
        guard let ctx = modelContext else { return }

        let interaction = Interaction(
            nudge: data.nudge,
            triggerSelection: "",
            replacementSelection: "",
            tabAction: "",
            conversation: []
        )

        let event = NudgeEvent(siteURL: currentSiteURL, siteTitle: currentSiteTitle, interaction: interaction)
        ctx.insert(event)
        try? ctx.save()
        currentEvent = event
        print("[Nudge] Event created for \(currentSiteURL)")
    }

    func updateEvent(triggerSelection: String? = nil, replacementSelection: String? = nil, tabAction: String? = nil) {
        guard let event = currentEvent, var interaction = event.interaction else { return }

        if let t = triggerSelection { interaction.triggerSelection = t }
        if let r = replacementSelection { interaction.replacementSelection = r }
        if let a = tabAction { interaction.tabAction = a }

        interaction.conversation = chatMessages.map {
            Interaction.ConversationMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }

        event.interactionJSON = (try? String(data: JSONEncoder().encode(interaction), encoding: .utf8)) ?? "{}"
        try? modelContext?.save()
    }

    // MARK: - Tab Actions

    private func handleTabAction(_ action: CheckInView.TabAction) {
        switch action {
        case .closeAll:
            closeDistractingTabs(keepCurrent: false)
        case .closeAllButCurrent:
            closeDistractingTabs(keepCurrent: true)
        case .closeInFiveMinutes:
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                self?.closeDistractingTabs(keepCurrent: false)
            }
        case .leaveOpen:
            break
        }
    }

    private func closeDistractingTabs(keepCurrent: Bool) {
        // Step 1: Get tab info from all windows (URL + title for regex matching)
        let getTabsScript = """
        set output to ""
        tell application "Google Chrome"
            set frontIndex to index of front window
            repeat with w from 1 to (count of windows)
                set theWindow to window w
                set wIndex to index of theWindow
                set activeIndex to active tab index of theWindow
                set isFront to (wIndex = frontIndex)
                repeat with t from 1 to (count of tabs of theWindow)
                    set tabURL to URL of tab t of theWindow
                    set tabTitle to title of tab t of theWindow
                    set output to output & w & "\\t" & t & "\\t" & activeIndex & "\\t" & isFront & "\\t" & tabURL & "\\t" & tabTitle & "\\n"
                end repeat
            end repeat
        end tell
        return output
        """

        guard let script = NSAppleScript(source: getTabsScript) else { return }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            print("[Nudge] AppleScript error getting tabs: \(error)")
            return
        }

        let output = result.stringValue ?? ""
        // Parse: each line is "windowIndex\ttabIndex\tactiveTabIndex\tisFrontWindow\turl\ttitle"
        struct TabInfo {
            let windowIndex: Int
            let tabIndex: Int
            let isFrontActiveTab: Bool
            let url: String
        }

        var tabsToClose: [TabInfo] = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 6,
                  let windowIdx = Int(parts[0]),
                  let tabIdx = Int(parts[1]),
                  let activeIdx = Int(parts[2]) else { continue }
            let isFrontWindow = parts[3] == "true"
            let url = parts[4]
            let title = parts[5]
            let isFrontActiveTab = isFrontWindow && tabIdx == activeIdx
            // Match against "url title" like the distraction detector does
            let matchText = "\(url) \(title)"
            let isDistracting = detector?.isDistracting(matchText) ?? false

            if isDistracting && !(keepCurrent && isFrontActiveTab) {
                tabsToClose.append(TabInfo(windowIndex: windowIdx, tabIndex: tabIdx, isFrontActiveTab: isFrontActiveTab, url: url))
            }
        }

        guard !tabsToClose.isEmpty else {
            print("[Nudge] No distracting tabs to close")
            return
        }

        // Step 2: Close tabs in reverse order (so indices stay valid)
        let sorted = tabsToClose.sorted { ($0.windowIndex, $0.tabIndex) > ($1.windowIndex, $1.tabIndex) }
        let closeCommands = sorted.map { "close tab \($0.tabIndex) of window \($0.windowIndex)" }
        let closeScript = """
        tell application "Google Chrome"
            \(closeCommands.joined(separator: "\n            "))
        end tell
        """

        print("[Nudge] Closing \(tabsToClose.count) distracting tab(s)")
        if let closeAppleScript = NSAppleScript(source: closeScript) {
            var closeError: NSDictionary?
            closeAppleScript.executeAndReturnError(&closeError)
            if let closeError {
                print("[Nudge] AppleScript error closing tabs: \(closeError)")
            }
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        animationFrame = 0
        animationIcon = Self.eyeFrames[0]
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.animationFrame += 1
                self.animationIcon = Self.eyeFrames[self.animationFrame % Self.eyeFrames.count]
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationIcon = "eye"
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
