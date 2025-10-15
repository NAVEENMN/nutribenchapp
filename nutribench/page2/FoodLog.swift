// FoodLog.swift
import Foundation

struct FoodLog: Identifiable, Equatable {
    let id = UUID()                 // local view ID
    let eventId: String?            // Mongo event_id (nil until server returns)
    let date: Date
    let food: String
    let carbsText: String           // e.g. "48g"
    let serverResponse: String?     // calculation_steps
    let originalQuery: String       // what the user typed
}
