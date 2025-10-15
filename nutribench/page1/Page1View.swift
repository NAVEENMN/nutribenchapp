import SwiftUI

struct Page1View: View {
    @StateObject private var vm = Page1ViewModel()
    @State private var showConsent = false
    @State private var uploadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header()
                gridCards()

                // Upload button
                Button {
                    showConsent = true
                } label: {
                    Label("Upload to UCSB", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }

                if let status = vm.uploadStatus {
                    Text(status).font(.footnote).foregroundColor(.secondary)
                }
                if let err = uploadError {
                    Text(err).font(.footnote).foregroundColor(.red)
                }
            }
            .padding()
        }
        .onAppear {
            if !vm.isLoading && vm.errorMessage == nil { vm.initialize() }
        }
        .sheet(isPresented: $showConsent) {
            ConsentSheet(isPresented: $showConsent) {
                vm.uploadLastYearHealth { result in
                    switch result {
                    case .success: uploadError = nil
                    case .failure(let e): uploadError = e.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func header() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppHeader()
            if vm.isLoading {
                ProgressView().padding(.top, 4)
            } else if let err = vm.errorMessage {
                Text(err).foregroundColor(.red).font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
