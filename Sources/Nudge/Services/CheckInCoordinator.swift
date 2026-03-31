import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class CheckInCoordinator {
    var chatMessages: [ChatMessage] = []
    var streamingText = ""
    var isLoading = false
    var hasActiveCheckIn: Bool { panel.isVisible }
    var onChatStateChanged: (([ChatMessage], String) -> Void)?

    // Countdown state (nil = no active countdown) — single source of truth for both menu bar and panel
    var sessionRemaining: TimeInterval?
    var dailyRemaining: TimeInterval?
    var onCountdownTick: (() -> Void)?

    private let claude = ClaudeService()
    private let panel = FloatingPanel()
    private var currentSiteURL = ""
    private var currentSiteTitle = ""
    private var modelContext: ModelContext?
    private weak var detector: DistractionDetector?
    private var currentEvent: NudgeEvent?
    private var menuBarTimer: Timer?

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
        isLoading = true

        Task {
            defer { self.isLoading = false }
            // Query daily distraction time to determine tier
            let dailySeconds: TimeInterval
            if let bucketId = detector?.bucketId, let categories = detector?.categories {
                dailySeconds = await ActivityWatchService.dailyDistractionSeconds(bucketId: bucketId, categories: categories)
            } else {
                dailySeconds = 0
            }
            let dailyMinutes = dailySeconds / 60
            let countdown = Config.countdownFor(dailyMinutes: dailyMinutes)

            // Save initial event
            saveInitialEvent()

            if countdown == 0 {
                // Tier 3: immediate close, no panel — reset cooldowns so we re-trigger
                // if the user reopens distracting tabs
                print("[Nudge] Daily distraction: \(String(format: "%.0f", dailyMinutes))min — auto-closing immediately")
                updateEvent(tabAction: "auto_closed")
                closeDistractingTabs(keepCurrent: false)
                detector?.resetCooldowns()
                return
            }

            // Show panel with countdown + suggestions
            startMenuBarCountdown(sessionSeconds: countdown, dailyUsedSeconds: dailySeconds)
            let suggestions = await generateSuggestions()
            print("[Nudge] Daily distraction: \(String(format: "%.0f", dailyMinutes))min — \(Int(countdown))s countdown, \(suggestions.count) suggestions")
            showPanel(suggestions: suggestions)
        }
    }

    // MARK: - Panel

    private func showPanel(suggestions: [String]) {
        let vc = CheckInViewController(
            suggestions: suggestions,
            coordinator: self,
            onComplete: { [weak self] replacement in
                self?.updateEvent(replacementSelection: replacement, tabAction: "close_all")
                self?.closeDistractingTabs(keepCurrent: false)
                self?.dismissPanel()
            },
            onCloseAll: { [weak self] in
                self?.updateEvent(tabAction: "close_all")
                self?.closeDistractingTabs(keepCurrent: false)
                self?.dismissPanel()
            },
            onAutoClose: { [weak self] in
                self?.updateEvent(tabAction: "auto_closed")
                self?.closeDistractingTabs(keepCurrent: false)
            },
            onDismiss: { [weak self] in
                self?.updateEvent(tabAction: "dismissed")
                self?.dismissPanel()
            }
        )
        onChatStateChanged = { [weak vc] messages, streaming in
            vc?.chatStateChanged(messages: messages, streamingText: streaming)
        }
        panel.show(viewController: vc)
    }

    func refocusPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    func testNudge() {
        dismissPanel()
        currentSiteURL = "https://x.com"
        currentSiteTitle = "X / Twitter"
        saveInitialEvent()
        startMenuBarCountdown(sessionSeconds: 120, dailyUsedSeconds: 1500)
        Task {
            let suggestions = await generateSuggestions()
            showPanel(suggestions: suggestions)
        }
    }

    func runLatencyTest() {
        dismissPanel()
        currentSiteURL = "https://x.com"
        currentSiteTitle = "Latency Test"
        saveInitialEvent()
        startMenuBarCountdown(sessionSeconds: 300, dailyUsedSeconds: 0)
        Task {
            let suggestions = await generateSuggestions()
            showPanel(suggestions: suggestions)
        }
        InputLatencyMonitor.shared.runTest(panel: panel)
    }

    func dismissPanel() {
        stopMenuBarCountdown()
        panel.dismiss()
        chatMessages = []
        streamingText = ""
        currentEvent = nil
        onChatStateChanged = nil
        onCountdownTick = nil
    }

    // MARK: - Menu Bar Countdown

    private func startMenuBarCountdown(sessionSeconds: TimeInterval, dailyUsedSeconds: TimeInterval) {
        sessionRemaining = sessionSeconds
        dailyRemaining = max(0, Config.dailyBudgetSeconds - dailyUsedSeconds)
        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let s = self.sessionRemaining { self.sessionRemaining = max(0, s - 1) }
                if let d = self.dailyRemaining { self.dailyRemaining = max(0, d - 1) }
                self.onCountdownTick?()
            }
        }
    }

    func stopMenuBarCountdown() {
        menuBarTimer?.invalidate()
        menuBarTimer = nil
        sessionRemaining = nil
        dailyRemaining = nil
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
                    self.onChatStateChanged?(self.chatMessages, accumulated)
                }
                self.chatMessages.append(ChatMessage(role: .assistant, content: accumulated))
                self.streamingText = ""
                self.onChatStateChanged?(self.chatMessages, "")
                self.updateEvent()
            } catch {
                print("[Nudge] Chat stream error: \(error)")
                if !accumulated.isEmpty {
                    self.chatMessages.append(ChatMessage(role: .assistant, content: accumulated))
                    self.streamingText = ""
                    self.onChatStateChanged?(self.chatMessages, "")
                }
            }
        }
    }


    // MARK: - Suggestions

    private func fetchHistory() -> (selections: [String], starters: [String]) {
        guard let ctx = modelContext else { return ([], []) }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<NudgeEvent>(
            predicate: #Predicate { $0.timestamp >= thirtyDaysAgo },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let events = try? ctx.fetch(descriptor) else { return ([], []) }

        var selections: [String] = []
        var starters: [String] = []
        for event in events {
            guard let interaction = event.interaction else { continue }
            let choice = interaction.replacementSelection.trimmingCharacters(in: .whitespaces)
            if !choice.isEmpty, choice.count <= 100, !choice.contains("\n") {
                selections.append(choice)
            }
            if let first = interaction.conversation.first(where: { $0.role == "user" }) {
                starters.append(first.content)
            }
        }
        return (Array(selections.prefix(100)), Array(starters.prefix(50)))
    }

    private func generateSuggestions() async -> [String] {
        let (selections, starters) = fetchHistory()
        if selections.isEmpty && starters.isEmpty { return [] }

        let prompt = """
        Here are recent replacement activities a user chose when nudged away from distracting websites (most recent first):

        \(selections.joined(separator: "\n"))

        And here are things they said when starting a conversation about their distraction:

        \(starters.joined(separator: "\n"))

        Generate 5-8 short suggestion buttons for what they might do instead right now. \
        Each suggestion should be a common CATEGORY from their history, generalized (not task-specific). \
        Keep each under 50 characters. Return one suggestion per line, nothing else.
        """

        do {
            let response = try await claude.chat(
                messages: [ClaudeMessage(role: "user", content: prompt)],
                system: "You generate concise activity suggestions. Return only the suggestions, one per line."
            )
            return response.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count <= 60 }
        } catch {
            print("[Nudge] Failed to generate suggestions: \(error)")
            // Fallback: deduplicated top selections from history
            var seen = Set<String>()
            return selections.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
        }
    }

    // MARK: - Persistence

    private func saveInitialEvent() {
        guard let ctx = modelContext else { return }
        let interaction = Interaction(
            nudge: "",
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
        if let a = tabAction {
            interaction.tabAction = a
            interaction.completedAt = Date()
            let responseTime = Date().timeIntervalSince(event.timestamp)
            print("[Nudge] Check-in \(a) after \(String(format: "%.0f", responseTime))s")
        }

        interaction.conversation = chatMessages.map {
            Interaction.ConversationMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }

        event.interactionJSON = (try? String(data: JSONEncoder().encode(interaction), encoding: .utf8)) ?? "{}"
        try? modelContext?.save()
    }

    // MARK: - Tab Actions

    func closeTabsOnly() {
        updateEvent(tabAction: "close_all")
        closeDistractingTabs(keepCurrent: false)
    }

    private func closeDistractingTabs(keepCurrent: Bool) {
        let chromeRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
        guard chromeRunning else {
            print("[Nudge] Chrome not running, nothing to close")
            return
        }

        let getTabsScript = """
        set output to ""
        tell application "Google Chrome"
            set windowList to every window
            if (count of windowList) = 0 then return output
            set frontIndex to index of front window
            repeat with w from 1 to (count of windowList)
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

        // Close incognito windows
        let stillRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
        guard stillRunning else { return }

        let incognitoScript = """
        tell application "Google Chrome"
            repeat with w in (reverse of (every window whose mode is "incognito"))
                close w
            end repeat
        end tell
        """
        if let incognitoAppleScript = NSAppleScript(source: incognitoScript) {
            var incognitoError: NSDictionary?
            incognitoAppleScript.executeAndReturnError(&incognitoError)
            if let incognitoError {
                print("[Nudge] AppleScript error closing incognito: \(incognitoError)")
            }
        }
    }

}
