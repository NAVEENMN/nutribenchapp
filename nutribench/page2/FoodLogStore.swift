import Foundation

final class FoodLogStore {
    static let shared = FoodLogStore()

    // You could also use UserDefaults, but a file is fine and transparent
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("food_logs_v1.json")
    }

    func load() -> [FoodLog] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([FoodLog].self, from: data)
        } catch {
            // If file missing or invalid, just treat as empty
            return []
        }
    }

    func save(_ logs: [FoodLog]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(logs)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("⚠️ Failed to save FoodLogStore:", error)
        }
    }
}
