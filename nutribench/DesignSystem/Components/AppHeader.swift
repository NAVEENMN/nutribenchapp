//
//  AppHeader.swift
//  nutribench
//

import SwiftUI

/// Reusable top header used across all pages (Indicators, Log Food, Photos, Trends).
struct AppHeader: View {
    /// Main title text. Defaults to the app name.
    var title: String = "UCSB Nutribench"

    /// Optional subtitle (e.g., "Indicators", "Glucose Trends").
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appTitle)
                    .foregroundColor(UCSBNavy)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appSubtitle)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}
