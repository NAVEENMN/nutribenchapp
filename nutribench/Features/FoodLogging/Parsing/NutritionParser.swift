//
//  NutritionParser.swift
//  nutribench
//

import Foundation

/// Parsed nutrition info from the LLM/Lambda nutrition response.
struct ParsedNutrition {
    /// List of normalized food item descriptions.
    let foods: [String]
    /// Total carbs in grams, if present.
    let carbsG: Double?
    /// Human-readable calculation steps, if present.
    let steps: String?
}

enum NutritionParser {

    // Public entrypoint
    static func parse(from response: String) -> ParsedNutrition? {
        let once = unwrapJSONStringOnce(response)
        let candidate = stripFencesAndExtractJSONObject(once)

        guard let data = candidate.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let foods = (obj["food_items"] as? [Any])?
            .compactMap { $0 as? String }
            .map { normalizeFoodName($0) }
            .filter { !$0.isEmpty } ?? []

        // Try common carb keys; tolerate strings like "6g", "0g de carbohidratos"
        let carbsG =
            numberFromAny(obj["total_carbs_g"]) ??
            numberFromAny(obj["carbs_g"]) ??
            numberFromAny(obj["carbs"]) ??
            numberFromAny(obj["total_carbs"])

        let steps = (obj["calculation_steps"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedNutrition(foods: foods, carbsG: carbsG, steps: steps)
    }

    /// Fallback extractor for responses that just contain "carbs = 45g" style text.
    static func extractCarbText(from text: String?) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }

        // Last non-empty line
        if let lastLine = t.components(separatedBy: .newlines).reversed()
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            t = lastLine
        }

        let raw: String = {
            if let eq = t.range(of: "=", options: .backwards) {
                return String(t[eq.upperBound...])
            } else {
                return t
            }
        }()

        let uptoNewline = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw

        var cleaned = uptoNewline.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.isEmpty ? nil : cleaned
    }
}

// MARK: - Private helpers (moved from Page2ViewModel)

/// If the server body is a JSON-encoded *string* (e.g. "\"{\\\"food_items\\\":...}\""),
/// decode it once to get the inner JSON text.
private func unwrapJSONStringOnce(_ s: String) -> String {
    if let data = "[\(s)]".data(using: .utf8),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
       let first = arr.first as? String {
        return first
    }
    return s
}

/// Remove code fences and keep just the JSON object segment if present.
private func stripFencesAndExtractJSONObject(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.firstIndex(of: "{"),
       let end = trimmed.lastIndex(of: "}") {
        return String(trimmed[start...end])
    }
    return trimmed
}

/// Keep quantities as-is; just trim whitespace.
private func normalizeFoodName(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func numberFromAny(_ any: Any?) -> Double? {
    switch any {
    case let d as Double: return d
    case let i as Int:    return Double(i)
    case let s as String:
        if let d = Double(s) { return d }
        if let regex = try? NSRegularExpression(pattern: #"(\d+(\.\d+)?)"#),
           let match = regex.firstMatch(
                in: s,
                range: NSRange(s.startIndex..<s.endIndex, in: s)
           ),
           let r = Range(match.range(at: 1), in: s) {
            return Double(s[r])
        }
        return nil
    default:
        return nil
    }
}

