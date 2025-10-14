//
//  SwiftUIView.swift
//  Indie Wish
//
//  Created by Balu on 10/14/25.
//

import SwiftUI

@available(iOS 15.0, *)
public struct IndieWishFeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var desc: String = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var success = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Title")) {
                    TextField("e.g. App crashed on save", text: $title)
                        .textInputAutocapitalization(.sentences)
                }
                Section(header: Text("Description (optional)")) {
                    TextEditor(text: $desc)
                        .frame(minHeight: 120)
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }

                if success {
                    Section {
                        Label("Thanks! Feedback sent.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Send Feedback")
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
            try await IndieWish.sendFeedback(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : desc
            )
            success = true
            // optionally auto-dismiss after a second
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
        busy = false
    }
}
