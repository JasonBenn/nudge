import Foundation
import Observation

@Observable
final class DistractionDetector {
    var isPaused = false
    var lastDetectedURL = ""
    var lastDetectedTitle = ""

    /// Called on the main actor when a fresh distraction is detected.
    var onDistraction: ((String, String) -> Void)?

    /// All compiled AW categories, used for classification. Distraction patterns exposed for tab closing.
    private(set) var categories: [CompiledCategory] = []
    var distractionPatterns: [NSRegularExpression] {
        categories.filter { $0.group == "Distraction" }.map(\.regex)
    }

    private var bucketId: String?
    private var lastEventTimestamp: String?
    private var lastTriggerTime: Date = .distantPast
    private var lastTriggeredURL: String = ""
    /// Tracks when we last saw a distracting AW event — used to require a sustained
    /// productive period before re-triggering (prevents false transitions from AW
    /// interleaving events across multiple Chrome windows).
    private var lastDistractingEventTime: Date = .distantPast
    private var hasProcessedFirstEvent = false
    private var pollingTask: Task<Void, Never>?

    init() {}

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            if let self {
                self.categories = await ActivityWatchService.fetchAllCategories()
            }

            while !Task.isCancelled {
                if let self, !self.isPaused {
                    await self.poll()
                }
                try? await Task.sleep(nanoseconds: UInt64(Config.pollIntervalSeconds * 1_000_000_000))
            }
        }
    }

    private func poll() async {
        if bucketId == nil {
            bucketId = await ActivityWatchService.findWebChromeBucket()
            if let bucketId {
                print("[Nudge] Using AW bucket: \(bucketId)")
            }
        }

        guard let bucketId else { return }

        let events = await ActivityWatchService.getLatestEvents(bucketId: bucketId, limit: 5)
        guard let newest = events.first else { return }

        let ts = newest.timestamp
        let url = newest.data.url
        let title = newest.data.title

        if ts == lastEventTimestamp { return }
        lastEventTimestamp = ts

        // Classify using AW categories — first match wins.
        let matchText = "\(url) \(title)"
        let currentlyDistracting = classify(matchText) == "Distraction"

        // On first event after launch, seed the state but never trigger —
        // we don't know what the user was doing before launch.
        if !hasProcessedFirstEvent {
            hasProcessedFirstEvent = true
            if currentlyDistracting { lastDistractingEventTime = Date() }
            return
        }

        // Require a sustained productive period (5 min) before triggering again.
        // AW interleaves events from multiple Chrome windows, so we can't rely on
        // single-event transitions — e.g. x.com and localhost:3300 alternate rapidly
        // even when the user is just browsing Twitter.
        let wasRecentlyDistracting = Date().timeIntervalSince(lastDistractingEventTime) < 300
        if currentlyDistracting { lastDistractingEventTime = Date() }

        guard currentlyDistracting else { return }
        guard !wasRecentlyDistracting else { return }

        let elapsed = Date().timeIntervalSince(lastTriggerTime)
        let sameURL = url == lastTriggeredURL
        let cooldownSeconds: TimeInterval = sameURL ? 600 : 60
        guard elapsed >= cooldownSeconds else {
            let remaining = Int(cooldownSeconds - elapsed)
            print("[Nudge] Rate limited — \(remaining)s until next trigger. Site: \(url)")
            return
        }

        print("[Nudge] Fresh distraction: \(url) — triggering")
        lastDetectedURL = url
        lastDetectedTitle = title
        lastTriggerTime = Date()
        lastTriggeredURL = url

        let capturedURL = url
        let capturedTitle = title
        await MainActor.run {
            self.onDistraction?(capturedURL, capturedTitle)
        }
    }

    /// Classify text against all AW categories. Returns the top-level group of the first match,
    /// or nil if nothing matches. Non-Distraction categories are checked first so they take priority.
    func classify(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        // Check non-Distraction categories first — they act as an allowlist
        for cat in categories where cat.group != "Distraction" {
            if cat.regex.firstMatch(in: text, range: range) != nil {
                return cat.group
            }
        }
        for cat in categories where cat.group == "Distraction" {
            if cat.regex.firstMatch(in: text, range: range) != nil {
                return "Distraction"
            }
        }
        return nil
    }

    /// Check if text matches any distraction pattern (used by tab closer).
    func isDistracting(_ text: String) -> Bool {
        classify(text) == "Distraction"
    }

    deinit {
        pollingTask?.cancel()
    }
}
