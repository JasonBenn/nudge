import Foundation
import SwiftData

/// Gathers context for Claude prompts from multiple sources.
struct ContextGatherer {
    func gatherContext(modelContext: ModelContext) -> String {
        var parts: [String] = []

        // 1. Current time
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        parts.append("Current time: \(formatter.string(from: now))")

        // 2. Previous app from AW window watcher
        if let appName = fetchCurrentApp() {
            parts.append("Previous app: \(appName)")
        }

        // 3. Last 50 NudgeEvents
        let events = fetchRecentEvents(modelContext: modelContext)
        if !events.isEmpty {
            parts.append("\nLast \(events.count) distraction events:")
            for event in events {
                let ts = formatter.string(from: event.timestamp)
                if let i = event.interaction {
                    var line = "- \(ts) | \(event.siteURL)"
                    if !i.triggerSelection.isEmpty { line += " | trigger: \(i.triggerSelection)" }
                    if !i.replacementSelection.isEmpty { line += " | replacement: \(i.replacementSelection)" }
                    if !i.conversation.isEmpty {
                        let convo = i.conversation.map { "\($0.role): \($0.content)" }.joined(separator: " → ")
                        line += " | chat: \(convo)"
                    }
                    parts.append(line)
                } else {
                    parts.append("- \(ts) | \(event.siteURL) | (no interaction data)")
                }
            }
        }

        // 4. Latest weekly note
        if let weeklyNote = readWeeklyNote() {
            parts.append("\n--- Weekly Note ---\n\(weeklyNote)")
        }

        // 5. Today's and yesterday's journal entries
        if let journal = readJournalEntries() {
            parts.append("\n--- Journal ---\n\(journal)")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - ActivityWatch window watcher

    private func fetchCurrentApp() -> String? {
        guard let url = URL(string: "\(Config.awBase)/0/buckets") else { return nil }
        guard let data = try? Data(contentsOf: url),
              let buckets = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let windowBuckets = buckets.keys.filter { $0.hasPrefix("aw-watcher-window") }
        guard let bucketId = windowBuckets.first else { return nil }

        guard let eventsURL = URL(string: "\(Config.awBase)/0/buckets/\(bucketId)/events?limit=1") else { return nil }
        guard let eventsData = try? Data(contentsOf: eventsURL),
              let events = try? JSONSerialization.jsonObject(with: eventsData) as? [[String: Any]],
              let latest = events.first,
              let eventData = latest["data"] as? [String: Any],
              let appName = eventData["app"] as? String
        else { return nil }

        return appName
    }

    // MARK: - SwiftData events

    private func fetchRecentEvents(modelContext: ModelContext) -> [NudgeEvent] {
        let descriptor = FetchDescriptor<NudgeEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 50
        return (try? modelContext.fetch(limited)) ?? []
    }

    // MARK: - Weekly note

    private func readWeeklyNote() -> String? {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.year, from: Date())
        let weekStr = String(format: "%02d", week)
        let path = "\(Config.weeklyNotesDir)/\(year)-W\(weekStr).md"
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Journal entries

    private func readJournalEntries() -> String? {
        guard let full = try? String(contentsOfFile: Config.journalPath, encoding: .utf8) else { return nil }

        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayStr = df.string(from: today)
        let yesterdayStr = df.string(from: yesterday)

        // Split on ### [[date]] headers
        let lines = full.components(separatedBy: "\n")
        var result: [String] = []
        var capturing = false
        var capturedHeader = ""

        for line in lines {
            if line.hasPrefix("### [[") {
                let isToday = line.contains(todayStr)
                let isYesterday = line.contains(yesterdayStr)
                capturing = isToday || isYesterday
                if capturing {
                    capturedHeader = line
                    result.append(capturedHeader)
                }
            } else if capturing {
                // Stop at next header
                if line.hasPrefix("### [[") || line.hasPrefix("## ") || line.hasPrefix("# ") {
                    capturing = false
                } else {
                    result.append(line)
                }
            }
        }

        return result.isEmpty ? nil : result.joined(separator: "\n")
    }
}
