//
//  ServerEvent+FoodLog.swift
//  nutribench
//

import Foundation

extension ServerEvent {
    func toFoodLog() -> FoodLog? {
        guard event_type == "food_log" else { return nil }

        let food = (details?["food"]?.value as? String) ?? "Food"

        let carbsText: String = {
            if let s = details?["carbsText"]?.value as? String { return s }
            if let g = details?["carbs_g"]?.value as? Double {
                return String(format: "%.0f g", g)
            }
            if let gStr = details?["total_carbs_g"]?.value as? String,
               let g = Double(gStr) {
                return String(format: "%.0f g", g)
            }
            return "15 g"
        }()

        let steps = (details?["calculation_steps"]?.value as? String)
                 ?? (details?["serverResponse"]?.value as? String)

        let original = (details?["originalQuery"]?.value as? String) ?? food

        // Prefer the timestampISO inside details (user-edited time), then fall back
        let detailTS = details?["timestampISO"]?.value as? String
        let date = DateParsers
            .parseServerTimestamp(detailTS ?? timestampISO ?? timestamp)
            ?? Date.distantPast

        let imageS3URL = details?["image_s3_url"]?.value as? String

        return FoodLog(
            eventId: event_id,
            date: date,
            food: food,
            carbsText: carbsText,
            serverResponse: steps,
            originalQuery: original,
            imageS3URL: imageS3URL,
            localImageFilename: nil
        )
    }
}

