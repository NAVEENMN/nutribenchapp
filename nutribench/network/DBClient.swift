import Foundation

// MARK: - Networking types
struct DBRequest<T: Encodable>: Encodable {
    let action: String
    let payload: T
}

// MARK: - Client
final class DBClient {
    static let shared = DBClient()
    private init() {}

    private let baseURL = APIEndpoints.backendBase

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
