import Foundation
import UIKit

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

/// Keep quantities as-is; just trim whitespace.
private func normalizeFoodName(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
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
    @Published var logs: [FoodLog] = []
    @Published var isSending = false
    @Published var sendError: String?
    @Published var isLoading = false

    // Your nutrition inference Lambda (returns {statusCode, body})
    private let endpoint = URL(string: "https://5lcj2njvoq4urxszpj7lqoatxy0gslkf.lambda-url.us-west-2.on.aws/")!
    
    // Track whether we've already loaded history from server this app session
    private var hasLoadedInitialHistory = false
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - History / initial load

    func ensureInitialHistoryLoaded() {
        // 1) Always try local cache first (fast, robust)
        if !hasLoadedInitialHistory && logs.isEmpty {
            let cached = FoodLogStore.shared.load()
            if !cached.isEmpty {
                self.logs = cached.sorted { $0.date > $1.date }
                // Start prefetch for cached logs
                prefetchRecentImages()
            }
        }

        // 2) Then, once per app session, refresh from server
        guard !hasLoadedInitialHistory else { return }
        hasLoadedInitialHistory = true
        loadHistory()
    }

    func loadHistory() {
        let uid = UserID.getOrCreate()
        isLoading = true
        Task {
            do {
                let events = try await DBClient.shared.getEvents(userId: uid, limit: 200)
                let mapped = events.compactMap { $0.toFoodLog() }
                await MainActor.run {
                    self.logs = mapped.sorted { $0.date > $1.date }
                    FoodLogStore.shared.save(self.logs)
                }
                // Pre-warm images for the most recent logs (background)
                prefetchRecentImages()
                await MainActor.run {
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sendError = "History fetch failed."
                    self.isLoading = false
                    // keep local cache as-is
                }
            }
        }
    }

    // MARK: - Submit new meal (legacy text box)

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
                    _ = self.addLocal(food: trimmed, response: responseText, image: nil)
                case .failure(let err):
                    self.sendError = err.localizedDescription
                    _ = self.addLocal(food: trimmed, response: nil, image: nil)
                }
            }
        }
    }

    // MARK: - Local add + persist + server add_event (with optional image)

    @discardableResult
    func addLocal(food: String, response: String?, image: UIImage? = nil) -> FoodLog {
        var displayFood = food
        var carbsDisplay = "15g"
        var stepsText: String? = nil

        if let response, let parsed = parseNutritionJSON(from: response) {
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
            let cleaned = t
                .replacingOccurrences(of: "carbs", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " ", with: "")
            carbsDisplay = cleaned.isEmpty ? "15g" : cleaned
        }

        // Initial log (no eventId yet)
        var newLog = FoodLog(
            eventId: nil,
            date: Date(),
            food: displayFood,
            carbsText: carbsDisplay,
            serverResponse: stepsText,
            originalQuery: food
        )

        // --- image handling ---
        var localFilename: String? = nil
        if let image {
            localFilename = FoodImageStore.shared.saveSquareImage(image, for: newLog.id)
        }

        newLog = FoodLog(
            id: newLog.id,
            eventId: nil,
            date: newLog.date,
            food: displayFood,
            carbsText: carbsDisplay,
            serverResponse: stepsText,
            originalQuery: food,
            imageS3URL: nil,
            localImageFilename: localFilename
        )

        logs.append(newLog)
        logs.sort { $0.date > $1.date }
        FoodLogStore.shared.save(logs)

        // Persist to DB
        let uid = UserID.getOrCreate()
        Task {
            let iso = isoFormatter.string(from: newLog.date)

            // (1) optionally upload image to S3 to get a URL
            var imageURLString: String? = nil
            if let image, localFilename != nil {
                do {
                    let url = try await uploadImageToS3(image: image)
                    imageURLString = url.absoluteString
                } catch {
                    print("⚠️ Image upload failed:", error)
                }
            }

            var details: [String: AnyEncodable] = [
                "food": AnyEncodable(displayFood),
                "carbsText": AnyEncodable(carbsDisplay),
                "total_carbs_g": AnyEncodable(Int(carbsDisplay.replacingOccurrences(of: "g", with: "")) ?? 0),
                "serverResponse": AnyEncodable(stepsText ?? ""),
                "calculation_steps": AnyEncodable(stepsText ?? ""),
                "originalQuery": AnyEncodable(food),
                "timestampISO": AnyEncodable(iso)
            ]
            if let imageURLString, !imageURLString.isEmpty {
                details["image_s3_url"] = AnyEncodable(imageURLString)
            }

            struct AddEventResponse: Decodable {
                let ok: Bool
                let result: Inner
                struct Inner: Decodable { let event_id: String? }
            }

            let payload = DBClient.AddEventPayload(
                user_id: uid,
                event_type: "food_log",
                details: details
            )

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
                    originalQuery: current.originalQuery,
                    imageS3URL: imageURLString ?? current.imageS3URL,
                    localImageFilename: current.localImageFilename
                )
                FoodLogStore.shared.save(self.logs)
            }
        }

        return newLog
    }

    // MARK: - Edit existing log

    func applyEdit(for target: FoodLog, newFood: String, newDate: Date) {
        let trimmed = newFood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = logs.firstIndex(where: { $0.id == target.id }) else { return }

        let original = logs[idx]
        let dateChanged = abs(original.date.timeIntervalSince(newDate)) > 1.0
        let foodChanged = trimmed != original.originalQuery

        func makeDetails(food: String,
                         carbsText: String,
                         steps: String?,
                         originalQuery: String,
                         date: Date,
                         imageS3URL: String?) -> [String: AnyEncodable] {
            let iso = isoFormatter.string(from: date)
            let totalCarbs = Int(carbsText.replacingOccurrences(of: "g", with: "")) ?? 0
            var dict: [String: AnyEncodable] = [
                "food": AnyEncodable(food),
                "carbsText": AnyEncodable(carbsText),
                "total_carbs_g": AnyEncodable(totalCarbs),
                "serverResponse": AnyEncodable(steps ?? ""),
                "calculation_steps": AnyEncodable(steps ?? ""),
                "originalQuery": AnyEncodable(originalQuery),
                "timestampISO": AnyEncodable(iso)
            ]
            if let imageS3URL, !imageS3URL.isEmpty {
                dict["image_s3_url"] = AnyEncodable(imageS3URL)
            }
            return dict
        }

        // Case 1: only time changed
        if !foodChanged && dateChanged {
            let updated = FoodLog(
                id: original.id,
                eventId: original.eventId,
                date: newDate,
                food: original.food,
                carbsText: original.carbsText,
                serverResponse: original.serverResponse,
                originalQuery: original.originalQuery,
                imageS3URL: original.imageS3URL,
                localImageFilename: original.localImageFilename
            )
            logs[idx] = updated
            logs.sort { $0.date > $1.date }
            FoodLogStore.shared.save(logs)

            if let eid = updated.eventId {
                let uid = UserID.getOrCreate()
                let details = makeDetails(food: updated.food,
                                          carbsText: updated.carbsText,
                                          steps: updated.serverResponse,
                                          originalQuery: updated.originalQuery,
                                          date: updated.date,
                                          imageS3URL: updated.imageS3URL)
                Task {
                    do {
                        try await DBClient.shared.updateEvent(userId: uid, eventId: eid, details: details)
                    } catch {
                        await MainActor.run { self.sendError = "Edit (time) failed." }
                    }
                }
            }
            return
        }

        // Case 2: meal text changed (with or without time change)
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
                    self.sendError = e.localizedDescription
                }

                let updated = FoodLog(
                    id: original.id,
                    eventId: original.eventId,
                    date: dateChanged ? newDate : original.date,
                    food: displayFood,
                    carbsText: carbs,
                    serverResponse: steps,
                    originalQuery: trimmed,
                    imageS3URL: original.imageS3URL,
                    localImageFilename: original.localImageFilename
                )

                if let j = self.logs.firstIndex(where: { $0.id == original.id }) {
                    self.logs[j] = updated
                    self.logs.sort { $0.date > $1.date }
                    FoodLogStore.shared.save(self.logs)
                }

                if let eid = updated.eventId {
                    let uid = UserID.getOrCreate()
                    let details = makeDetails(food: updated.food,
                                              carbsText: updated.carbsText,
                                              steps: updated.serverResponse,
                                              originalQuery: updated.originalQuery,
                                              date: updated.date,
                                              imageS3URL: updated.imageS3URL)
                    Task {
                        do {
                            try await DBClient.shared.updateEvent(userId: uid, eventId: eid, details: details)
                        } catch {
                            await MainActor.run { self.sendError = "Edit failed." }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Delete

    func delete(_ log: FoodLog) {
        guard let idx = logs.firstIndex(where: { $0.id == log.id }) else { return }
        let removed = logs.remove(at: idx)
        logs.sort { $0.date > $1.date }
        FoodLogStore.shared.save(logs)

        Task {
            let uid = UserID.getOrCreate()
            if let eid = removed.eventId {
                struct DeletePayload: Encodable { let user_id: String; let event_id: String }
                do {
                    _ = try await DBClient.shared.postRaw("delete_event",
                                                          payload: DeletePayload(user_id: uid, event_id: eid))
                } catch {
                    // rollback
                    logs.insert(removed, at: idx)
                    logs.sort { $0.date > $1.date }
                    FoodLogStore.shared.save(logs)
                    sendError = "Delete failed."
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
                    completion(.success(body))
                } else if let bodyDict = obj?["body"] as? [String: Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyDict)
                    let body = String(data: data2, encoding: .utf8) ?? ""
                    completion(.success(body))
                } else if let bodyArr = obj?["body"] as? [Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyArr)
                    let body = String(data: data2, encoding: .utf8) ?? ""
                    completion(.success(body))
                } else {
                    if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        completion(.success(raw))
                    } else {
                        completion(.failure(NSError(domain: "parse", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Missing body"])))
                    }
                }
            } catch {
                if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    completion(.success(raw))
                } else {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Image upload via Lambda pre-signed URL

    /// Upload a square-cropped image to S3 (via your backend) and return its URL.
    func uploadImageToS3(image: UIImage) async throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ImageUpload", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"])
        }

        struct GetUploadURLPayload: Encodable {
            let user_id: String
            let filename: String
            let content_type: String
        }

        struct GetUploadURLResponse: Decodable {
            let ok: Bool
            let upload_url: String?
            let public_url: String?
            let error: String?
        }

        let uid = UserID.getOrCreate()
        let filename = UUID().uuidString + ".jpg"

        let payload = GetUploadURLPayload(
            user_id: uid,
            filename: filename,
            content_type: "image/jpeg"
        )

        // Step 1: ask Lambda for URLs
        let dataResp = try await DBClient.shared.postRaw("get_image_upload_url", payload: payload)
        let decoded = try JSONDecoder().decode(GetUploadURLResponse.self, from: dataResp)

        guard decoded.ok,
              let uploadURLString = decoded.upload_url,
              let publicURLString = decoded.public_url,
              let uploadURL = URL(string: uploadURLString),
              let publicURL = URL(string: publicURLString) else {
            let msg = decoded.error ?? "Could not get upload URL"
            throw NSError(domain: "ImageUpload", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // Step 2: PUT to S3 directly from the app
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw NSError(domain: "ImageUpload", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "S3 upload failed with \(http.statusCode)"])
        }

        // Step 3: return the public URL to be stored as image_s3_url
        return publicURL
    }

    // MARK: - Background image prefetch (for latest logs)

    /// Prefetch images for the most recent `limit` logs in the background.
    /// Uses the on-disk cache if present; otherwise downloads from S3.
    func prefetchRecentImages(limit: Int = 20) {
        // Snapshot to avoid race with logs mutation
        let snapshot = logs.sorted { $0.date > $1.date }
        let slice = Array(snapshot.prefix(limit))

        for log in slice {
            // Already cached locally?
            if FoodImageStore.shared.loadLocalImage(for: log) != nil {
                continue
            }
            // Only try if we have an S3 URL
            guard log.imageS3URL != nil else { continue }

            Task.detached {
                FoodImageStore.shared.loadOrDownloadImage(for: log) { _ in
                    // We don't need to update any UI here;
                    // thumbnail and grid views will use the cache when displayed.
                }
            }
        }
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
