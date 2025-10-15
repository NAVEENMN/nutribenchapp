import SwiftUI
import UIKit

struct Page2View: View {
    @StateObject private var vm = Page2ViewModel()
    @State private var showLogSheet = false

    // track which rows are expanded
    @State private var expanded = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header (matches Page 1)
            VStack(alignment: .leading, spacing: 0) {
                AppHeader()
                    .padding([.top, .horizontal])
                Divider()
            }

            if vm.logs.isEmpty {
                VStack(spacing: 12) {
                    Text("No food logged yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tap “Log Food” to add your first entry.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                // Date/time column
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.dateString(log.date))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(vm.timeString(log.date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Divider()

                                // Food + carbs column
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.food).font(.body)
                                    HStack(spacing: 8) {
                                        Text("Carbs: \(log.carbsText)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: expanded.contains(log.id) ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }

                            // Expanded content
                            if expanded.contains(log.id) {
                                Divider().padding(.vertical, 6)
                                VStack(alignment: .leading, spacing: 8) {
                                    // original user query
                                    Text(log.originalQuery)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    // readable calculation steps
                                    if let steps = log.serverResponse, !steps.isEmpty {
                                        if #available(iOS 15.0, *) {
                                            Text(steps)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                                .textSelection(.enabled)
                                        } else {
                                            Text(steps)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if expanded.contains(log.id) { expanded.remove(log.id) }
                            else { expanded.insert(log.id) }
                        }
                        // iOS 14 alternative to swipe actions
                        .contextMenu {
                            Button(action: { vm.beginEdit(log) }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(action: { vm.delete(log) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    // Enable the standard iOS 14 delete swipe
                    .onDelete { indexSet in
                        // delete each selected row
                        indexSet
                            .map { vm.logs[$0] }
                            .forEach { vm.delete($0) }
                    }
                }
                .listStyle(PlainListStyle())
            }

            if let err = vm.sendError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding([.horizontal, .top])
            }

            // Bottom action bar
            VStack {
                Button {
                    showLogSheet = true
                } label: {
                    HStack {
                        if vm.isSending { ProgressView().padding(.trailing, 6) }
                        Label("Log Food", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(vm.isSending)
            }
            .padding()
        }
        .onAppear { vm.loadHistory() }
        .sheet(isPresented: $showLogSheet) {
            // Sheet auto-saves on success and dismisses itself.
            LogFoodSheet(isPresented: $showLogSheet) { food, responseText in
                let newLog = vm.addLocal(food: food, response: responseText)
                // collapse all others; expand the newest one
                expanded = Set([newLog.id])
            }
        }
    }
}

// Classic previews for older toolchains
struct Page2View_Previews: PreviewProvider {
    static var previews: some View { Page2View() }
}
