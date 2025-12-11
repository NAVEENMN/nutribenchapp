import Foundation
import UIKit

@MainActor
final class Page2ViewModel: ObservableObject {
    @Published var logs: [FoodLog] = []
    @Published var isSending = false
    @Published var sendError: String?
    @Published var isLoading = false

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
                let serverLogs = events.compactMap { $0.toFoodLog() }

                await MainActor.run {
                    // Local logs (from Core Data or the in-memory state) may contain:
                    // - pending entries with eventId == nil
                    // - older cached entries we haven't synced yet
                    let localLogs = self.logs.isEmpty
                        ? FoodLogStore.shared.load()
                        : self.logs

                    // Keep local logs that were never assigned an eventId (pending sync).
                    let pendingLocal = localLogs.filter { $0.eventId == nil }

                    // Server logs are the source of truth for synced entries.
                    var merged = serverLogs
                    merged.append(contentsOf: pendingLocal)

                    // Sort newest → oldest
                    merged.sort { $0.date > $1.date }

                    self.logs = merged
                    FoodLogStore.shared.save(self.logs)
                    self.isLoading = false
                }

                // Pre-warm images for the most recent logs (background)
                prefetchRecentImages()
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

        Task { [weak self] in
            guard let self else { return }
            do {
                let responseText = try await NutritionService.shared.estimate(for: trimmed)
                self.isSending = false
                _ = self.addLocal(food: trimmed, response: responseText, image: nil)
            } catch {
                self.isSending = false
                self.sendError = error.localizedDescription
                _ = self.addLocal(food: trimmed, response: nil, image: nil)
            }
        }
    }

    // MARK: - Local add + persist + server add_event (with optional image)

    @discardableResult
    func addLocal(food: String, response: String?, image: UIImage? = nil) -> FoodLog {
        var displayFood = food
        var carbsDisplay = "15g"
        var stepsText: String? = nil

        if let response, let parsed = NutritionParser.parse(from: response) {
            if !parsed.foods.isEmpty {
                displayFood = parsed.foods.joined(separator: ", ")
            }
            if let g = parsed.carbsG {
                carbsDisplay = String(format: "%.0fg", g)
            }
            stepsText = parsed.steps
        } else if let t = NutritionParser.extractCarbText(from: response) {
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
                    let url = try await ImageUploadService.shared.uploadImage(image: image)
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

        Task { [weak self] in
            guard let self else { return }

            var displayFood = trimmed
            var carbs = original.carbsText
            var steps: String? = original.serverResponse

            do {
                let response = try await NutritionService.shared.estimate(for: trimmed)

                if let parsed = NutritionParser.parse(from: response) {
                    if !parsed.foods.isEmpty {
                        displayFood = parsed.foods.joined(separator: ", ")
                    }
                    if let g = parsed.carbsG {
                        carbs = String(format: "%.0fg", g)
                    }
                    steps = parsed.steps
                } else if let t = NutritionParser.extractCarbText(from: response) {
                    let cleaned = t
                        .replacingOccurrences(of: "carbs", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: " ", with: "")
                    carbs = cleaned.isEmpty ? "15g" : cleaned
                }
            } catch {
                self.sendError = error.localizedDescription
                // Fall back to using original carbs/steps
            }

            self.isSending = false

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
                let details = makeDetails(
                    food: updated.food,
                    carbsText: updated.carbsText,
                    steps: updated.serverResponse,
                    originalQuery: updated.originalQuery,
                    date: updated.date,
                    imageS3URL: updated.imageS3URL
                )
                do {
                    try await DBClient.shared.updateEvent(userId: uid, eventId: eid, details: details)
                } catch {
                    self.sendError = "Edit failed."
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

