import SwiftUI

// Compile Charts code only if the module exists (Xcode with iOS 16 SDK)
// and constrain usage to iOS 16+ so iOS 14/15 never type-checks it.
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
            }
        }
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartYAxisLabel("mg/dL")
        .chartXAxis { AxisMarks() }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 280)
        .padding()
    }
}
#endif

struct Page3View: View {
    @StateObject private var vm = Page3ViewModel()

    // Local formatters
    private let dfDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    private let dfTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "h:mm a"
        return f
    }()
    private func dateString(_ d: Date) -> String { dfDate.string(from: d) }
    private func timeString(_ d: Date) -> String { dfTime.string(from: d) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 0) {
                AppHeader(title: "UCSB Nutribench")
                    .padding([.top, .horizontal])
                Divider()
            }

            // Chart (iOS 16+ with Charts) or iOS 14/15 fallback
            Group {
                if vm.glucose.isEmpty {
                    VStack(spacing: 12) {
                        Text("No glucose data in this range")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Show Last 24 Hours") { vm.showLast24h() }
                            .accentColor(UCSBNavy) // iOS 14-safe
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Prefer the Charts view if we can compile & run it.
                    if #available(iOS 16.0, * ) {
                        #if canImport(Charts)
                        GlucoseChartSection(
                            points: vm.glucose,
                            selectedDate: vm.selectedDate,
                            rangeStart: vm.rangeStart,
                            rangeEnd: vm.rangeEnd,
                            accent: UCSBNavy
                        )
                        #else
                        SparklineFallback(points: vm.glucose,
                                          rangeStart: vm.rangeStart,
                                          rangeEnd: vm.rangeEnd)
                        #endif
                    } else {
                        SparklineFallback(points: vm.glucose,
                                          rangeStart: vm.rangeStart,
                                          rangeEnd: vm.rangeEnd)
                    }
                }
            }

            // Meal list (recent → older)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Meals").font(.headline)
                    Spacer()
                    Button("Last 24h") { vm.showLast24h() }
                        .font(.caption)
                        .accentColor(UCSBNavy) // iOS 14-safe
                }
                .padding(.horizontal)

                if vm.meals.isEmpty {
                    Text("No food logs")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.meals) { log in
                                Button { vm.jump(to: log) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.food)
                                            .font(.subheadline)
                                            .fontWeight(.bold) // iOS 14-safe bold
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text(dateString(log.date))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(timeString(log.date))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
        }
        .onAppear { vm.loadInitial() }
    }
}

// iOS 14/15 fallback sparkline (no Charts dependency)
private struct SparklineFallback: View {
    let points: [GlucosePoint]
    let rangeStart: Date
    let rangeEnd: Date

    var body: some View {
        GeometryReader { geo in
            let minX = rangeStart.timeIntervalSince1970
            let maxX = rangeEnd.timeIntervalSince1970
            let minY = points.map(\.mgdl).min() ?? 0
            let maxY = points.map(\.mgdl).max() ?? 1
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
        }
        .frame(height: 180)
        .padding()
    }
}

// Classic previews
struct Page3View_Previews: PreviewProvider {
    static var previews: some View { Page3View() }
}
