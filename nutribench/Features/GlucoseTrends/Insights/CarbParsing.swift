//
//  CarbParsing.swift
//  nutribench
//

import Foundation

struct CarbPoint: Identifiable {
    let id = UUID()
    let date: Date
    let grams: Double
}

enum CarbParsing {
    /// Extract numeric grams from strings like "48g", "48 g", "48", "48.2g"
    static func grams(from carbsText: String) -> Double? {
        let s = carbsText.lowercased()
        let pattern = #"(\d+(\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
              let r = Range(match.range(at: 1), in: s) else {
            return nil
        }
        return Double(s[r])
    }

    /// Carb points inside the visible window.
    static func points(from meals: [FoodLog], rangeStart: Date, rangeEnd: Date) -> [CarbPoint] {
        meals.compactMap { log in
            guard log.date >= rangeStart, log.date <= rangeEnd else { return nil }
            guard let g = grams(from: log.carbsText) else { return nil }
            return CarbPoint(date: log.date, grams: g)
        }
        .sorted { $0.date < $1.date }
    }
}

