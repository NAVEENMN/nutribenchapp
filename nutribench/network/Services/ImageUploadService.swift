//
//  ImageUploadService.swift
//  nutribench
//

import Foundation
import UIKit

/// Service responsible for uploading food images to S3 via your backend.
final class ImageUploadService {
    static let shared = ImageUploadService()
    private init() {}

    /// Upload a JPEG image to S3 (via Lambda) and return its public URL.
    func uploadImage(image: UIImage) async throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(
                domain: "ImageUpload",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode image as JPEG"]
            )
        }

        struct GetUploadURLPayload: Encodable {
            let user_id: String
            let filename: String
            let content_type: String
        }

        struct GetUploadURLResponse: Decodable {
            let ok: Bool
            let upload_url: String?
            let public_url: String?
            let error: String?
        }

        let uid = UserID.getOrCreate()
        let filename = UUID().uuidString + ".jpg"

        let payload = GetUploadURLPayload(
            user_id: uid,
            filename: filename,
            content_type: "image/jpeg"
        )

        // Step 1: ask Lambda for URLs
        let dataResp = try await DBClient.shared.postRaw("get_image_upload_url",
                                                         payload: payload)
        let decoded = try JSONDecoder().decode(GetUploadURLResponse.self, from: dataResp)

        guard decoded.ok,
              let uploadURLString = decoded.upload_url,
              let publicURLString = decoded.public_url,
              let uploadURL = URL(string: uploadURLString),
              let publicURL = URL(string: publicURLString) else {
            let msg = decoded.error ?? "Could not get upload URL"
            throw NSError(
                domain: "ImageUpload",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        // Step 2: PUT to S3 directly from the app
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "ImageUpload",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "S3 upload failed with \(http.statusCode)"]
            )
        }

        // Step 3: return the public URL to be stored as image_s3_url
        return publicURL
    }
}

