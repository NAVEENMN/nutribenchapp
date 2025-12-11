//
//  HealthSummary.swift
//  nutribench
//

import Foundation

/// Single-day health summary payload sent to the backend.
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

