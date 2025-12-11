//
//  Typography.swift
//  nutribench
//
//  Centralized text styles for the app.
//

import SwiftUI

// MARK: - Token namespace (sizes etc.)

enum AppTypography {
    enum Size {
        static let title: CGFloat        = 22   // main app title
        static let subtitle: CGFloat     = 15   // secondary label under title
        static let sectionTitle: CGFloat = 17   // "Glucose curve", "Meals", etc.
        static let metricValue: CGFloat  = 34   // big numbers (Steps, Glucose)
        static let metricUnit: CGFloat   = 13   // "kcal", "mg/dL" etc.
        static let body: CGFloat         = 15   // normal text
        static let caption: CGFloat      = 12   // smaller annotations
        static let chip: CGFloat         = 13   // small buttons / chips
    }
}

// MARK: - Semantic fonts

extension Font {
    /// App-wide main title (e.g., "UCSB Nutribench")
    static var appTitle: Font {
        .system(size: AppTypography.Size.title,
                weight: .bold,
                design: .rounded)
    }

    /// Optional subtitle under the main title.
    static var appSubtitle: Font {
        .system(size: AppTypography.Size.subtitle,
                weight: .regular,
                design: .rounded)
    }

    /// Section headers: "Glucose curve", "Meals", "Indicators", etc.
    static var appSectionTitle: Font {
        .system(size: AppTypography.Size.sectionTitle,
                weight: .semibold,
                design: .rounded)
    }

    /// Big metrics: Steps, Glucose, etc.
    static var appMetricValue: Font {
        .system(size: AppTypography.Size.metricValue,
                weight: .bold,
                design: .rounded)
    }

    /// Units / small labels under metrics, like "kcal", "mg/dL".
    static var appMetricUnit: Font {
        .system(size: AppTypography.Size.metricUnit,
                weight: .regular,
                design: .rounded)
    }

    /// Primary body text.
    static var appBody: Font {
        .system(size: AppTypography.Size.body,
                weight: .regular,
                design: .rounded)
    }

    /// Smaller descriptive text / hints / steps.
    static var appCaption: Font {
        .system(size: AppTypography.Size.caption,
                weight: .regular,
                design: .rounded)
    }

    /// Small chip / button labels (e.g. "Last 24h").
    static var appChip: Font {
        .system(size: AppTypography.Size.chip,
                weight: .semibold,
                design: .rounded)
    }
}
