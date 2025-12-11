//
//  NutritionService.swift
//  nutribench
//

import Foundation

/// Calls the nutrition Lambda and returns the raw `body` string
/// after unwrapping the Lambda wrapper `{ statusCode, body }`.
final class NutritionService {
    static let shared = NutritionService()
    private init() {}

    private let endpoint = APIEndpoints.nutritionInference

    /// Send a meal description to the Lambda and get back the body string,
    /// which is then parsed by `NutritionParser`.
    func estimate(for meal: String) async throws -> String {
        let trimmed = meal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "NutritionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Empty meal text"]
            )
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["body": trimmed]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, _) = try await URLSession.shared.data(for: req)

        // We expect either:
        //   { "statusCode": 200, "body": "<string | dict | array>" }
        // or some raw text.
        do {
            let any = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = any as? [String: Any] {
                let status = dict["statusCode"] as? Int ?? 0
                if status != 200 {
                    throw NSError(
                        domain: "NutritionService",
                        code: status,
                        userInfo: [NSLocalizedDescriptionKey: "Bad status: \(status)"]
                    )
                }

                if let bodyStr = dict["body"] as? String {
                    return bodyStr
                } else if let bodyObj = dict["body"] as? [String: Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyObj)
                    return String(data: data2, encoding: .utf8) ?? ""
                } else if let bodyArr = dict["body"] as? [Any] {
                    let data2 = try JSONSerialization.data(withJSONObject: bodyArr)
                    return String(data: data2, encoding: .utf8) ?? ""
                }
            }

            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                return raw
            } else {
                throw NSError(
                    domain: "NutritionService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"]
                )
            }
        } catch {
            // If JSON decoding fails, still try to interpret as raw UTF-8 text
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                return raw
            }
            throw error
        }
    }
}

