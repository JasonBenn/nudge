import Foundation

struct AWEvent: Decodable {
    let timestamp: String
    let duration: Double
    let data: AWEventData
}

struct AWEventData: Decodable {
    let url: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case url, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
    }
}

// MARK: - AW Settings / Categories

struct AWSettings: Decodable {
    let classes: [AWCategory]
}

struct AWCategory: Decodable {
    let name: [String]
    let rule: AWRule
}

struct AWRule: Decodable {
    let type: String
    let regex: String?
    let ignore_case: Bool?
}

/// A compiled AW category with its top-level group and regex.
struct CompiledCategory {
    let group: String  // e.g. "Distraction", "Communication", "Work"
    let name: String   // e.g. "Distraction > Social Media"
    let regex: NSRegularExpression
}

enum ActivityWatchService {
    /// Fetch all bucket IDs from the AW API.
    static func listBuckets() async -> [String] {
        guard let url = URL(string: "\(Config.awBase)/0/buckets") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return Array(json.keys)
        } catch {
            print("[AW] Failed to list buckets: \(error)")
            return []
        }
    }

    /// Find the web-chrome bucket with the most recent event.
    static func findWebChromeBucket() async -> String? {
        let buckets = await listBuckets()
        var webBuckets = buckets.filter { $0.lowercased().contains("web") && $0.lowercased().contains("chrome") }
        if webBuckets.isEmpty {
            webBuckets = buckets.filter { $0.lowercased().contains("web") }
        }
        if webBuckets.isEmpty {
            print("[AW] No web watcher bucket found. Available: \(buckets)")
            return nil
        }

        var best: String? = nil
        var bestTimestamp = ""
        for bucketId in webBuckets {
            let events = await getLatestEvents(bucketId: bucketId, limit: 1)
            let ts = events.first?.timestamp ?? ""
            if ts > bestTimestamp {
                bestTimestamp = ts
                best = bucketId
            }
        }
        return best
    }

    /// Fetch all AW category patterns, compiled and grouped by top-level category.
    static func fetchAllCategories() async -> [CompiledCategory] {
        guard let url = URL(string: "\(Config.awBase)/0/settings") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let settings = try JSONDecoder().decode(AWSettings.self, from: data)
            var categories: [CompiledCategory] = []
            for category in settings.classes {
                guard let group = category.name.first,
                      category.rule.type == "regex",
                      let regex = category.rule.regex else { continue }
                let options: NSRegularExpression.Options = category.rule.ignore_case == true ? [.caseInsensitive] : []
                if let compiled = try? NSRegularExpression(pattern: regex, options: options) {
                    let name = category.name.joined(separator: " > ")
                    categories.append(CompiledCategory(group: group, name: name, regex: compiled))
                    print("[AW] Loaded category: \(name)")
                }
            }
            print("[AW] Loaded \(categories.count) categories from ActivityWatch")
            return categories
        } catch {
            print("[AW] Failed to fetch settings: \(error)")
            return []
        }
    }

    /// Fetch recent events from a bucket.
    static func getLatestEvents(bucketId: String, limit: Int = 5) async -> [AWEvent] {
        guard var components = URLComponents(string: "\(Config.awBase)/0/buckets/\(bucketId)/events") else { return [] }
        components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = components.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([AWEvent].self, from: data)
        } catch {
            print("[AW] Failed to get events for \(bucketId): \(error)")
            return []
        }
    }
}
