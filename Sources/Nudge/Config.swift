import Foundation

enum Config {
    static let awBase = "http://localhost:5600/api"
    static let pollIntervalSeconds: TimeInterval = 20
    static let rateLimitSeconds: TimeInterval = 3600
    static let workStartHour = 8
    static let workEndHour = 17
    static let claudeModel = "claude-opus-4-6"

    static let distractingDomains: Set<String> = [
        "twitter.com",
        "x.com",
        "youtube.com",
        "news.ycombinator.com",
        "substack.com",
    ]

    static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/code/nudge/nudge.db"
    }()

    static let weeklyNotesDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/notes/Periodic/Weekly"
    }()

    static let journalPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let year = Calendar.current.component(.year, from: Date())
        return "\(home)/notes/Journals/Journals/\(year).md"
    }()

    static var anthropicAPIKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }
}
