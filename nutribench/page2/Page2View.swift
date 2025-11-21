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
    
    // track which day sections are expanded (per start-of-day Date)
    @State private var expandedDays = Set<Date>()
    
    // track which log is being edited
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
                    let sections = buildDaySections(from: vm.logs)

                    ScrollViewReader { proxy in
                        List {
                            ForEach(sections) { section in
                                Section(header: dayHeader(for: section)) {
                                    if expandedDays.contains(section.id) {
                                        ForEach(section.logs) { log in
                                            let isOpen = expanded.contains(log.id)
                                            logRow(log: log, isOpen: isOpen)
                                                .contextMenu {
                                                    Button(action: {
                                                        editingLog = log
                                                    }) {
                                                        Label("Edit", systemImage: "pencil")
                                                    }
                                                    Button(action: {
                                                        vm.delete(log)
                                                    }) {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                }
                                        }
                                        // Swipe-to-delete within this day
                                        .onDelete { indexSet in
                                            indexSet
                                                .map { section.logs[$0] }
                                                .forEach { vm.delete($0) }
                                        }
                                    }
                                }
                                .id(section.id)   // so we can scrollTo this day
                            }
                        }
                        .listStyle(PlainListStyle())
                        // when Jump-to-Today is tapped
                        .onChange(of: scrollToTodayToken) { _ in
                            let cal = Calendar.current
                            if let todaySection = sections.first(where: { cal.isDateInToday($0.id) }) {
                                proxy.scrollTo(todaySection.id, anchor: .top)
                            } else if let first = sections.first {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
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

            // ---- Loading overlay (uses your LoadingUIView) ----
            if vm.isLoading || vm.isSending {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                loaderCard
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2),
                               value: vm.isLoading || vm.isSending)
            }

            // ---- Floating buttons (Jump to Today + Log Food) ----
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        // Jump to Today
                        Button {
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
        .onAppear {
            vm.ensureInitialHistoryLoaded()
        }
        // Auto-expand only Today + Yesterday on first load
        .onChange(of: vm.logs) { logs in
            // only do this once, so we don't override user toggles
            guard expandedDays.isEmpty else { return }
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)

            var initial = Set<Date>()
            for log in logs {
                let d = cal.startOfDay(for: log.date)
                if d == today || (yesterday != nil && d == yesterday) {
                    initial.insert(d)
                }
            }
            expandedDays = initial
        }
        .sheet(isPresented: $showLogSheet) {
            LogFoodSheet(isPresented: $showLogSheet) { food, responseText in
                let newLog = vm.addLocal(food: food, response: responseText)
                // collapse all rows; expand just the newest one
                expanded = Set([newLog.id])
            }
        }
        // Edit sheet for editing an existing log (time + text)
        .sheet(item: $editingLog) { log in
            EditFoodSheet(
                original: log
            ) { newFood, newDate in
                vm.applyEdit(for: log, newFood: newFood, newDate: newDate)
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
        if cal.isDateInToday(day) {
            return "Today"
        }
        if cal.isDateInYesterday(day) {
            return "Yesterday"
        }
        return dayHeaderFormatter.string(from: day)
    }

    private func dayHeader(for section: DaySection) -> some View {
        let isOpen = expandedDays.contains(section.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen {
                    expandedDays.remove(section.id)
                } else {
                    expandedDays.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.headline)

                // Small count badge
                Text("\(section.logs.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())

                Spacer()

                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

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
                    
                    // Inline Edit button + hint about swipe delete
                    HStack {
                        Button {
                            editingLog = log
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Spacer()
                        Text("Swipe left on the card to delete")
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

// MARK: - Edit sheet (unchanged behavior)

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
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let trimmed = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    onSave(trimmed, date)
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// Classic previews
struct Page2View_Previews: PreviewProvider {
    static var previews: some View { Page2View() }
}
