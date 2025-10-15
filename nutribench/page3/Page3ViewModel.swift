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

    private let hk = HealthKitManager()

    func loadInitial() {
        // last 24 hours window
        rangeEnd = Date()
        rangeStart = rangeEnd.addingTimeInterval(-24*3600)
        loadGlucose()
        loadMeals()
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
                // Only food logs; map to FoodLog via toFoodLog()
                let mapped = events.compactMap { $0.toFoodLog() }
                // Show recent first for the list
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
    }

    /// Go back to the last 24h window
    func showLast24h() {
        selectedDate = nil
        rangeEnd = Date()
        rangeStart = rangeEnd.addingTimeInterval(-24*3600)
        loadGlucose()
    }
}

