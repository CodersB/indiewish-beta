//
//  SwiftUIView.swift
//  Indie Wish
//
//  Created by Balu on 10/15/25.
//

import SwiftUI

@available(iOS 15.0, *)
public struct IndieWishFeedbackListView: View {
    @State private var items: [PublicItem] = []
    @State private var busy = false
    @State private var err: String?

    public init() {}

    public var body: some View {
        List {
            if let err { Text(err).foregroundColor(.red) }
            ForEach(items, id: \.id) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        if let d = item.description, !d.isEmpty {
                            Text(d).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("votes: \(item.votes ?? 0) · status: \(item.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await upvote(item.id) }
                    } label: {
                        Text("▲ \(item.votes ?? 0)")
                            .font(.caption).padding(6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
                .padding(.vertical, 4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle("Ideas")
    }

    private func load() async {
        err = nil; busy = true
        do {
            items = try await IndieWish.fetchPublicItems()
        } catch {
            err = error.localizedDescription
        }
        busy = false
    }

    private func upvote(_ id: String) async {
        err = nil; busy = true
        do {
            try await IndieWish.upvote(feedbackId: id)
            // optimistic refresh
            await load()
        } catch {
            err = error.localizedDescription
        }
        busy = false
    }
}

#Preview {
    IndieWishFeedbackListView()
}
