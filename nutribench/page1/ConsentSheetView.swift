import SwiftUI

struct ConsentSheet: View {
    @Binding var isPresented: Bool
    @State private var consent = false

    let onContinue: () -> Void   // called when user taps Continue with consent ON

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // UCSB Header
                    Text("UCSB")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Research Consent Form")
                        .font(.title2).bold()
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Card body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("""
Thank you for considering participation in our research study. This study will collect health-related data from your Apple Health app. Data collected may include, but is not limited to:
""")
                        .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 6) {
                            bullet("Activity (steps, distance, flights climbed)")
                            bullet("Heart Rate and Heart Rate Variability")
                            bullet("Sleep Patterns")
                            bullet("Nutrition and Calorie Intake")
                            bullet("Body Measurements (weight, BMI, etc.)")
                            bullet("All other categories available through Apple Health")
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Consent toggle
                    HStack {
                        Text("I consent to participate").bold()
                        Spacer()
                        Toggle("", isOn: $consent)
                            .labelsHidden()
                    }
                    .padding(.vertical, 8)

                    // Continue button
                    Button {
                        onContinue()
                        isPresented = false
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!consent)
                }
                .padding()
            }
            .navigationBarItems(leading:
                Button("Close") { isPresented = false }
            )
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
