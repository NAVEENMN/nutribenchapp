import SwiftUI
import UIKit

struct LogFoodSheet: View {
    @Binding var isPresented: Bool
    var initialText: String = ""          // prefill when editing
    var skipServerCall: Bool = false      // true for Edit (save text only)

    @State private var foodText: String = ""
    @State private var now: Date = Date()

    // Networking state
    @State private var isSending = false
    @State private var sendError: String?
    @State private var responseText: String = ""   // parsed "body" from lambda

    // NEW: image picking state
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker: Bool = false

    // Return food, response, and optional image
    let onSave: (_ food: String, _ response: String, _ image: UIImage?) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Local Time")) {
                    HStack {
                        Text(dateString(now))
                        Spacer()
                        Text(timeString(now)).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("What did you eat?")) {
                    TextField("e.g., Bagel with cream cheese", text: $foodText)
                        .autocapitalization(.sentences)
                        .disableAutocorrection(false)

                    HStack {
                        Button {
                            showImagePicker = true
                        } label: {
                            Image(systemName: "camera")
                                .font(.system(size: 18, weight: .medium))
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if let img = selectedImage {
                            Spacer(minLength: 8)
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipped()
                                .cornerRadius(8)
                        }

                        Spacer()
                    }
                }

                Section(
                    footer:
                        Group {
                            if skipServerCall {
                                Text("Save your changes. We'll re-estimate carbs and update this entry.")
                            } else if let err = sendError {
                                Text(err).foregroundColor(.red)
                            } else if !responseText.isEmpty {
                                Text("Carb estimate received. Saving entry…")
                            } else {
                                Text("We'll estimate carbs and save this entry.")
                            }
                        }
                ) {
                    Button {
                        let trimmed = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        if skipServerCall {
                            onSave(trimmed, "", selectedImage)
                            isPresented = false
                        } else {
                            sendToLambda(food: trimmed)
                        }
                    } label: {
                        HStack {
                            if isSending { ProgressView().padding(.trailing, 6) }
                            Text(skipServerCall ? "Save" : "Log Food")
                        }
                    }
                    .disabled(foodText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }

            }
            .navigationBarTitle(skipServerCall ? "Edit Food" : "Log Food", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false }
            )
            .onAppear {
                now = Date()
                if foodText.isEmpty { foodText = initialText }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary) { img in
                self.selectedImage = img
            }
        }
    }

    // MARK: - Networking (Add mode)

    private func sendToLambda(food: String) {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Run the whole flow on the main actor so state updates are safe.
        Task { @MainActor in
            self.isSending = true
            self.sendError = nil
            self.responseText = ""

            do {
                // Call shared NutritionService → unwraps Lambda {statusCode, body}
                let body = try await NutritionService.shared.estimate(for: trimmed)
                self.responseText = body

                let foodClean = trimmed
                // Mirror the previous behavior: only save if we have both food & body
                if !foodClean.isEmpty, !body.isEmpty {
                    self.onSave(foodClean, body, self.selectedImage)
                    self.isPresented = false
                }
            } catch {
                self.sendError = error.localizedDescription
            }

            self.isSending = false
        }
    }

    // MARK: - Formatters
    private func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "EEE, MMM d, yyyy"; return f.string(from: d)
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}

