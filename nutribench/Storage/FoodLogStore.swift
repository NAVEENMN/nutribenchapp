//
//  FoodLogStore.swift
//  nutribench
//

import Foundation
import CoreData

/// Simple on-disk store for `FoodLog` objects, backed by Core Data.
///
/// - `load()` returns all logs sorted by date (newest first)
/// - `save(_:)` upserts the given logs and removes any that are no longer present
final class FoodLogStore {
    static let shared = FoodLogStore()

    private let context: NSManagedObjectContext

    private init(
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.context = context
    }

    /// Load all logs from Core Data. Returns [] if fetch fails.
    func load() -> [FoodLog] {
        let request: NSFetchRequest<FoodLogRecord> = FoodLogRecord.fetchRequest()
        let sort = NSSortDescriptor(key: "date", ascending: false)
        request.sortDescriptors = [sort]

        do {
            let records = try context.fetch(request)
            return records.map { $0.toDomain() }
        } catch {
            print("⚠️ FoodLogStore.load Core Data fetch failed:", error)
            return []
        }
    }

    /// Save the full list of logs to Core Data.
    ///
    /// Semantics: treat the passed `logs` slice as the *authoritative* set:
    /// - Upsert all logs in the array
    /// - Delete any stored records that are not in the array
    func save(_ logs: [FoodLog]) {
        let ids = Set(logs.map(\.id))

        // 1) Fetch existing records
        let request: NSFetchRequest<FoodLogRecord> = FoodLogRecord.fetchRequest()

        do {
            let existing = try context.fetch(request)

            // 2) Delete any record whose id is not in the `logs` array
            for record in existing {
                if let rid = record.id, !ids.contains(rid) {
                    context.delete(record)
                }
            }

            // 3) Upsert each log
            for log in logs {
                upsert(log)
            }

            // 4) Save context
            if context.hasChanges {
                try context.save()
            }
        } catch {
            print("⚠️ FoodLogStore.save Core Data error:", error)
        }
    }

    // MARK: - Private helpers

    private func upsert(_ log: FoodLog) {
        // Find existing record with same id, if any.
        let request: NSFetchRequest<FoodLogRecord> = FoodLogRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", log.id as CVarArg)
        request.fetchLimit = 1

        let record: FoodLogRecord
        if let existing = try? context.fetch(request).first {
            record = existing
        } else {
            record = FoodLogRecord(context: context)
        }

        record.update(from: log)
    }
}
