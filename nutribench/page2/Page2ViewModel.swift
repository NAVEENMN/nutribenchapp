import Foundation

// MARK: - Helpers to unwrap/clean server text

/// If the server body is a JSON-encoded *string* (e.g. "\"{\\\"food_items\\\":...}\""),
/// decode it once to get the inner JSON text.
private func unwrapJSONStringOnce(_ s: String) -> String {
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
        print("❌ parseNutritionJSON – failed to decode JSON")
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

    print("🧩 parseNutritionJSON – foods=\(foods), carbsG=\(String(describing: carbsG)), steps.isNil=\(steps == nil)")
    return ParsedNutrition(foods: foods, carbsG: carbsG, steps: steps)
}

private func normalizeFoodName(_ s: String) -> String {
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func numberFromAny(_ any: Any?) -> Double? {
    switch any {
    case let d as Double: return d
    case let i as Int:    return Double(i)
    case let s as String:
        if let d = Double(s) { return d }
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
    @Published var logs: [FoodLog] = [] {
        didSet {
            print("📚 logs didSet – new count=\(logs.count)")
        }
    }
    @Published var isSending = false {
        didSet { print("📨 isSending=\(isSending)") }
    }
    @Published var sendError: String? {
        didSet { if let e = sendError { print("❗ sendError set: \(e)") } }
    }
    @Published var isLoading = false {
        didSet { print("⏳ isLoading=\(isLoading)") }
    }

    // Your nutrition inference Lambda (returns {statusCode, body})
    private let endpoint = URL(string: "https://5lcj2njvoq4urxszpj7lqoatxy0gslkf.lambda-url.us-west-2.on.aws/")!
    
    // Track whether we've already loaded history from server this app session
    private var hasLoadedInitialHistory = false

    init() {
        print("🔥 Page2ViewModel.init – new instance created")
    }
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - History / initial load

    func ensureInitialHistoryLoaded() {
        print("📥 ensureInitialHistoryLoaded – hasLoadedInitialHistory=\(hasLoadedInitialHistory), logs.count=\(logs.count)")

        // 1) Always try local cache first (fast, robust)
        if !hasLoadedInitialHistory && logs.isEmpty {
            let cached = FoodLogStore.shared.load()
            print("📄 loaded cached logs from disk: \(cached.count)")
            if !cached.isEmpty {
                self.logs = cached.sorted { $0.date > $1.date }
                print("📄 after assigning cached logs, logs.count=\(self.logs.count)")
            }
        }

        // 2) Then, once per app session, refresh from server
        guard !hasLoadedInitialHistory else {
            print("📥 ensureInitialHistoryLoaded – already loaded, returning")
            return
        }
        hasLoadedInitialHistory = true
        print("🌐 ensureInitialHistoryLoaded – calling loadHistory()")
        loadHistory()
    }

    func loadHistory() {
        let uid = UserID.getOrCreate()
        print("🌐 loadHistory – start for user_id=\(uid)")
        isLoading = true
        Task {
            do {
                let events = try await DBClient.shared.getEvents(userId: uid, limit: 200)
                let mapped = events.compactMap { $0.toFoodLog() }
                await MainActor.run {
                    print("🌐 loadHistory – server events=\(events.count), mapped foodLogs=\(mapped.count)")
                    self.logs = mapped.sorted { $0.date > $1.date }
                    self.isLoading = false
                    FoodLogStore.shared.save(self.logs)
                    print("🌐 loadHistory – done, logs.count=\(self.logs.count)")
                }
            } catch {
                await MainActor.run {
                    print("❌ loadHistory failed: \(error)")
                    self.sendError = "History fetch failed."
                    self.isLoading = false
                    // keep local cache as-is
                }
            }
        }
    }

    // MARK: - Submit new meal

    func submit(food: String) {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🍽 submit(food:) called with '\(food)' trimmed='\(trimmed)'")
        guard !trimmed.isEmpty else {
            print("❌ submit – trimmed text is empty, ignoring")
            return
        }

        isSending = true
        sendError = nil

        postFood(trimmed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false
                switch result {
                case .success(let responseText):
                    print("🍽 submit – postFood success, adding local log")
                    _ = self.addLocal(food: trimmed, response: responseText)
                case .failure(let err):
                    print("❌ submit – postFood failed: \(err)")
                    self.sendError = err.localizedDescription
                    _ = self.addLocal(food: trimmed, response: nil)
                }
            }
        }
    }

    // MARK: - Local add + persist + server add_event

    @discardableResult
    func addLocal(food: String, response: String?) -> FoodLog {
        print("➕ addLocal – food='\(food)', hasResponse=\(response != nil)")
        var displayFood = food
        var carbsDisplay = "15g"
        var stepsText: String? = nil

        if let response, let parsed = parseNutritionJSON(from: response) {
            print("➕ addLocal – using parsed nutrition")
            if !parsed.foods.isEmpty {
                displayFood = parsed.foods
                    .map(normalizeFoodName)
                    .joined(separator: ", ")
            }
            if let g = parsed.carbsG {
                carbsDisplay = String(format: "%.0fg", g)
            }
            stepsText = parsed.steps
        } else if let t = extractCarbText(from: response) {
            print("➕ addLocal – using legacy carb extractor")
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
            serverResponse: stepsText,
            originalQuery: food
        )

        print("➕ addLocal – appending newLog id=\(newLog.id) food='\(newLog.food)' carbs='\(newLog.carbsText)'")
        logs.append(newLog)
        logs.sort { $0.date > $1.date }
        FoodLogStore.shared.save(logs)
        print("➕ addLocal – after append, logs.count=\(logs.count)")

        // Persist to DB
        let uid = UserID.getOrCreate()
        Task {
            let iso = isoFormatter.string(from: newLog.date)
            let details: [String: AnyEncodable] = [
                "food": AnyEncodable(displayFood),
                "carbsText": AnyEncodable(carbsDisplay),
                "total_carbs_g": AnyEncodable(Int(carbsDisplay.replacingOccurrences(of: "g", with: "")) ?? 0),
                "serverResponse": AnyEncodable(stepsText ?? ""),
                "calculation_steps": AnyEncodable(stepsText ?? ""),
                "originalQuery": AnyEncodable(food),
                "timestampISO": AnyEncodable(iso)
            ]

            struct AddEventResponse: Decodable {
                let ok: Bool
                let result: Inner
                struct Inner: Decodable { let event_id: String? }
            }
            let payload = DBClient.AddEventPayload(user_id: uid, event_type: "food_log", details: details)
            print("➕ addLocal – sending add_event to server for id=\(newLog.id)")
            if let data = try? await DBClient.shared.postRaw("add_event", payload: payload),
               let res = try? JSONDecoder().decode(AddEventResponse.self, from: data),
               let eid = res.result.event_id,
               let idx = self.logs.firstIndex(where: { $0.id == newLog.id }) {

                let current = self.logs[idx]
                self.logs[idx] = FoodLog(
                    id: current.id,
                    eventId: eid,
                    date: current.date,
                    food: current.food,
                    carbsText: current.carbsText,
                    serverResponse: current.serverResponse,
                    originalQuery: current.originalQuery
                )
                FoodLogStore.shared.save(self.logs)
                print("➕ addLocal – server event_id attached to id=\(current.id) eid=\(eid)")
            } else {
                print("⚠️ addLocal – failed to decode add_event response or find log index")
            }
        }

        return newLog
    }

    // MARK: - Edit existing log

    /// Edit an existing FoodLog.
    /// - If only the timestamp changes → update date locally + on server (no nutribench call).
    /// - If meal text changes (with or without timestamp change) → recompute via nutribench and update DB.
    func applyEdit(for target: FoodLog, newFood: String, newDate: Date) {
        print("✏️ applyEdit – target.id=\(target.id) target.food='\(target.food)' newFood='\(newFood)' newDate=\(newDate)")
        let trimmed = newFood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("✏️ applyEdit – trimmed text is empty, abort")
            return
        }
        guard let idx = logs.firstIndex(where: { $0.id == target.id }) else {
            print("✏️ applyEdit – target not found in logs")
            return
        }

        let original = logs[idx]
        let dateChanged = abs(original.date.timeIntervalSince(newDate)) > 1.0
        let foodChanged = trimmed != original.originalQuery
        print("✏️ applyEdit – dateChanged=\(dateChanged) foodChanged=\(foodChanged)")

        func makeDetails(food: String, carbsText: String, steps: String?, originalQuery: String, date: Date) -> [String: AnyEncodable] {
            let iso = isoFormatter.string(from: date)
            let totalCarbs = Int(carbsText.replacingOccurrences(of: "g", with: "")) ?? 0
            return [
                "food": AnyEncodable(food),
                "carbsText": AnyEncodable(carbsText),
                "total_carbs_g": AnyEncodable(totalCarbs),
                "serverResponse": AnyEncodable(steps ?? ""),
                "calculation_steps": AnyEncodable(steps ?? ""),
                "originalQuery": AnyEncodable(originalQuery),
                "timestampISO": AnyEncodable(iso)
            ]
        }

        // Case 1: only time changed
        if !foodChanged && dateChanged {
            print("✏️ applyEdit – only date changed, updating locally and server")
            let updated = FoodLog(
                id: original.id,
                eventId: original.eventId,
                date: newDate,
                food: original.food,
                carbsText: original.carbsText,
                serverResponse: original.serverResponse,
                originalQuery: original.originalQuery
            )
            logs[idx] = updated
            logs.sort { $0.date > $1.date }
            FoodLogStore.shared.save(logs)
            print("✏️ applyEdit – time-only update done, logs.count=\(logs.count)")

            if let eid = updated.eventId {
                let uid = UserID.getOrCreate()
                let details = makeDetails(food: updated.food,
                                          carbsText: updated.carbsText,
                                          steps: updated.serverResponse,
                                          originalQuery: updated.originalQuery,
                                          date: updated.date)
                Task {
                    do {
                        try await DBClient.shared.updateEvent(userId: uid, eventId: eid, details: details)
                        print("✏️ applyEdit – time-only update_event succeeded for eid=\(eid)")
                    } catch {
                        await MainActor.run {
                            print("❌ applyEdit – time-only update_event failed: \(error)")
                            self.sendError = "Edit (time) failed."
                        }
                    }
                }
            }
            return
        }

        // Case 2: meal text changed (with or without time change)
        print("✏️ applyEdit – meal text changed, calling postFood")
        isSending = true
        sendError = nil

        postFood(trimmed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false

                var displayFood = trimmed
                var carbs = original.carbsText
                var steps: String? = original.serverResponse

                switch result {
                case .success(let response):
                    print("✏️ applyEdit – postFood success")
                    if let parsed = parseNutritionJSON(from: response) {
                        let norm = parsed.foods.map(normalizeFoodName)
                        if !norm.isEmpty { displayFood = norm.joined(separator: ", ") }
                        if let g = parsed.carbsG { carbs = String(format: "%.0fg", g) }
                        steps = parsed.steps
                    } else if let t = self.extractCarbText(from: response) {
                        let cleaned = t
                            .replacingOccurrences(of: "carbs", with: "", options: .caseInsensitive)
                            .replacingOccurrences(of: " ", with: "")
                        carbs = cleaned.isEmpty ? "15g" : cleaned
                    }
                case .failure(let e):
                    print("❌ applyEdit – postFood failed: \(e)")
                    self.sendError = e.localizedDescription
                }

                let updated = FoodLog(
                    id: original.id,
                    eventId: original.eventId,
                    date: dateChanged ? newDate : original.date,
                    food: displayFood,
                    carbsText: carbs,
                    serverResponse: steps,
                    originalQuery: trimmed
                )

                if let j = self.logs.firstIndex(where: { $0.id == original.id }) {
                    self.logs[j] = updated
                    self.logs.sort { $0.date > $1.date }
                    FoodLogStore.shared.save(self.logs)
                    print("✏️ applyEdit – updated local log for id=\(updated.id)")
                } else {
                    print("❌ applyEdit – could not find log index during update")
                }

                if let eid = updated.eventId {
                    let uid = UserID.getOrCreate()
                    let details = makeDetails(food: updated.food,
                                              carbsText: updated.carbsText,
                                              steps: updated.serverResponse,
                                              originalQuery: updated.originalQuery,
                                              date: updated.date)
                    Task {
                        do {
                            try await DBClient.shared.updateEvent(userId: uid, eventId: eid, details: details)
                            print("✏️ applyEdit – update_event succeeded for eid=\(eid)")
                        } catch {
                            await MainActor.run {
                                print("❌ applyEdit – update_event failed: \(error)")
                                self.sendError = "Edit failed."
                            }
                        }
                    }
                } else {
                    print("✏️ applyEdit – no eventId, skipping server update")
                }
            }
        }
    }

    // MARK: - Delete

    func delete(_ log: FoodLog) {
        print("🗑 delete – called for id=\(log.id) food='\(log.food)'")
        guard let idx = logs.firstIndex(where: { $0.id == log.id }) else {
            print("🗑 delete – target not found in logs")
            return
        }

        // Optimistically remove from local list
        let removed = logs.remove(at: idx)
        print("🗑 delete – removed from logs at index \(idx). logs.count now=\(logs.count)")
        logs.sort { $0.date > $1.date }
        FoodLogStore.shared.save(logs)

        Task {
            let uid = UserID.getOrCreate()
            guard let eid = removed.eventId else {
                print("🗑 delete – removed log had no eventId, skipping server delete")
                return
            }

            struct DeletePayload: Encodable { let user_id: String; let event_id: String }

            do {
                print("🗑 delete – sending delete_event to server for eid=\(eid)")
                _ = try await DBClient.shared.postRaw(
                    "delete_event",
                    payload: DeletePayload(user_id: uid, event_id: eid)
                )
                print("🗑 delete – server delete_event succeeded for eid=\(eid)")
            } catch {
                // Roll back on the main actor if server delete fails
                await MainActor.run {
                    print("❌ delete – server delete_event failed, rolling back: \(error)")
                    self.logs.insert(removed, at: idx)
                    self.logs.sort { $0.date > $1.date }
                    FoodLogStore.shared.save(self.logs)
                    self.sendError = "Delete failed."
                }
            }
        }
    }

    // MARK: - Legacy carb extractor

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

    // MARK: - Network call to nutrition Lambda

    private func postFood(_ food: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("🌐 postFood – sending request for food='\(food)'")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["body": food]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("❌ postFood – JSON encode error: \(error)")
            completion(.failure(error)); return
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                print("❌ postFood – network error: \(err)")
                completion(.failure(err)); return
            }
            guard let data else {
                print("❌ postFood – empty response data")
                completion(.failure(NSError(domain: "net", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                let status = obj?["statusCode"] as? Int ?? 0
                print("🌐 postFood – statusCode=\(status)")
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
                    if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        print("🍱 RAW SERVER BODY (Fallback-TopLevelString):\n\(raw)")
                        completion(.success(raw))
                    } else {
                        print("❌ postFood – Missing body in response")
                        completion(.failure(NSError(domain: "parse", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Missing body"])))
                    }
                }
            } catch {
                if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    print("🍱 RAW SERVER BODY (TopLevel RAW):\n\(raw)")
                    completion(.success(raw))
                } else {
                    print("❌ postFood – JSON parse error: \(error)")
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
