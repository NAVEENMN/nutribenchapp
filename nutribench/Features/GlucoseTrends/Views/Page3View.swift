import SwiftUI

private enum InsightKind: String, Identifiable {
    case atSelected
    case deltaSinceMeal
    case dailyMax
    case dailyMin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atSelected:      return "At selected meal"
        case .deltaSinceMeal:  return "Δ since last meal"
        case .dailyMax:        return "Daily max"
        case .dailyMin:        return "Daily min"
        }
    }

    /// Plain-English explanation shown in the alert
    var explanation: String {
        switch self {
        case .atSelected:
            return "Estimated glucose (mg/dL) at the moment of the selected meal. If the exact timestamp isn't available, we interpolate between the nearest readings."
        case .deltaSinceMeal:
            return "Change in glucose since the selected meal within the visible window:\n\nΔ = maxₜ≥t_meal G(t) − G(t_meal)\n\nPositive means your glucose peaked above the value at mealtime."
        case .dailyMax:
            return "The highest glucose (mg/dL) recorded today (00:00–23:59) from available samples."
        case .dailyMin:
            return "The lowest glucose (mg/dL) recorded today (00:00–23:59) from available samples."
        }
    }
}

// ======================= Swift Charts section =======================
#if canImport(Charts)
import Charts

@available(iOS 16.0, *)
private struct GlucoseChartSection: View {
    let points: [GlucosePoint]
    let selectedDate: Date?
    let rangeStart: Date
    let rangeEnd: Date
    let accent: Color

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("mg/dL", p.mgdl)
                )
                .interpolationMethod(.catmullRom)
            }

            if let cursor = selectedDate {
                RuleMark(x: .value("Selected", cursor))
                    .foregroundStyle(accent)
                    .lineStyle(.init(lineWidth: 2, dash: [4, 4]))

                if let y = GlucoseInsights.interpolatedGlucose(at: cursor, from: points) {
                    PointMark(
                        x: .value("Time", cursor),
                        y: .value("mg/dL", y)
                    )
                    .symbol(Circle())
                    .symbolSize(60)
                    .foregroundStyle(accent)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(Int(round(y)))")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                            )
                    }
                }
            }
        }
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartYAxisLabel("mg/dL")
        .chartXAxis { AxisMarks() }
                .chartYAxis { AxisMarks(position: .leading) }
    }
}

@available(iOS 16.0, *)
private struct CarbsChartSection: View {
    let carbs: [CarbPoint]
    let rangeStart: Date
    let rangeEnd: Date

    var body: some View {
        Chart {
            ForEach(carbs) { c in
                BarMark(
                    x: .value("Time", c.date),
                    y: .value("Carbs (g)", c.grams)
                )
            }
        }
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartYAxisLabel("g")
        .chartXAxis {
            // Keep it minimal; the glucose chart already has the main axis marks.
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}
#endif

// ======================= Page 3 main view =======================
struct Page3View: View {
    @State private var infoToShow: InsightKind? = nil
    @StateObject private var vm = Page3ViewModel()

    // Local formatters
    private let dfDate: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "EEE, MMM d"; return f
    }()
    private let dfTime: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "h:mm a"; return f
    }()
    private func dateString(_ d: Date) -> String { dfDate.string(from: d) }
    private func timeString(_ d: Date) -> String { dfTime.string(from: d) }

    // Layout constants
    private let chartHeight: CGFloat = 320
    private let carbChartHeight: CGFloat = 90
    private let mealCardWidth: CGFloat = 160
    private let tileHeight: CGFloat = 74
    private let selectionToleranceSec: TimeInterval = 120 // ±2 minutes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ---- Fixed brand header ----
            VStack(alignment: .leading, spacing: 0) {
                AppHeader(title: "UCSB Nutribench")
                    .padding([.top, .horizontal])
                Divider()
            }

