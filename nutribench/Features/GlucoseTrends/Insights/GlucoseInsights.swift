//
//  GlucoseInsights.swift
//  nutribench
//

import Foundation

/// Helper for glucose interpolation and summary metrics used by the Glucose Trends feature.
enum GlucoseInsights {

    /// Small struct collecting key metrics for the visible window.
    struct Window {
        let atSelected: Double?
        let deltaSinceMeal: Double?
        let dailyMax: Double?
        let dailyMin: Double?
    }

    // MARK: - Linear interpolation

    /// Linearly interpolate glucose at `date` from sorted or unsorted points.
    static func interpolatedGlucose(at date: Date,
                                    from points: [GlucosePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let pts = points.sorted { $0.date < $1.date }

        if let first = pts.first, date <= first.date { return first.mgdl }
        if let last  = pts.last,  date >= last.date  { return last.mgdl  }

        guard let upperIdx = pts.firstIndex(where: { $0.date >= date }), upperIdx > 0 else {
            return nil
        }

        let lowerIdx = upperIdx - 1
        let p0 = pts[lowerIdx], p1 = pts[upperIdx]

        let t0 = p0.date.timeIntervalSince1970
        let t1 = p1.date.timeIntervalSince1970
        let tt = date.timeIntervalSince1970
        let span = max(1e-6, t1 - t0)
        let u = (tt - t0) / span

        return p0.mgdl + u * (p1.mgdl - p0.mgdl)
    }

    // MARK: - Window-level metrics

    /// Compute insights for the current visible window and selected meal time.
    static func computeWindow(points: [GlucosePoint],
                              selectedDate: Date?,
                              dailyMax: Double?,
                              dailyMin: Double?) -> Window {
        if points.isEmpty {
            return Window(atSelected: nil,
                          deltaSinceMeal: nil,
                          dailyMax: dailyMax,
                          dailyMin: dailyMin)
        }

        let atSel = selectedDate.flatMap { interpolatedGlucose(at: $0, from: points) }

        var delta: Double? = nil
        if let sd = selectedDate, let yMeal = atSel {
            let after = points.filter { $0.date >= sd }
            if let peakAfter = after.map(\.mgdl).max() {
                delta = peakAfter - yMeal
            }
        }

        return Window(
            atSelected: atSel,
            deltaSinceMeal: delta,
            dailyMax: dailyMax,
            dailyMin: dailyMin
        )
    }

    // MARK: - Formatting helpers

    static func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(Int(round(v)))
    }

    static func formatSigned(_ v: Double?) -> String {
        guard let v else { return "—" }
        let n = Int(round(v))
        return n > 0 ? "+\(n)" : "\(n)"
    }
}

