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
