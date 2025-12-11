//
//  PersistenceController.swift
//  nutribench
//

import Foundation
import CoreData

/// Shared Core Data stack for the app.
/// Uses an `NSPersistentContainer` backed by SQLite.
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NutribenchCoreData")

        if inMemory {
            // Used only for tests/previews if you want.
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }

        // Make sure main context merges changes from background contexts.
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

