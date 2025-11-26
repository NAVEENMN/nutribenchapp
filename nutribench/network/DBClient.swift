import Foundation
import Security

// MARK: - Stable user id in Keychain
enum UserID {
    private static let service = "com.ucsb.nutribench"
    private static let account = "user_id"

    static func getOrCreate() -> String {
        if let s = read() { return s }
        let s = UUID().uuidString
        save(s)
        return s
    }
    private static func read() -> String? {
        let q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
    private static func save(_ s: String) {
        let data = s.data(using: .utf8)!
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
        SecItemAdd([kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: data] as CFDictionary, nil)
    }
}

// MARK: - Networking types
struct DBRequest<T: Encodable>: Encodable {
    let action: String
    let payload: T
}

// MARK: - Type-erased decode/encode helpers
struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(Int.self) { value = v; return }
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode([String: AnyDecodable].self) { value = v.mapValues(\.value); return }
        if let v = try? c.decode([AnyDecodable].self) { value = v.map(\.value); return }
        value = NSNull()
    }
}
extension Dictionary where Key == String, Value == AnyDecodable {
    func decode<T: Decodable>(to: T.Type) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: self.mapValues(\.value)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ v: T) { _encode = v.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Date parsing for flexible server strings
enum DateParsers {
    static func parseServerTimestamp(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }

        // 1) ISO8601 with fractional seconds
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        // 2) ISO8601 without fractional seconds
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }

        // 3) Common Mongo/Python string patterns
        let patterns = [
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", // microseconds + tz
            "yyyy-MM-dd HH:mm:ss.SSSXXXXX",    // millis + tz
            "yyyy-MM-dd HH:mm:ssXXXXX",        // no fraction + tz
            "yyyy-MM-dd HH:mm:ss.SSSSSS",      // microseconds, no tz
            "yyyy-MM-dd HH:mm:ss.SSS",         // millis, no tz
            "yyyy-MM-dd HH:mm:ss"              // seconds, no tz
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for pat in patterns {
            f.timeZone = pat.hasSuffix("XXXXX") ? TimeZone(secondsFromGMT: 0) : TimeZone.current
            f.dateFormat = pat
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - Server models
struct ServerEvent: Decodable {
    let user_id: String
    let event_id: String?
    let event_type: String

    let timestampISO: String?
    let timestamp: String?

    let details: [String: AnyDecodable]?

    func toFoodLog() -> FoodLog? {
        guard event_type == "food_log" else { return nil }
        let food = (details?["food"]?.value as? String) ?? "Food"
        let carbsText: String = {
            if let s = details?["carbsText"]?.value as? String { return s }
            if let g = details?["carbs_g"]?.value as? Double { return String(format: "%.0f g", g) }
            if let gStr = details?["total_carbs_g"]?.value as? String, let g = Double(gStr) {
                return String(format: "%.0f g", g)
            }
            return "15 g"
        }()
        let steps = (details?["calculation_steps"]?.value as? String)
                 ?? (details?["serverResponse"]?.value as? String)
        let original = (details?["originalQuery"]?.value as? String) ?? food

        // Prefer the timestampISO inside details (user-edited time), then fall back
        let detailTS = details?["timestampISO"]?.value as? String
        let date = DateParsers.parseServerTimestamp(detailTS ?? timestampISO ?? timestamp)
                 ?? Date.distantPast

        // NEW: optional image URL from server
        let imageS3URL = details?["image_s3_url"]?.value as? String

        return FoodLog(
            eventId: event_id,
            date: date,
            food: food,
            carbsText: carbsText,
            serverResponse: steps,
            originalQuery: original,
            imageS3URL: imageS3URL,
            localImageFilename: nil      // will fill when we cache locally
        )
    }
}


// MARK: - Client
final class DBClient {
    static let shared = DBClient()
    private init() {}

    private let baseURL = URL(string: "https://k6wbwg2lh5dgsb7yso2bi3dsta0nhmdy.lambda-url.us-west-2.on.aws/")!

    // Internal (not private) so extensions/other files can call it
    func postRaw<A: Encodable>(_ action: String, payload: A) async throws -> Data {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = DBRequest(action: action, payload: payload)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LambdaError", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "Lambda returned \(status): \(txt)"])
        }
        return data
    }

    // --- Users ---
    struct CreateUserPayload: Encodable {
        let user_id: String
        let name: String?
        let email: String?
    }
    func createUser(userId: String, name: String? = nil, email: String? = nil) async throws {
        _ = try await postRaw("create_user",
                              payload: CreateUserPayload(user_id: userId,
                                                         name: name,
                                                         email: email))
    }

    // --- Events (food logs) ---
    struct AddEventPayload: Encodable {
        let user_id: String
        let event_type: String
        let details: [String: AnyEncodable]
    }
    func addEvent(userId: String, details: [String: AnyEncodable]) async throws {
        _ = try await postRaw("add_event",
                              payload: AddEventPayload(user_id: userId,
                                                       event_type: "food_log",
                                                       details: details))
    }
    
    // --- Delete event ---
    struct DeleteEventPayload: Encodable { let user_id: String; let event_id: String }
    func deleteEvent(userId: String, eventId: String) async throws {
        _ = try await postRaw("delete_event", payload: DeleteEventPayload(user_id: userId, event_id: eventId))
    }

    // --- Update event (details only) ---
    struct UpdateEventPayload: Encodable {
        let user_id: String
        let event_id: String
        let details: [String: AnyEncodable]
    }
    func updateEvent(userId: String, eventId: String, details: [String: AnyEncodable]) async throws {
        _ = try await postRaw("update_event",
                              payload: UpdateEventPayload(user_id: userId, event_id: eventId, details: details))
    }

    struct GetEventsPayload: Encodable { let user_id: String; let limit: Int }
    func getEvents(userId: String, limit: Int = 100) async throws -> [ServerEvent] {
        let data = try await postRaw("get_events",
                                     payload: GetEventsPayload(user_id: userId, limit: limit))
        // Expect {"ok":true,"events":[...]}
        let decoder = JSONDecoder()
        if let obj = try? decoder.decode([String: AnyDecodable].self, from: data),
           let eventsAny = obj["events"]?.value as? [Any] {
            let edata = try JSONSerialization.data(withJSONObject: eventsAny)
            return try decoder.decode([ServerEvent].self, from: edata)
        }
        return []
    }

    // --- Health (batch upload) ---
    struct HealthSummary: Encodable {
        let dateISO8601: String
        let steps: Int
        let activeEnergyKcal: Int
        let carbsG: Double
        let exerciseMin: Int
        let heartRateBPM: Int
        let glucoseMgdl: Int
        let insulinIU: Double
    }
    private struct UploadHealthBatchPayload: Encodable {
        let user_id: String
        let data: [HealthSummary]
    }
    func uploadHealthBatch(userId: String, summaries: [HealthSummary]) async throws {
        _ = try await postRaw("upload_health_batch",
                              payload: UploadHealthBatchPayload(user_id: userId,
                                                                data: summaries))
    }
}

private func _parseStepsFromMaybeJSON(_ s: String?) -> String? {
    guard let s = s, !s.isEmpty else { return nil }
    // Try to find a JSON object within (handles raw text, code fences, escaped quotes)
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let unfenced: String = {
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }()
    if let data = unfenced.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let steps = obj["calculation_steps"] as? String {
        return steps.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}
