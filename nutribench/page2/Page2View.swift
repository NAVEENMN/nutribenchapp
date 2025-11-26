import SwiftUI
import UIKit

// Group of logs for a single calendar day
private struct DaySection: Identifiable {
    let id: Date          // start-of-day date
    let title: String     // "Today", "Yesterday", or "Wed, Nov 12"
    let logs: [FoodLog]
}

struct Page2View: View {
    @StateObject private var vm = Page2ViewModel()
    @State private var showLogSheet = false

    // track which rows are expanded (per FoodLog)
    @State private var expanded = Set<UUID>()
    
    // track which log is being edited (used with .sheet(item:))
    @State private var editingLog: FoodLog? = nil

    // trigger for ScrollViewReader to scroll to "Today"
    @State private var scrollToTodayToken: Int = 0

    // Header date formatter for non-today/yesterday days
    private let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent

            if vm.isLoading || vm.isSending {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                loaderCard
            }

            floatingButtons
        }
        .onAppear {
            print("👀 Page2View.onAppear")
            vm.ensureInitialHistoryLoaded()
        }
        // Sheet for adding a new log
        .sheet(isPresented: $showLogSheet) {
            LogFoodSheet(isPresented: $showLogSheet) { food, responseText, image in
                print("➕ LogFoodSheet.onSave '\(food)'")
                let newLog = vm.addLocal(food: food, response: responseText, image: image)
                expanded = Set([newLog.id])
            }
        }
        // Sheet for editing an existing log (driven by editingLog)
        // Sheet for editing an existing log (driven by editingLog)
        .sheet(item: $editingLog) { log in
            EditFoodSheet(
                original: log
            ) { newFood, newDate in
                vm.applyEdit(for: log, newFood: newFood, newDate: newDate)
            }
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header (matches Page 1)
            VStack(alignment: .leading, spacing: 0) {
                AppHeader()
                    .padding([.top, .horizontal])
                Divider()
            }

            Group {
                if vm.logs.isEmpty {
                    emptyState
                } else {
                    LogsListView(
                        vm: vm,
                        expanded: $expanded,
                        editingLog: $editingLog,
                        scrollToTodayToken: $scrollToTodayToken,
                        dayHeaderFormatter: dayHeaderFormatter
                    )
                }
            }

            if let err = vm.sendError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding([.horizontal, .top])
            }
        }
        .allowsHitTesting(!(vm.isSending || vm.isLoading))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No food logged yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Tap “Log Food” to add your first entry.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Floating buttons (Jump to Today + Log Food)

    private var floatingButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    // Jump to Today
                    Button {
                        print("📅 Jump to Today button tapped")
                        scrollToTodayToken += 1
                    } label: {
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 20))
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.12),
                                            radius: 8, x: 0, y: 4)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                            .accessibilityLabel("Jump to Today")
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Log Food
                    Button {
                        print("➕ Log Food button tapped")
                        showLogSheet = true
                    } label: {
                        Image("logfood")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.12),
                                            radius: 10, x: 0, y: 6)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                            .accessibilityLabel("Log food")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(vm.isSending)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 28)
            }
        }
        .allowsHitTesting(!vm.isSending)
    }

    // MARK: - Loader card

    private var loaderCard: some View {
        LoadingUIView()
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(.systemBackground).opacity(0.8))
    }
}

// MARK: - Logs list in its own View

private struct LogsListView: View {
    @ObservedObject var vm: Page2ViewModel

    @Binding var expanded: Set<UUID>
    @Binding var editingLog: FoodLog?
    @Binding var scrollToTodayToken: Int

    let dayHeaderFormatter: DateFormatter

