import Foundation
import SwiftUI
import HealthKit

@MainActor
final class Page1ViewModel: ObservableObject {
    // UI state
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var uploadStatus: String?

    // Metrics (today)
    @Published var steps: Int = 0
    @Published var activeEnergyKcal: Int = 0
    @Published var carbsG: Double = 0
    @Published var exerciseMin: Int = 0
    @Published var heartRateBPM: Int = 0        // daily average BPM
    @Published var glucoseMgdl: Int = 0         // daily average mg/dL
    @Published var insulinIU: Double = 0

    // Demo counter
    @Published var count: Int = 0
    func increment() { count += 1 }

    private let hk = HealthKitManager()

    // MARK: - Lifecycle

    func initialize() {
        isLoading = true
        errorMessage = nil

        // Create user record on first run (idempotent on server)
        Task { [weak self] in
            let uid = UserID.getOrCreate()
            do {
                try await DBClient.shared.createUser(userId: uid)
                print("✅ User created on Lambda: \(uid)")
            } catch {
                print("⚠️ Failed to register user: \(error)")
                // Optionally surface to UI:
                // self?.errorMessage = "Registration failed"
            }
        }

        hk.requestAuthorization { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                if success {
                    self.loadAllToday()
                } else {
                    self.errorMessage = "Health authorization not granted."
                    self.isLoading = false
                }
            }
        }
    }

    func refresh() { loadAllToday() }

    // MARK: - Today snapshot

    private func loadAllToday() {
        isLoading = true
        errorMessage = nil

        let group = DispatchGroup()
        var firstError: Error?

        func capture<T>(_ result: Result<T, Error>, onSuccess: (T) -> Void) {
            switch result {
            case .success(let v): onSuccess(v)
            case .failure(let e): if firstError == nil { firstError = e }
            }
        }

        // Steps (count)
        group.enter()
        hk.fetchTodaySum(.stepCount, unit: .count()) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.steps = Int($0) }
                group.leave()
            }
        }

        // Active Energy (kcal)
        group.enter()
        hk.fetchTodaySum(.activeEnergyBurned, unit: .kilocalorie()) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.activeEnergyKcal = Int($0.rounded()) }
                group.leave()
            }
        }

        // Carbohydrates (grams)
        group.enter()
        hk.fetchTodaySum(.dietaryCarbohydrates, unit: .gram()) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.carbsG = Double(round(10 * $0) / 10) } // 0.1g
                group.leave()
            }
        }

        // Exercise minutes
        group.enter()
        hk.fetchTodaySum(.appleExerciseTime, unit: .minute()) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.exerciseMin = Int($0.rounded()) }
                group.leave()
            }
        }

        // Heart rate (avg BPM today)
        group.enter()
        hk.fetchTodayAverage(.heartRate, unit: HKUnit.count().unitDivided(by: .minute())) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.heartRateBPM = Int($0.rounded()) }
                group.leave()
            }
        }

        // Blood glucose (avg mg/dL today)
        group.enter()
        hk.fetchTodayAverage(.bloodGlucose, unit: HKUnit(from: "mg/dL")) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.glucoseMgdl = Int($0.rounded()) }
                group.leave()
            }
        }

        // Insulin (IU sum today)
        group.enter()
        hk.fetchTodaySum(.insulinDelivery, unit: .internationalUnit()) { [weak self] result in
            DispatchQueue.main.async {
                capture(result) { self?.insulinIU = Double(round(10 * $0) / 10) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isLoading = false
            if let e = firstError { self.errorMessage = e.localizedDescription }
        }
    }

    // MARK: - (Legacy) local JSON payload builder (kept for reference / future use)

    private struct HealthUploadPayload: Encodable {
        let dateISO8601: String
        let steps: Int
        let activeEnergyKcal: Int
        let carbsG: Double
        let exerciseMin: Int
        let heartRateBPM: Int
        let glucoseMgdl: Int
        let insulinIU: Double
    }

    func buildPayload() -> Data? {
        let payload = HealthUploadPayload(
            dateISO8601: ISO8601DateFormatter().string(from: Date()),
            steps: steps,
            activeEnergyKcal: activeEnergyKcal,
            carbsG: carbsG,
            exerciseMin: exerciseMin,
            heartRateBPM: heartRateBPM,
            glucoseMgdl: glucoseMgdl,
            insulinIU: insulinIU
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        return try? enc.encode(payload)
    }

    // MARK: - Upload last 365 days (batch → Lambda → Mongo)

    func uploadLastYearHealth(completion: @escaping (Result<Void, Error>) -> Void) {
        uploadStatus = "Preparing last year's data…"
        let uid = UserID.getOrCreate()
        let today = Calendar.current.startOfDay(for: Date())

        // Build last 365 days, oldest → newest
        let dates: [Date] = stride(from: 0, through: 365, by: 1).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }.reversed()

        var summaries: [DBClient.HealthSummary] = []
        let group = DispatchGroup()
        var firstError: Error?

        for day in dates {
            group.enter()
            hk.dailySummary(for: day) { result in
                switch result {
                case .success(let s): summaries.append(s)
                case .failure(let e): if firstError == nil { firstError = e }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let e = firstError {
                self.uploadStatus = "Failed to read HealthKit."
                completion(.failure(e))
                return
            }
            // Chunk to avoid very large payloads
            let chunks = summaries.chunked(into: 100)  // ~100 days per request
            Task { @MainActor in
                do {
                    for (i, chunk) in chunks.enumerated() {
                        self.uploadStatus = "Uploading… (\(i + 1)/\(chunks.count))"
                        try await DBClient.shared.uploadHealthBatch(userId: uid, summaries: Array(chunk))
                    }
                    self.uploadStatus = "Upload complete."
                    completion(.success(()))
                } catch {
                    self.uploadStatus = "Upload failed."
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Small utility

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }
        return stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
