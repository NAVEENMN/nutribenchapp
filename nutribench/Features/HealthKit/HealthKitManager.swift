import Foundation
import HealthKit

enum HealthKitError: Error {
    case notAvailable
    case dataTypeUnavailable(String)
}

struct GlucosePoint: Identifiable {
    let id = UUID()
    let date: Date
    let mgdl: Double
}

final class HealthKitManager {
    fileprivate let store = HKHealthStore()

    // Call once to ask for read access to everything we need
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, HealthKitError.notAvailable); return
        }

        // Quantity types we need
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .dietaryCarbohydrates,
            .appleExerciseTime,
            .heartRate,
            .bloodGlucose,
            .insulinDelivery
        ]

        var readTypes = Set<HKObjectType>()
        for id in ids {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                readTypes.insert(t)
            }
        }

        store.requestAuthorization(toShare: [], read: readTypes) { success, error in
            completion(success, error)
        }
    }

    // MARK: - Queries (iOS 14 closures)

    /// Sum of a cumulative quantity for "today"
    func fetchTodaySum(_ id: HKQuantityTypeIdentifier,
                       unit: HKUnit,
                       completion: @escaping (Result<Double, Error>) -> Void) {

        guard let type = HKObjectType.quantityType(forIdentifier: id) else {
            completion(.failure(HealthKitError.dataTypeUnavailable(id.rawValue))); return
        }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let q = HKStatisticsQuery(quantityType: type,
                                  quantitySamplePredicate: predicate,
                                  options: .cumulativeSum) { _, stats, error in
            if let _ = error {
                // Treat HK "no data" as 0 for UX
                completion(.success(0)); return
            }
            let v = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
            completion(.success(v))
        }
        store.execute(q)
    }

    /// Average of a discrete quantity for "today" (e.g., heart rate, glucose)
    func fetchTodayAverage(_ id: HKQuantityTypeIdentifier,
                           unit: HKUnit,
                           completion: @escaping (Result<Double, Error>) -> Void) {

        guard let type = HKObjectType.quantityType(forIdentifier: id) else {
            completion(.failure(HealthKitError.dataTypeUnavailable(id.rawValue))); return
        }

        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let q = HKStatisticsQuery(quantityType: type,
                                  quantitySamplePredicate: predicate,
                                  options: .discreteAverage) { _, stats, error in
            if let _ = error {
                // Fallback as 0 if no samples
                completion(.success(0)); return
            }
            let v = stats?.averageQuantity()?.doubleValue(for: unit) ?? 0
            completion(.success(v))
        }
        store.execute(q)
    }

    /// Most recent sample value (fallback if you prefer latest instead of avg)
    func fetchMostRecent(_ id: HKQuantityTypeIdentifier,
                         unit: HKUnit,
                         completion: @escaping (Result<Double, Error>) -> Void) {

        guard let type = HKObjectType.quantityType(forIdentifier: id) else {
            completion(.failure(HealthKitError.dataTypeUnavailable(id.rawValue))); return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
            if let _ = error {
                completion(.success(0)); return
            }
            guard let s = samples?.first as? HKQuantitySample else {
                completion(.success(0)); return
            }
            completion(.success(s.quantity.doubleValue(for: unit)))
        }
        store.execute(q)
    }

    // MARK: - Per-day summaries (for historical backfill)

    /// Build a one-day summary bounded to [startOfDay(day), startOfDay(day)+1d)
    /// Returns a HealthSummary via completion.
    func dailySummary(for day: Date, completion: @escaping (Result<HealthSummary, Error>) -> Void) {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            completion(.failure(NSError(domain: "date", code: -1))); return
        }

        let group = DispatchGroup()
        var firstError: Error?

        var steps = 0
        var activeEnergy = 0
        var carbs: Double = 0
        var exerciseMin = 0
        var hrBPM = 0
        var glucose = 0
        var insulin: Double = 0

        func cap<T>(_ result: Result<T, Error>, _ assign: (T)->Void) {
            switch result {
            case .success(let v): assign(v)
            case .failure(let e): if firstError == nil { firstError = e }
            }
        }

        // Steps
        group.enter()
        sum(for: .stepCount, unit: .count(), start: start, end: end) { r in
            cap(r) { steps = Int($0) }; group.leave()
        }

        // Active energy (kcal)
        group.enter()
        sum(for: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: end) { r in
            cap(r) { activeEnergy = Int($0.rounded()) }; group.leave()
        }

        // Carbohydrates (g)
        group.enter()
        sum(for: .dietaryCarbohydrates, unit: .gram(), start: start, end: end) { r in
            cap(r) { carbs = Double(round(10*$0)/10) }; group.leave()
        }

        // Exercise minutes
        group.enter()
        sum(for: .appleExerciseTime, unit: .minute(), start: start, end: end) { r in
            cap(r) { exerciseMin = Int($0.rounded()) }; group.leave()
        }

        // Heart rate average (BPM)
        group.enter()
        avg(for: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end) { r in
            cap(r) { hrBPM = Int($0.rounded()) }; group.leave()
        }

        // Glucose average (mg/dL)
        group.enter()
        avg(for: .bloodGlucose, unit: HKUnit(from: "mg/dL"), start: start, end: end) { r in
            cap(r) { glucose = Int($0.rounded()) }; group.leave()
        }

        // Insulin sum (IU)
        group.enter()
        sum(for: .insulinDelivery, unit: .internationalUnit(), start: start, end: end) { r in
            cap(r) { insulin = Double(round(10*$0)/10) }; group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let e = firstError {
                completion(.failure(e)); return
            }
            let iso = ISO8601DateFormatter().string(from: start)
            let summary = HealthSummary(
                dateISO8601: iso,
                steps: steps,
                activeEnergyKcal: activeEnergy,
                carbsG: carbs,
                exerciseMin: exerciseMin,
                heartRateBPM: hrBPM,
                glucoseMgdl: glucose,
                insulinIU: insulin
            )
            completion(.success(summary))
        }
    }

    // MARK: - Bounded-day helpers used by dailySummary

    fileprivate func sum(for id: HKQuantityTypeIdentifier,
                         unit: HKUnit,
                         start: Date,
                         end: Date,
                         completion: @escaping (Result<Double, Error>) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else {
            completion(.failure(HealthKitError.dataTypeUnavailable(id.rawValue))); return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type,
                                  quantitySamplePredicate: predicate,
                                  options: .cumulativeSum) { _, stats, error in
            if error != nil { completion(.success(0)); return }
            completion(.success(stats?.sumQuantity()?.doubleValue(for: unit) ?? 0))
        }
        store.execute(q)
    }

    fileprivate func avg(for id: HKQuantityTypeIdentifier,
                         unit: HKUnit,
                         start: Date,
                         end: Date,
                         completion: @escaping (Result<Double, Error>) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else {
            completion(.failure(HealthKitError.dataTypeUnavailable(id.rawValue))); return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type,
                                  quantitySamplePredicate: predicate,
                                  options: .discreteAverage) { _, stats, error in
            if error != nil { completion(.success(0)); return }
            completion(.success(stats?.averageQuantity()?.doubleValue(for: unit) ?? 0))
        }
        store.execute(q)
    }
}

extension HealthKitManager {
    func fetchGlucoseSeries(start: Date,
                            end: Date,
                            completion: @escaping (Result<[GlucosePoint], Error>) -> Void)
    {
        guard let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            completion(.success([])); return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let q = HKSampleQuery(sampleType: type,
                              predicate: predicate,
                              limit: HKObjectQueryNoLimit,
                              sortDescriptors: [sort]) { [weak self] _, samples, error in
            // We don't actually need self here, but keep the capture consistent
            if let _ = error {
                completion(.success([])); return
            }
            let unit = HKUnit(from: "mg/dL")
            let points: [GlucosePoint] = (samples as? [HKQuantitySample])?.map {
                GlucosePoint(date: $0.endDate, mgdl: $0.quantity.doubleValue(for: unit))
            } ?? []
            completion(.success(points))
        }
        store.execute(q)
    }
}

