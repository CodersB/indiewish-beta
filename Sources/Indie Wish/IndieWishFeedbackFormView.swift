import SwiftUI

@available(iOS 15.0, *)
public struct IndieWishFeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var desc = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var success = false
    @State private var isBug = false   // false = feature, true = bug

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Feedback type")) {
                    Picker("What’s this about?", selection: $isBug) {
                        Text("🚀 Feature Request").tag(false)
                        Text("🐞 Bug Report").tag(true)
                    }
                }

                Section(header: Text(isBug ? "Issue title" : "Title")) {
                    TextField(isBug ? "e.g. Crash when saving" : "e.g. Sort tasks by priority", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section(header: Text(isBug ? "Describe the issue" : "Details")) {
                    TextEditor(text: $desc)
                        .frame(minHeight: 120)
                }

                if let errorText {
                    Section { Text(errorText).foregroundColor(.red) }
                }

                if success {
                    Section {
                        Label("Thank you! Your feedback was sent.", systemImage: "checkmark.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .navigationTitle(isBug ? "Bug Report" : "Feature Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func send() async {
        errorText = nil
        success = false
        busy = true
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDesc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = isBug ? "bug" : "feature"

            try await IndieWish.sendFeedback(
                title: trimmedTitle,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                category: category
            )

            success = true
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        } catch {
            errorText = error.localizedDescription
        }
        busy = false
    }
}

#Preview { IndieWishFeedbackFormView() }
