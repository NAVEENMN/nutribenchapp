import SwiftUI
import UIKit

struct Page2View: View {
    @StateObject private var vm = Page2ViewModel()
    @State private var showLogSheet = false

    // track which rows are expanded
    @State private var expanded = Set<UUID>()

    var body: some View {
        ZStack {
            // ---- Main content ----
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
                            let isOpen = expanded.contains(log.id)

                            VStack(alignment: .leading, spacing: 0) {
                                // Card content
                                VStack(alignment: .leading, spacing: 10) {

                                    // --- Header (date | food+carbs | chevron) ---
                                    HStack(alignment: .top, spacing: 12) {
                                        // Date/time column with a fixed width → perfect alignment
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vm.dateString(log.date))
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Text(vm.timeString(log.date))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(width: 96, alignment: .leading)

                                        // Middle column (title + carbs) gets priority
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(log.food)
                                                .font(.body)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.9)

                                            Text("Carbs: \(log.carbsText)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        }
                                        .layoutPriority(1)

                                        Spacer(minLength: 8)

                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.secondary)
                                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                                            .frame(width: 20) // keeps it from stealing width
                                            .animation(.easeInOut(duration: 0.18), value: isOpen)
                                    }
                                    .padding(.vertical, 6)

                                    // --- Expanded area ---
                                    if isOpen {
                                        Divider().padding(.vertical, 4)

                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Original:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(log.originalQuery)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)

                                            if let steps = log.serverResponse, !steps.isEmpty {
                                                Text("Calculation steps:")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)

                                                ScrollView {
                                                    if #available(iOS 15.0, *) {
                                                        Text(steps)
                                                            .font(.footnote)
                                                            .foregroundColor(.secondary)
                                                            .textSelection(.enabled)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    } else {
                                                        Text(steps)
                                                            .font(.footnote)
                                                            .foregroundColor(.secondary)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                }
                                                .frame(minHeight: 140, maxHeight: 320)
                                                .padding(8)
                                                .background(Color(.secondarySystemBackground))
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            }
                                        }
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity.combined(with: .move(edge: .top))
                                        ))
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        if isOpen { expanded.remove(log.id) } else { expanded.insert(log.id) }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            // Card spacing + clear list background for edge alignment
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .animation(.easeInOut(duration: 0.22), value: expanded)
                            .contextMenu {
                                Button(action: { vm.beginEdit(log) }) { Label("Edit", systemImage: "pencil") }
                                Button(action: { vm.delete(log) })    { Label("Delete", systemImage: "trash") }
                            }
                        }
                        // Enable the standard iOS 14 delete swipe
                        .onDelete { indexSet in
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
            }
            .allowsHitTesting(!(vm.isSending || vm.isLoading))

            // ---- Loading overlay (uses your LoadingUIView) ----
            if vm.isLoading || vm.isSending {
                // Dim layer fills entire screen
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                // Centered loader card
                loaderCard
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2),
                               value: vm.isLoading || vm.isSending)
            }

            // ---- Floating add button (iOS14-safe overlay via Spacer layout) ----
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showLogSheet = true
                    } label: {
                        Image("logfood")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                            .accessibilityLabel("Log food")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(vm.isSending)
                    .padding(.trailing, 20)
                    .padding(.bottom, 28) // keep above tab bar / home indicator
                }
            }
            .allowsHitTesting(!vm.isSending) // still tappable when not sending
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

    // Centered card with a soft background and your fruit/leaf animation
    private var loaderCard: some View {
        LoadingUIView()
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(.systemBackground).opacity(0.8))
    }
}

// Classic previews for older toolchains
struct Page2View_Previews: PreviewProvider {
    static var previews: some View { Page2View() }
}
