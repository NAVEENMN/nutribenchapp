import SwiftUI

struct FoodPhotosView: View {
    @State private var logs: [FoodLog] = []
    @State private var selectedLog: FoodLog? = nil
    @State private var selectedImage: UIImage? = nil

    // 3-column grid
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                AppHeader(title: "Food Photos")
                    .padding([.top, .horizontal])
                Divider()
            }

            if logs.isEmpty {
                Text("No food photos yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(logsWithImages(), id: \.id) { log in
                            FoodPhotoCell(log: log) {
                                loadImage(for: log) { img in
                                    self.selectedLog = log
                                    self.selectedImage = img
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .onAppear {
            // Simple: load from local cache
            logs = FoodLogStore.shared.load().sorted { $0.date > $1.date }
        }
        .sheet(item: $selectedLog) { log in
            FoodPhotoDetailSheet(log: log, image: selectedImage)
        }
    }

    private func logsWithImages() -> [FoodLog] {
        logs.filter { FoodImageStore.shared.loadLocalImage(for: $0) != nil || $0.imageS3URL != nil }
    }

    private func loadImage(for log: FoodLog, completion: @escaping (UIImage?) -> Void) {
        if let img = FoodImageStore.shared.loadLocalImage(for: log) {
            completion(img); return
        }
        FoodImageStore.shared.loadOrDownloadImage(for: log, completion: completion)
    }
}

private struct FoodPhotoCell: View {
    let log: FoodLog
    let onTap: () -> Void

    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = false

    var body: some View {
        ZStack {
            // Background / placeholder
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: cellSize, height: cellSize)

            // Image (when ready)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
                    .transition(.opacity)
            }

            // Loading overlay
            if isLoading && image == nil {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear {
            guard image == nil, !isLoading else { return }

            // If already cached locally, show immediately (no spinner)
            if let local = FoodImageStore.shared.loadLocalImage(for: log) {
                self.image = local
                return
            }

            // Otherwise download -> show spinner
            isLoading = true
            FoodImageStore.shared.loadOrDownloadImage(for: log) { img in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.image = img
                    }
                    self.isLoading = false
                }
            }
        }
    }

    private var cellSize: CGFloat {
        UIScreen.main.bounds.width / 3 - 6
    }
}

private struct FoodPhotoDetailSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let log: FoodLog
    let initialImage: UIImage?

    @State private var image: UIImage? = nil
    @State private var isLoadingImage: Bool = false

    // Local formatters
    private static let dfDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()

    private static let dfTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "h:mm a"
        return f
    }()

    init(log: FoodLog, image: UIImage?) {
        self.log = log
        self.initialImage = image
        _image = State(initialValue: image)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageSection

                    // NEW: timestamp row
                    Text("\(Self.dfDate.string(from: log.date)) • \(Self.dfTime.string(from: log.date))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(log.food)
                        .font(.headline)

                    Text("Carbs: \(log.carbsText)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(log.originalQuery)
                        .font(.body)

                    if let steps = log.serverResponse, !steps.isEmpty {
                        Text("Calculation steps")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(steps)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationBarTitle("Food Log", displayMode: .inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onAppear {
            // If we didn't get an image passed in, try to load from cache/S3.
            if image == nil && !isLoadingImage {
                isLoadingImage = true
                if let local = FoodImageStore.shared.loadLocalImage(for: log) {
                    self.image = local
                    self.isLoadingImage = false
                } else {
                    FoodImageStore.shared.loadOrDownloadImage(for: log) { img in
                        DispatchQueue.main.async {
                            self.image = img
                            self.isLoadingImage = false
                        }
                    }
                }
            }
        }
    }

    private var imageSection: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
            } else if isLoadingImage {
                ZStack {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 240)
                        .cornerRadius(12)
                    ProgressView()
                }
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 240)
                    .cornerRadius(12)
            }
        }
    }
}

