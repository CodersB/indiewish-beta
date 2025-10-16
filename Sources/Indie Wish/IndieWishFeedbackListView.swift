//
//  IndieWishFeedbackListView.swift
//  Indie Wish
//
//  Created by Balu on 10/15/25.
//

import SwiftUI

@available(iOS 15.0, *)
public struct IndieWishFeedbackListView: View {
    @State private var items: [PublicItem] = []
    @State private var err: String?

    // Track which items are currently sending an upvote
    @State private var votingIds: Set<String> = []

    // Persisted “already voted” guard (per-device)
    @State private var votedIds: Set<String> = IndieWishFeedbackListView.loadVotedIds()

    public init() {}

    public var body: some View {
        List {
            if let err {
                Text(err).foregroundColor(.red)
            }

            ForEach(items, id: \.id) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        if let d = item.description, !d.isEmpty {
                            Text(d)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("votes: \(item.votes ?? 0) · status: \(item.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    let isVoting = votingIds.contains(item.id)
                    let alreadyVoted = votedIds.contains(item.id)

                    Button {
                        Task { await upvote(item.id) }
                    } label: {
                        if isVoting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("▲ \(item.votes ?? 0)")
                                .font(.caption)
                                .padding(6)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isVoting || alreadyVoted)
                    .opacity(alreadyVoted ? 0.5 : 1.0)
                    .animation(.default, value: isVoting)
                }
                .padding(.vertical, 4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle("Ideas")
    }

    // MARK: - Data

    private func load() async {
        err = nil
        do {
            items = try await IndieWish.fetchPublicItems()
        } catch {
            err = error.localizedDescription
        }
    }

    // MARK: - Upvote (server-synced)

    private func upvote(_ id: String) async {
        guard !votedIds.contains(id), !votingIds.contains(id) else { return }
        err = nil
        votingIds.insert(id)

        // Optimistic: bump local count immediately
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].votes = (items[idx].votes ?? 0) + 1
        }

        do {
            // ✅ Fetch updated count from server
            let newCount = try await IndieWish.upvote(feedbackId: id)
            votedIds.insert(id)
            Self.saveVotedIds(votedIds)

            // ✅ Update item with actual server vote total
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].votes = newCount
            }
        } catch {
            // Rollback on failure
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].votes = max(0, (items[idx].votes ?? 1) - 1)
            }
            err = error.localizedDescription
        }

        votingIds.remove(id)
    }
    
    // MARK: - Local persistence for “already voted”

    private static let votedKey = "iw_voted_ids"

    private static func loadVotedIds() -> Set<String> {
        let arr = UserDefaults.standard.array(forKey: votedKey) as? [String] ?? []
        return Set(arr)
    }

    private static func saveVotedIds(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: votedKey)
    }
}

#Preview {
    IndieWishFeedbackListView()
}
