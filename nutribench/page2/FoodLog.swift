// FoodLog.swift
import Foundation

struct FoodLog: Identifiable, Equatable, Codable {
    let id: UUID                 // local view ID (must be stable)
    let eventId: String?         // Mongo event_id (nil until server returns)
    let date: Date
    let food: String
    let carbsText: String        // e.g. "48g"
    let serverResponse: String?  // calculation_steps
    let originalQuery: String    // what the user typed

    // Custom initializer so we can preserve `id` when copying
    init(
        id: UUID = UUID(),
        eventId: String?,
        date: Date,
        food: String,
        carbsText: String,
        serverResponse: String?,
        originalQuery: String
    ) {
        self.id = id
        self.eventId = eventId
        self.date = date
        self.food = food
        self.carbsText = carbsText
        self.serverResponse = serverResponse
        self.originalQuery = originalQuery
    }
}