    var body: some View {
        let sections = buildDaySections(from: vm.logs)

        return ScrollViewReader { proxy in
            List {
                ForEach(sections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.logs) { log in
                            let isOpen = expanded.contains(log.id)
                            logRow(log: log, isOpen: isOpen)
                                .contextMenu {
                                    Button(action: {
                                        print("✏️ contextMenu Edit tapped id=\(log.id)")
                                        editingLog = log
                                    }) {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(action: {
                                        print("🗑 contextMenu Delete tapped id=\(log.id)")
                                        vm.delete(log)
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            print("🧹 swipe-to-delete indexSet=\(Array(indexSet))")
                            indexSet
                                .map { section.logs[$0] }
                                .forEach { log in
                                    print("🧹 deleting id=\(log.id)")
                                    vm.delete(log)
                                }
                        }
                    }
                    .id(section.id)   // so we can scrollTo this day
                }
            }
            .listStyle(PlainListStyle())
            .onChange(of: scrollToTodayToken) { _ in
                let cal = Calendar.current
                if let todaySection = sections.first(where: { cal.isDateInToday($0.id) }) {
                    print("📅 Jump to Today → section \(todaySection.title)")
                    proxy.scrollTo(todaySection.id, anchor: .top)
                } else if let first = sections.first {
                    print("📅 Jump to first section \(first.title)")
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
        }
    }

    // MARK: - Day grouping helpers

    private func buildDaySections(from logs: [FoodLog]) -> [DaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: logs) { (log: FoodLog) in
            cal.startOfDay(for: log.date)
        }

        let sections: [DaySection] = grouped.map { (day, logsForDay) in
            let title = dayTitle(for: day)
            let sortedLogs = logsForDay.sorted { $0.date > $1.date }
            return DaySection(id: day, title: title, logs: sortedLogs)
        }

        // Sort days newest → oldest
        return sections.sorted { $0.id > $1.id }
    }

    private func dayTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return dayHeaderFormatter.string(from: day)
    }

    // MARK: - Single log row view

    // MARK: - Single log row view

    private func logRow(log: FoodLog, isOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // --- Header (time + title + carbs) ---
                HStack(alignment: .top, spacing: 12) {
                    // Time column
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.timeString(log.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 64, alignment: .leading)

                    // Middle column (title + carbs)
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
                        .frame(width: 20)
                        .animation(.easeInOut(duration: 0.18), value: isOpen)
                }
                .padding(.vertical, 6)

                // --- Expanded area ---
                if isOpen {
                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {

                        // Tiny inline thumbnail if cached
                        if let img = FoodImageStore.shared.loadLocalImage(for: log) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .clipped()
                                .cornerRadius(10)
                        }

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

                    // Hint about swipe / long-press
                    HStack {
                        Text("Swipe left on the card to delete or long-press for more options")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                    .padding(.top, 8)
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
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        // 👇 Make the entire card tappable to toggle expand/collapse
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                if isOpen {
                    expanded.remove(log.id)
                } else {
                    expanded.insert(log.id)
                }
            }
        }
    }
}

// MARK: - Edit sheet

struct EditFoodSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let original: FoodLog
    let onSave: (_ newFood: String, _ newDate: Date) -> Void

    @State private var foodText: String
    @State private var date: Date

    init(
        original: FoodLog,
        onSave: @escaping (_ newFood: String, _ newDate: Date) -> Void
    ) {
        self.original = original
        self.onSave = onSave
        _foodText = State(initialValue: original.originalQuery)
        _date = State(initialValue: original.date)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date & Time")) {
                    DatePicker("Local time", selection: $date)
                        .datePickerStyle(.compact)
                }

                Section(header: Text("What did you eat?")) {
                    TextField("e.g., Bagel with cream cheese", text: $foodText)
                        .autocapitalization(.sentences)
                        .disableAutocorrection(false)
                }
            }
            .navigationBarTitle("Edit Food", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    print("❌ EditFoodSheet Cancel tapped id=\(original.id)")
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let trimmed = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    print("💾 EditFoodSheet Save tapped id=\(original.id)")
                    onSave(trimmed, date)
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onAppear {
            print("👀 EditFoodSheet.onAppear id=\(original.id)")
        }
    }
}

// Classic previews
struct Page2View_Previews: PreviewProvider {
    static var previews: some View { Page2View() }
}
