import Foundation
import UIKit

final class FoodImageStore {
    static let shared = FoodImageStore()

    private let fm = FileManager.default
    private let dir: URL

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        dir = docs.appendingPathComponent("food_images", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // Deterministic file URL based on log.id
    private func fileURL(for logId: UUID) -> URL {
        dir.appendingPathComponent("\(logId.uuidString).jpg")
    }

    // Center-crop to square and save as JPEG.
    @discardableResult
    func saveSquareImage(_ image: UIImage, for logId: UUID) -> String? {
        guard let cropped = image.centerCroppedSquare(),
              let data = cropped.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        let url = fileURL(for: logId)
        do {
            try data.write(to: url, options: [.atomic])
            // filename is still useful for debugging / UI if you like
            return url.lastPathComponent
        } catch {
            print("⚠️ FoodImageStore.saveSquareImage failed:", error)
            return nil
        }
    }

    // Load using the id-derived filename (ignores localImageFilename)
    func loadLocalImage(for log: FoodLog) -> UIImage? {
        let url = fileURL(for: log.id)
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            return nil
        }
        return img
    }

    /// If local missing but S3 URL exists, download, cache, and return.
    func loadOrDownloadImage(for log: FoodLog,
                             completion: @escaping (UIImage?) -> Void) {
        if let img = loadLocalImage(for: log) {
            completion(img); return
        }
        guard let s = log.imageS3URL, let url = URL(string: s) else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, resp, err in
            if let data, let img = UIImage(data: data) {
                _ = self.saveSquareImage(img, for: log.id)
                completion(img)
            } else {
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - UIImage helper

extension UIImage {
    /// Center-crop to a square.
    func centerCroppedSquare() -> UIImage? {
        let minSide = min(size.width, size.height)
        let x = (size.width  - minSide) / 2.0
        let y = (size.height - minSide) / 2.0
        let cropRect = CGRect(x: x, y: y,
                              width: minSide,
                              height: minSide)

        guard let cg = cgImage else { return nil }
        let scale = self.scale
        let scaledRect = CGRect(x: cropRect.origin.x * scale,
                                y: cropRect.origin.y * scale,
                                width: cropRect.size.width * scale,
                                height: cropRect.size.height * scale)

        guard let croppedCG = cg.cropping(to: scaledRect) else { return nil }
        return UIImage(cgImage: croppedCG,
                       scale: scale,
                       orientation: imageOrientation)
    }
}
