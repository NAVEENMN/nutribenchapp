//
//  BrandheaderView.swift
//  nutribench
//
//  Created by Naveen Mysore on 10/8/25.
//

import SwiftUI

// UCSB brand color (Navy)
let UCSBNavy = Color(hex: "#003660")

// Small hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 54, 96) // fallback = UCSB Navy
        }
        self = Color(.sRGB,
                     red: Double(r) / 255.0,
                     green: Double(g) / 255.0,
                     blue: Double(b) / 255.0,
                     opacity: 1.0)
    }
}

// Reusable app header
struct AppHeader: View {
    var title: String = "UCSB Nutribench"
    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(UCSBNavy)
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

