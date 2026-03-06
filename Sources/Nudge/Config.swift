import Foundation

enum Config {
    static let awBase = "http://localhost:5600/api"
    static let pollIntervalSeconds: TimeInterval = 20
    static let rateLimitSeconds: TimeInterval = 0
    static let workStartHour = 8
    static let workEndHour = 17
    static let claudeModel = "claude-opus-4-6"

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
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty, envKey != "YOUR_API_KEY_HERE" {
            return envKey
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/code/nudge/.env"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                return String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count))
            }
        }
        return ""
    }
}
