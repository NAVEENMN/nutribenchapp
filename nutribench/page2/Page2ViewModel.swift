import Foundation

// MARK: - Helpers to unwrap/clean server text

/// If the server body is a JSON-encoded *string* (e.g. "\"{\\\"food_items\\\":...}\""),
/// decode it once to get the inner JSON text.
private func unwrapJSONStringOnce(_ s: String) -> String {
    // Wrap in an array and parse, so JSON decoder will unescape once
    if let data = "[\(s)]".data(using: .utf8),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
       let first = arr.first as? String {
        return first
    }
    return s
}

/// Remove code fences and keep just the JSON object segment if present.
private func stripFencesAndExtractJSONObject(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.firstIndex(of: "{"),
       let end = trimmed.lastIndex(of: "}") {
        return String(trimmed[start...end])
    }
    return trimmed
}

// MARK: - Parser for nutrition JSON

private struct ParsedNutrition {
    let foods: [String]
    let carbsG: Double?
    let steps: String?
}

private func parseNutritionJSON(from response: String) -> ParsedNutrition? {
    let once = unwrapJSONStringOnce(response)
    let candidate = stripFencesAndExtractJSONObject(once)

    guard let data = candidate.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    let foods = (obj["food_items"] as? [Any])?
        .compactMap { $0 as? String }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty } ?? []

    // Try common keys; tolerate localized/annotated strings like "6g", "0g de carbohidratos"
    let carbsG =
        numberFromAny(obj["total_carbs_g"]) ??
        numberFromAny(obj["carbs_g"]) ??
        numberFromAny(obj["carbs"]) ??
        numberFromAny(obj["total_carbs"])

    let steps = (obj["calculation_steps"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return ParsedNutrition(foods: foods, carbsG: carbsG, steps: steps)
}

/// Keep quantities like "3 tangerines" intact,
/// only normalize trivial "1 " prefix (for cleaner display).
private func normalizeFoodName(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    // Only drop leading "1 " (e.g. "1 bagel" -> "bagel")
    if trimmed.hasPrefix("1 ") {
        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    return trimmed
}

private func numberFromAny(_ any: Any?) -> Double? {
    switch any {
    case let d as Double: return d
    case let i as Int:    return Double(i)
    case let s as String:
        if let d = Double(s) { return d }
        // Regex: first integer/decimal in the string
        if let match = try? NSRegularExpression(pattern: #"(\d+(\.\d+)?)"#)
            .firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let r = Range(match.range(at: 1), in: s) {
            return Double(s[r])
        }
        return nil
    default:
        return nil
    }
}

@MainActor
final class Page2ViewModel: ObservableObject {
    @Published var logs: [FoodLog] = []
    @Published var isSending = false
    @Published var sendError: String?
    @Published var isLoading = false

    // Edit flow
    @Published var editing: FoodLog? = nil

    // Your nutrition inference Lambda (returns {statusCode, body})
    private let endpoint = URL(string: "https://5lcj2njvoq4urxszpj7lqoatxy0gslkf.lambda-url.us-west-2.on.aws/")!

    // Load historical food logs from DB Lambda
    func loadHistory() {
        let uid = UserID.getOrCreate()
        isLoading = true
        Task {
            do {
                let events = try await DBClient.shared.getEvents(userId: uid, limit: 200)
                let mapped = events.compactMap { $0.toFoodLog() }
                await MainActor.run {
                    self.logs = mapped.sorted { $0.date > $1.date }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sendError = "History fetch failed."
                    self.isLoading = false
                }
            }
        }
    }

    // Submit a new query to the nutrition Lambda, then save locally & to DB
    func submit(food: String) {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        sendError = nil

        postFood(trimmed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false
                switch result {
                case .success(let responseText):
                    _ = self.addLocal(food: trimmed, response: responseText)
                case .failure(let err):
                    self.sendError = err.localizedDescription
                    _ = self.addLocal(food: trimmed, response: nil)
                }
            }
        }
    }

    // Add a new log (parsing server JSON for foods + carbs + steps) and persist to DB
    @discardableResult
    func addLocal(food: String, response: String?) -> FoodLog {
        var displayFood = food
        var carbsDisplay = "15g"   // normalized "48g"
        var stepsText: String? = nil

        if let response, let parsed = parseNutritionJSON(from: response) {
            if !parsed.foods.isEmpty {
                // Keep quantities (e.g., "3 tangerines")
                displayFood = parsed.foods
                    .map(normalizeFoodName)
                    .joined(separator: ", ")
            }
            if let g = parsed.carbsG {
                carbsDisplay = String(format: "%.0fg", g)  // "48g"
            }
            stepsText = parsed.steps
        } else if let t = extractCarbText(from: response) {
            // fallback for legacy/plain text responses, normalize to "48g"
            let cleaned = t
                .replacingOccurrences(of: "carbs", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " ", with: "")
            carbsDisplay = cleaned.isEmpty ? "15g" : cleaned
        }

        var newLog = FoodLog(
            eventId: nil,                 // will patch after server returns
            date: Date(),
            food: displayFood,
            carbsText: carbsDisplay,
            serverResponse: stepsText,    // expanded shows steps
            originalQuery: food           // expanded shows user's text
        )

        logs.append(newLog)
        logs.sort { $0.date > $1.date }

        // Persist to DB Lambda with rich details (including the original query)
        let uid = UserID.getOrCreate()
        Task {
            let details: [String: AnyEncodable] = [
                "food": AnyEncodable(displayFood),
                "carbsText": AnyEncodable(carbsDisplay),
                "total_carbs_g": AnyEncodable(Int(carbsDisplay.replacingOccurrences(of: "g", with: "")) ?? 0),
                // store steps redundantly so reads are robust
                "serverResponse": AnyEncodable(stepsText ?? ""),
                "calculation_steps": AnyEncodable(stepsText ?? ""),
                "originalQuery": AnyEncodable(food)
            ]

            // Reuse postRaw so we can decode event_id immediately
            struct AddEventResponse: Decodable {
                let ok: Bool
                let result: Inner
                struct Inner: Decodable { let event_id: String? }
            }
            let payload = DBClient.AddEventPayload(user_id: uid, event_type: "food_log", details: details)
            if let data = try? await DBClient.shared.postRaw("add_event", payload: payload),
               let res = try? JSONDecoder().decode(AddEventResponse.self, from: data),
               let eid = res.result.event_id,
               let idx = self.logs.firstIndex(where: { $0.id == newLog.id }) {

                // Patch eventId while preserving the rest
                let current = self.logs[idx]
                self.logs[idx] = FoodLog(
                    eventId: eid,
                    date: current.date,
                    food: current.food,
                    carbsText: current.carbsText,
                    serverResponse: current.serverResponse,
                    originalQuery: current.originalQuery
                )
            }
        }

        return newLog
    }

    // Delete locally + on DB (rollback on failure)
    func delete(_ log: FoodLog) {
        guard let idx = logs.firstIndex(where: { $0.id == log.id }) else { return }
        let removed = logs.remove(at: idx)

        Task {
            let uid = UserID.getOrCreate()
            // If we already have an eventId, delete remotely
            if let eid = removed.eventId {
                struct DeletePayload: Encodable { let user_id: String; let event_id: String }
                do {
                    _ = try await DBClient.shared.postRaw("delete_event",
                                                          payload: DeletePayload(user_id: uid, event_id: eid))
                } catch {
                    // rollback
                    logs.insert(removed, at: idx)
                    sendError = "Delete failed."
                }
            }
        }
    }

    // Start edit flow
    func beginEdit(_ log: FoodLog) { editing = log }

    /// Apply edited text:
    /// 1) Recompute via nutrition Lambda
    /// 2) Update DB details (keep timestamp)
    /// 3) Update row locally
    func applyEdit(foodText: String) {
        // Capture target & dismiss sheet immediately so it doesn't re-present
        guard let target = editing else { return }
        editing = nil

        isSending = true
        sendError = nil

        postFood(foodText) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false

                // Start with conservative defaults; we'll upgrade if parsing works
                var displayFood = foodText
                var carbs = "15g"
                var steps: String? = nil

                switch result {
                case .success(let response):
                    if let parsed = parseNutritionJSON(from: response) {
                        let norm = parsed.foods.map(normalizeFoodName)
                        if !norm.isEmpty { displayFood = norm.joined(separator: ", ") }
                        if let g = parsed.carbsG { carbs = String(format: "%.0fg", g) }
                        steps = parsed.steps
                    } else if let t = self.extractCarbText(from: response) {
                        let cleaned = t.replacingOccurrences(of: "carbs", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: " ", with: "")
                        carbs = cleaned.isEmpty ? "15g" : cleaned
                    }
                case .failure(let e):
                    // Show error but still let the user’s text change locally
                    self.sendError = e.localizedDescription
                }

                // Update DB if we have an eventId; keep original timestamp
                let uid = UserID.getOrCreate()
                if let eid = target.eventId {
                    let details: [String: AnyEncodable] = [
                        "food": AnyEncodable(displayFood),
                        "carbsText": AnyEncodable(carbs),
                        "total_carbs_g": AnyEncodable(Int(carbs.replacingOccurrences(of: "g", with: "")) ?? 0),
                        "serverResponse": AnyEncodable(steps ?? ""),
                        "calculation_steps": AnyEncodable(steps ?? ""),
                        "originalQuery": AnyEncodable(foodText)
                    ]
                    struct UpdatePayload: Encodable {
                        let user_id: String
                        let event_id: String
                        let details: [String: AnyEncodable]
                    }
                    Task {
                        do {
                            _ = try await DBClient.shared.postRaw(
                                "update_event",
                                payload: UpdatePayload(user_id: uid, event_id: eid, details: details)
                            )
                        } catch {
                            await MainActor.run { self.sendError = "Edit failed." }
                        }
                    }
                }

                // Update local row (same timestamp & eventId)
                if let idx = self.logs.firstIndex(where: { $0.id == target.id }) {
                    self.logs[idx] = FoodLog(
                        eventId: self.logs[idx].eventId,
                        date: self.logs[idx].date,
                        food: displayFood,
                        carbsText: carbs,
                        serverResponse: steps,
                        originalQuery: foodText
                    )
                }
            }
        }
    }


    // --- legacy helper kept for non-JSON responses (last-line / "…= 48 g") ---
    private func extractCarbText(from text: String?) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }

        if let lastLine = t.components(separatedBy: .newlines).reversed()
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            t = lastLine
        }

        let raw: String = {
            if let eq = t.range(of: "=", options: .backwards) {
                return String(t[eq.upperBound...])
            } else {
                return t
            }
        }()

        let uptoNewline = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw

        var cleaned = uptoNewline.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.isEmpty ? nil : cleaned
    }

    // Call your nutrition Lambda (Function URL variant)
    // Call your nutrition Lambda (Function URL variant)
    private func postFood(_ food: String, completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["body": food]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error)); return
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data else {
                completion(.failure(NSError(domain: "net", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                let status = obj?["statusCode"] as? Int ?? 0
                if status != 200 {
                    completion(.failure(NSError(domain: "http", code: status,
                        userInfo: [NSLocalizedDescriptionKey: "Bad status: \(status)"])))
                    return
                }
                if let body = obj?["body"] as? String {
                    print("🍱 RAW SERVER BODY (String):\n\(body)")
                    completion(.success(body))
                } else if let bodyDict = obj?["body"] as? [String: Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyDict)
                    let body = String(data: data2, encoding: .utf8) ?? ""
                    print("🍱 RAW SERVER BODY (Dict→String):\n\(body)")
                    completion(.success(body))
                } else if let bodyArr = obj?["body"] as? [Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyArr)
                    let body = String(data: data2, encoding: .utf8) ?? ""
                    print("🍱 RAW SERVER BODY (Array→String):\n\(body)")
                    completion(.success(body))
                } else {
                    // Nothing recognizable in "body"
                    if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        print("🍱 RAW SERVER BODY (Fallback-TopLevelString):\n\(raw)")
                        completion(.success(raw))  // <-- still let parser try
                    } else {
                        completion(.failure(NSError(domain: "parse", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Missing body"])))
                    }
                }
            } catch {
                // JSON parse of the *top-level* failed — try returning raw text anyway
                if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    print("🍱 RAW SERVER BODY (TopLevel RAW):\n\(raw)")
                    completion(.success(raw))      // <-- important change
                } else {
                    completion(.failure(error))
                }
            }
        }.resume()
    }


    // MARK: - Row date/time formatting
    private lazy var dfDate: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "EEE, MMM d"; return f
    }()
    private lazy var dfTime: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "h:mm a"; return f
    }()
    func dateString(_ d: Date) -> String { dfDate.string(from: d) }
    func timeString(_ d: Date) -> String { dfTime.string(from: d) }
}
