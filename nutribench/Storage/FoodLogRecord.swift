//
//  FoodLogRecord.swift
//  nutribench
//

import Foundation
import CoreData

@objc(FoodLogRecord)
class FoodLogRecord: NSManagedObject {
}

extension FoodLogRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<FoodLogRecord> {
        NSFetchRequest<FoodLogRecord>(entityName: "FoodLogRecord")
    }

    @NSManaged var id: UUID?
    @NSManaged var eventId: String?
    @NSManaged var date: Date?
    @NSManaged var food: String?
    @NSManaged var carbsText: String?
    @NSManaged var serverResponse: String?
    @NSManaged var originalQuery: String?
    @NSManaged var imageS3URL: String?
    @NSManaged var localImageFilename: String?
}

// MARK: - Mapping to your domain model

extension FoodLogRecord {
    func toDomain() -> FoodLog {
        FoodLog(
            id: id ?? UUID(),
            eventId: eventId,
            date: date ?? Date.distantPast,
            food: food ?? "Food",
            carbsText: carbsText ?? "15g",
            serverResponse: serverResponse,
            originalQuery: originalQuery ?? "",
            imageS3URL: imageS3URL,
            localImageFilename: localImageFilename
        )
    }

    func update(from log: FoodLog) {
        id = log.id
        eventId = log.eventId
        date = log.date
        food = log.food
        carbsText = log.carbsText
        serverResponse = log.serverResponse
        originalQuery = log.originalQuery
        imageS3URL = log.imageS3URL
        localImageFilename = log.localImageFilename
    }
}