            // ---- Chart area ----
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Glucose curve")
                    .font(.appSectionTitle)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                ZStack(alignment: .topLeading) {
                    Group {
                        if vm.glucose.isEmpty {
                            VStack(spacing: 12) {
                                Text("No glucose data in this range")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Button("Show Last 24 Hours") { vm.showLast24h() }
                                    .accentColor(UCSBNavy)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            if #available(iOS 16.0, *) {
                                #if canImport(Charts)
                                GlucoseChartSection(
                                    points: vm.glucose,
                                    selectedDate: vm.selectedDate,
                                    rangeStart: vm.rangeStart,
                                    rangeEnd: vm.rangeEnd,
                                    accent: UCSBNavy
                                )
                                .padding(.horizontal)
                                #else
                                SparklineFallback(points: vm.glucose,
                                                  rangeStart: vm.rangeStart,
                                                  rangeEnd: vm.rangeEnd,
                                                  selectedDate: vm.selectedDate,
                                                  accent: UCSBNavy)
                                .padding(.horizontal)
                                #endif
                            } else {
                                SparklineFallback(points: vm.glucose,
                                                  rangeStart: vm.rangeStart,
                                                  rangeEnd: vm.rangeEnd,
                                                  selectedDate: vm.selectedDate,
                                                  accent: UCSBNavy)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
                .padding(.top, 6)
            }

            // ---- Carbs bar chart (grams) ----
            let carbPoints = CarbParsing.points(from: vm.meals,
                                                rangeStart: vm.rangeStart,
                                                rangeEnd: vm.rangeEnd)

            VStack(alignment: .leading, spacing: 4) {
                Text("Carbs (g)")
                    .font(.appSectionTitle)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Group {
                    if carbPoints.isEmpty {
                        Text("No carb data in this range")
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if #available(iOS 16.0, *) {
                            #if canImport(Charts)
                            CarbsChartSection(
                                carbs: carbPoints,
                                rangeStart: vm.rangeStart,
                                rangeEnd: vm.rangeEnd
                            )
                            .padding(.horizontal)
                            #else
                            CarbsBarsFallback(
                                carbs: carbPoints,
                                rangeStart: vm.rangeStart,
                                rangeEnd: vm.rangeEnd
                            )
                            .padding(.horizontal)
                            #endif
                        } else {
                            CarbsBarsFallback(
                                carbs: carbPoints,
                                rangeStart: vm.rangeStart,
                                rangeEnd: vm.rangeEnd
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(height: carbChartHeight)
            }
            .padding(.top, 6)

            // ---- INSIGHTS BAR (uniform tiles, two-line titles) ----
            let insights = GlucoseInsights.computeWindow(
                points: vm.glucose,
                selectedDate: vm.selectedDate,
                dailyMax: vm.dailyMax,
                dailyMin: vm.dailyMin
            )

            HStack(spacing: 10) {
                insightTile(
                    kind: .atSelected,
                    title: "At selected",
                    value: GlucoseInsights.format(insights.atSelected)
                ) { infoToShow = .atSelected }

                insightTile(
                    kind: .deltaSinceMeal,
                    title: "Δ since\nlast meal",
                    value: GlucoseInsights.formatSigned(insights.deltaSinceMeal)
                ) { infoToShow = .deltaSinceMeal }

                insightTile(
                    kind: .dailyMax,
                    title: "Daily\nmax",
                    value: GlucoseInsights.format(insights.dailyMax)
                ) { infoToShow = .dailyMax }

                insightTile(
                    kind: .dailyMin,
                    title: "Daily\nmin",
                    value: GlucoseInsights.format(insights.dailyMin)
                ) { infoToShow = .dailyMin }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            // ---- Meals strip at bottom ----
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Meals")
                        .font(.appSectionTitle)
                    Spacer()
                    Button("Last 24h") { vm.showLast24h() }
                        .font(.caption)
                        .accentColor(UCSBNavy)
                }
                .padding(.horizontal)

                if vm.meals.isEmpty {
                    Text("No food logs")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.meals) { log in
                                let isSelected = isSameMoment(vm.selectedDate, log.date, tolerance: selectionToleranceSec)
                                Button { vm.jump(to: log) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.food)
                                            .font(.appBody)
                                            .fontWeight(.bold)
                                            .lineLimit(1).truncationMode(.tail)
                                            .frame(width: mealCardWidth, alignment: .leading)
                                        HStack(spacing: 6) {
                                            Text(dateString(log.date))
                                                .font(.appCaption)
                                                .foregroundColor(.secondary)
                                            Text(timeString(log.date))
                                                .font(.appCaption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .frame(width: mealCardWidth + 20, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? UCSBNavy : Color.clear, lineWidth: 2)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .alert(item: $infoToShow) { kind in
            Alert(
                title: Text(kind.title),
                message: Text(kind.explanation),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear { vm.loadInitial() }
    }

    private func insightTile(
        kind: InsightKind,
        title: String,
        value: String,
        onInfo: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            // Tile content
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.appCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.headline)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Info button (top-right corner)
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .accessibilityLabel(Text("Info about \(kind.title)"))
        }
    }
    
    // ---- Helpers ----
    private func isSameMoment(_ a: Date?, _ b: Date, tolerance: TimeInterval) -> Bool {
        guard let a = a else { return false }
        return abs(a.timeIntervalSince(b)) <= tolerance
    }

    // Uniform tile with multi-line title support
    private func insightTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.headline)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// ======================= iOS 14/15 fallback sparkline =======================
private struct CarbsBarsFallback: View {
    let carbs: [CarbPoint]
    let rangeStart: Date
    let rangeEnd: Date

    var body: some View {
        GeometryReader { geo in
            let minX = rangeStart.timeIntervalSince1970
            let maxX = rangeEnd.timeIntervalSince1970
            let maxCarb = carbs.map(\.grams).max() ?? 0

            ZStack(alignment: .bottomLeading) {
                // Baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .stroke(Color(.separator), lineWidth: 0.5)

                ForEach(carbs) { c in
                    let xNorm = (c.date.timeIntervalSince1970 - minX) / max(1, (maxX - minX))
                    let x = geo.size.width * CGFloat(xNorm)

                    let hNorm = (maxCarb > 0) ? (c.grams / maxCarb) : 0
                    let h = geo.size.height * CGFloat(hNorm)

                    // Use a fixed bar width in points so it's readable
                    let barWidth: CGFloat = 6

                    Rectangle()
                        .frame(width: barWidth, height: h)
                        .position(x: x, y: geo.size.height - h/2)
                        .opacity(0.35)
                }
            }
        }
    }
}

private struct SparklineFallback: View {
    let points: [GlucosePoint]
    let rangeStart: Date
    let rangeEnd: Date
    let selectedDate: Date?
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let minX = rangeStart.timeIntervalSince1970
            let maxX = rangeEnd.timeIntervalSince1970
            let minY = points.map(\.mgdl).min() ?? 0
            let maxY = points.map(\.mgdl).max() ?? 1

            ZStack {
                // Line path
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let xNorm = (pt.date.timeIntervalSince1970 - minX) / max(1, (maxX - minX))
                        let yNorm = (pt.mgdl - minY) / max(1e-6, (maxY - minY))
                        let x = geo.size.width * CGFloat(xNorm)
                        let y = geo.size.height * (1 - CGFloat(yNorm))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Cursor + interpolated value at exact time
                if let cursor = selectedDate,
                   let yVal = GlucoseInsights.interpolatedGlucose(at: cursor, from: points) {
                    let xNorm = (cursor.timeIntervalSince1970 - minX) / max(1, (maxX - minX))
                    let yNorm = (yVal - minY) / max(1e-6, (maxY - minY))
                    let x = geo.size.width * CGFloat(xNorm)
                    let y = geo.size.height * (1 - CGFloat(yNorm))

                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .foregroundColor(accent)

                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                        .position(x: x, y: y)

                    Text("\(Int(round(yVal)))")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                        )
                        .position(x: x, y: max(0, y - 16))
                }
            }
        }
        .frame(height: 280)
    }
}

// Classic previews
struct Page3View_Previews: PreviewProvider {
    static var previews: some View { Page3View() }
}

