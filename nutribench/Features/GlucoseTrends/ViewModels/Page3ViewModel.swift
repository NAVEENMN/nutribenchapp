//
//  Page3ViewModel.swift
//  nutribench
//
//  Created by Naveen Mysore on 10/8/25.
//

import Foundation

@MainActor
final class Page3ViewModel: ObservableObject {
    @Published var glucose: [GlucosePoint] = []
    @Published var meals: [FoodLog] = []
    @Published var selectedDate: Date? = nil         // cursor on chart
    @Published var rangeStart: Date = Date().addingTimeInterval(-24*3600)
    @Published var rangeEnd: Date = Date()

    // NEW: daily extremes for the selected day (or today)
    @Published var dailyMax: Double? = nil
    @Published var dailyMin: Double? = nil

    private let hk = HealthKitManager()

    func loadInitial() {
        // last 24 hours window
        rangeEnd = Date()
        rangeStart = rangeEnd.addingTimeInterval(-24*3600)
        loadGlucose()
        loadMeals()
        // compute daily extremes for "today"
        updateDailyExtremes(for: Date())
    }

    func loadGlucose() {
        hk.fetchGlucoseSeries(start: rangeStart, end: rangeEnd) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let pts): self?.glucose = pts
                case .failure: self?.glucose = []
                }
            }
        }
    }

    func loadMeals(limit: Int = 200) {
        Task {
            let uid = UserID.getOrCreate()
            do {
                let events = try await DBClient.shared.getEvents(userId: uid, limit: limit)
                let mapped = events.compactMap { $0.toFoodLog() }
                meals = mapped.sorted { $0.date > $1.date }
            } catch {
                meals = []
            }
        }
    }

    /// Jump to a meal: center a 3h window around the meal and reload glucose.
    func jump(to meal: FoodLog) {
        selectedDate = meal.date
        let center = meal.date
        rangeStart = center.addingTimeInterval(-90*60)  // -1.5h
        rangeEnd   = center.addingTimeInterval( 90*60)  // +1.5h
        loadGlucose()

        // NEW: compute extremes for that calendar day
        updateDailyExtremes(for: meal.date)
    }

    /// Go back to the last 24h window
    func showLast24h() {
        selectedDate = nil
        rangeEnd = Date()
        rangeStart = rangeEnd.addingTimeInterval(-24*3600)
        loadGlucose()

        // NEW: compute extremes for "today"
        updateDailyExtremes(for: Date())
    }

    // MARK: NEW - Daily extremes for a calendar day
    private func updateDailyExtremes(for day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            self.dailyMax = nil; self.dailyMin = nil; return
        }
        hk.fetchGlucoseSeries(start: start, end: end) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let pts):
                    self?.dailyMax = pts.map(\.mgdl).max()
                    self?.dailyMin = pts.map(\.mgdl).min()
                case .failure:
                    self?.dailyMax = nil; self?.dailyMin = nil
                }
            }
        }
    }
}

