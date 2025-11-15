import SwiftUI

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

    // Return both food and response to the parent so it can save locally
    let onSave: (_ food: String, _ response: String) -> Void

    private let endpoint = URL(string: "https://5lcj2njvoq4urxszpj7lqoatxy0gslkf.lambda-url.us-west-2.on.aws/")!

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
                        // iOS 14-friendly capitalization API
                        .autocapitalization(.sentences)
                        .disableAutocorrection(false)
                }

                // iOS 14 style Section with a dynamic footer view
                Section(
                    footer:
                        Group {
                            if skipServerCall {
                                Text("Save your changes. We’ll re-estimate carbs and update this entry.")
                            } else if let err = sendError {
                                Text(err).foregroundColor(.red)
                            } else if !responseText.isEmpty {
                                Text("Carb estimate received. Saving entry…")
                            } else {
                                Text("We’ll estimate carbs and save this entry.")
                            }
                        }
                ) {
                    Button {
                        if skipServerCall {
                            // Edit mode: just return the text; ViewModel will handle inference + update_event.
                            let trimmed = foodText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            onSave(trimmed, "")
                            isPresented = false
                        } else {
                            // Add mode: infer via Lambda, then auto-save.
                            sendToLambda(food: foodText)
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
                if foodText.isEmpty { foodText = initialText }   // prefill once
            }
        }
    }

    // MARK: - Networking (Add mode)

    /// POST {"body":"<food>"} (UTF-8 JSON) → parse {"statusCode":200,"body":<string or object>}
    private func sendToLambda(food: String) {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        sendError = nil
        responseText = ""

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["body": trimmed]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            self.sendError = "Could not encode request."
            self.isSending = false
            return
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.isSending = false

                if let err = err {
                    self.sendError = err.localizedDescription
                    return
                }
                guard let data = data else {
                    self.sendError = "Empty response."
                    return
                }

                func finishAndDismissIfReady() {
                    let foodClean = trimmed
                    if !foodClean.isEmpty, !self.responseText.isEmpty {
                        self.onSave(foodClean, self.responseText)
                        self.isPresented = false
                    }
                }

                do {
                    let any = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = any as? [String: Any] {
                        let status = dict["statusCode"] as? Int ?? 0
                        if status != 200 {
                            self.sendError = "Bad status: \(status)"
                            return
                        }
                        if let bodyStr = dict["body"] as? String {
                            print("🍱 RAW SERVER BODY (String):\n\(bodyStr)")
                            self.responseText = bodyStr
                            finishAndDismissIfReady()
                            return
                        } else if let bodyObj = dict["body"] as? [String: Any] {
                            let data2 = try JSONSerialization.data(withJSONObject: bodyObj)
                            let bodyStr = String(data: data2, encoding: .utf8) ?? ""
                            print("🍱 RAW SERVER BODY (Dict→String):\n\(bodyStr)")
                            self.responseText = bodyStr
                            finishAndDismissIfReady()
                            return
                        } else if let bodyArr = dict["body"] as? [Any] {
                            let data2 = try JSONSerialization.data(withJSONObject: bodyArr)
                            let bodyStr = String(data: data2, encoding: .utf8) ?? ""
                            self.responseText = bodyStr
                            finishAndDismissIfReady()
                            return
                        }
                    }

                    if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        self.responseText = raw
                        finishAndDismissIfReady()
                    } else {
                        self.sendError = "Unexpected response format."
                    }
                } catch {
                    if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                        self.responseText = raw
                        finishAndDismissIfReady()
                    } else {
                        self.sendError = "Data could not be read (invalid format)."
                    }
                }
            }
        }.resume()
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
