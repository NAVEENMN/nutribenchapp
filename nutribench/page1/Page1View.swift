import SwiftUI

struct Page1View: View {
    @StateObject private var vm = Page1ViewModel()
    @State private var showConsent = false
    @State private var uploadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ---- Fixed brand header (matches Page 2) ----
            VStack(alignment: .leading, spacing: 0) {
                AppHeader()
                    .padding([.top, .horizontal])
                // Optional inline loading/error just under the title, like Page 2 style
                if vm.isLoading {
                    ProgressView().padding(.horizontal).padding(.top, 6)
                } else if let err = vm.errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                Divider()
            }

            // ---- Scrollable content below header ----
            ScrollView {
                VStack(spacing: 16) {
                    gridCards()

                    if let status = vm.uploadStatus {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let err = uploadError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            if !vm.isLoading && vm.errorMessage == nil { vm.initialize() }
        }
    }

    // MARK: - Subviews

    private func gridCards() -> some View {
        // Two-column adaptive grid
        let cols = [GridItem(.adaptive(minimum: 160), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            metricCard(title: "Steps", value: "\(vm.steps)", foot: "count")
            metricCard(title: "Active Energy", value: "\(vm.activeEnergyKcal)", foot: "kcal")
            metricCard(title: "Exercise", value: "\(vm.exerciseMin)", foot: "min")
            metricCard(title: "Carbs", value: String(format: "%.1f", vm.carbsG), foot: "g")
            metricCard(title: "Heart Rate", value: "\(vm.heartRateBPM)", foot: "bpm")
            metricCard(title: "Glucose", value: "\(vm.glucoseMgdl)", foot: "mg/dL")
            metricCard(title: "Insulin", value: String(format: "%.1f", vm.insulinIU), foot: "IU")
        }
    }

    private func metricCard(title: String, value: String, foot: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(foot).font(.caption).foregroundColor(.secondary)
            Button {
                vm.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Classic previews (work with iOS 15 toolchains)
struct Page1View_Previews: PreviewProvider {
    static var previews: some View { Page1View() }
}
