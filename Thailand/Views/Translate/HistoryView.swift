import SwiftUI

/// Past translations (kept only on this phone) with favorites first.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var history = TranslationHistoryStore.shared
    @StateObject private var speaker = Speaker.shared
    @State private var showContent: ShowModeContent?
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                if !history.favoriteRecords.isEmpty {
                    Section("★ Favorites") {
                        ForEach(history.favoriteRecords) { row($0) }
                    }
                }
                Section("Recent") {
                    ForEach(history.records.filter { !$0.isFavorite }) { row($0) }
                }
            }
            .overlay {
                if history.records.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.arrow.circlepath",
                        title: "No Translations Yet",
                        message: "Everything you translate is saved here so you can show it again later, even offline."
                    )
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .disabled(history.records.allSatisfy(\.isFavorite))
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear history?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { history.clearHistory() }
            } message: {
                Text("Favorites are kept.")
            }
            .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
        }
    }

    private func row(_ record: TranslationRecord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.englishText).font(.subheadline.weight(.semibold))
                Text(record.thaiText).font(.title3)
                Text(record.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                showContent = ShowModeContent(thai: record.thaiText, english: record.englishText, romanized: ThaiText.romanize(record.thaiText))
            }
            Button {
                speaker.speak(record.thaiText, languageCode: "th")
            } label: {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.lagoon)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speak in Thai")
        }
        .swipeActions(edge: .leading) {
            Button {
                history.toggleFavorite(record)
            } label: {
                Label(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(Theme.mango)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                history.delete(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    HistoryView()
}
