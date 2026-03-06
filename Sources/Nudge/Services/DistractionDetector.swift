import Foundation
import Observation

@Observable
final class DistractionDetector {
    var isPaused = false
    var lastDetectedURL = ""
    var lastDetectedTitle = ""

    /// Called on the main actor when a fresh distraction is detected.
    var onDistraction: ((String, String) -> Void)?

    private var bucketId: String?
    private var lastEventTimestamp: String?
    private var lastTriggerTime: Date = .distantPast
    private var lastURLWasDistracting = false
    private var pollingTask: Task<Void, Never>?

    init() {
        startPolling()
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
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

        let currentlyDistracting = isDistracting(url)
        let isFresh = currentlyDistracting && !lastURLWasDistracting
        lastURLWasDistracting = currentlyDistracting

        guard isFresh else { return }

        let elapsed = Date().timeIntervalSince(lastTriggerTime)
        guard elapsed >= Config.rateLimitSeconds else {
            let remaining = Int(Config.rateLimitSeconds - elapsed)
            print("[Nudge] Rate limited — \(remaining)s until next trigger. Site: \(url)")
            return
        }

        print("[Nudge] Fresh distraction: \(url) — triggering")
        lastDetectedURL = url
        lastDetectedTitle = title
        lastTriggerTime = Date()

        let capturedURL = url
        let capturedTitle = title
        await MainActor.run {
            self.onDistraction?(capturedURL, capturedTitle)
        }
    }

    private func isDistracting(_ url: String) -> Bool {
        let lower = url.lowercased()
        return Config.distractingDomains.contains { lower.contains($0) }
    }

    deinit {
        pollingTask?.cancel()
    }
}
