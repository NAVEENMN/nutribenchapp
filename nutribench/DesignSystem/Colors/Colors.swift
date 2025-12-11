//
//  Colors.swift
//  nutribench
//

import SwiftUI

// MARK: - Color+Hex initializer

extension Color {
    /// Initialize a Color from a 6-digit hex string like "#003660" or "003660".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (
                (int >> 16) & 0xFF,
                (int >> 8)  & 0xFF,
                int         & 0xFF
            )
        default:
            // Fallback to UCSB navy if input is malformed
            (r, g, b) = (0, 54, 96)
        }

        self = Color(.sRGB,
                     red:   Double(r) / 255.0,
                     green: Double(g) / 255.0,
                     blue:  Double(b) / 255.0,
                     opacity: 1.0)
    }
}

// MARK: - Brand palette

extension Color {
    /// Primary UCSB navy brand color.
    static let brandNavy = Color(hex: "#003660")

    /// Optional supporting colors (tweak as you design)
    static let brandAccent = Color(hex: "#F7A800")   // warm accent
    static let brandSoftBackground = Color(.secondarySystemBackground)
    static let brandCardBackground = Color(.systemBackground)
}

// MARK: - Legacy aliases (for existing code)

/// Legacy free constant used across the app. Prefer `Color.brandNavy` in new code.
let UCSBNavy = Color.brandNavy
