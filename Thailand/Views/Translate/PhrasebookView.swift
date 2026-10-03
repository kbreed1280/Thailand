import SwiftUI

/// Offline phrasebook with search, favorites, speak and Show mode.
struct PhrasebookView: View {
    @StateObject private var history = TranslationHistoryStore.shared
    @StateObject private var speaker = Speaker.shared
    @AppStorage(PoliteParticle.storageKey) private var particle: PoliteParticle = .khrap
    @State private var search = ""
    @State private var category: PhraseCategory?
    @State private var showContent: ShowModeContent?

    private var filtered: [Phrase] {
        let base = category.map(Phrasebook.phrases(in:)) ?? Phrasebook.all
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.english.localizedCaseInsensitiveContains(query)
                || $0.thai.contains(query)
                || $0.romanized.localizedCaseInsensitiveContains(query)
        }
    }

    private var favorites: [Phrase] {
        Phrasebook.all.filter(history.isFavorite)
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, title: "All", systemImage: "square.grid.2x2", colorHex: "#F4821C")
                        ForEach(PhraseCategory.allCases) { item in
                            chip(item, title: item.rawValue, systemImage: item.systemImage, colorHex: item.colorHex)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }

            if category == nil && search.isEmpty && !favorites.isEmpty {
                Section("★ Favorites") {
                    ForEach(favorites) { phrase in row(phrase) }
                }
            }

            if category == nil && search.isEmpty {
                ForEach(PhraseCategory.allCases) { item in
                    Section {
                        ForEach(Phrasebook.phrases(in: item)) { phrase in row(phrase) }
                    } header: {
                        Label(item.rawValue, systemImage: item.systemImage)
                    }
                }
            } else {
                Section {
                    ForEach(filtered) { phrase in row(phrase) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search phrases")
        .overlay {
            if filtered.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
    }

    private func chip(_ item: PhraseCategory?, title: String, systemImage: String, colorHex: String) -> some View {
        let selected = category == item
        let color = Color(hex: colorHex)
        return Button {
            withAnimation(.snappy) { category = item }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? .white : color)
                .background(selected ? color : color.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ phrase: Phrase) -> some View {
        let thai = phrase.thai(with: particle)
        let romanized = phrase.romanized(with: particle)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(phrase.english)
                    .font(.subheadline.weight(.semibold))
                Text(thai)
                    .font(.title3)
                Text(romanized)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                showContent = ShowModeContent(thai: thai, english: phrase.english, romanized: romanized)
            }

            VStack(spacing: 4) {
                Button {
                    speaker.speak(thai, languageCode: "th", slow: true)
                } label: {
                    Image(systemName: speaker.speakingText == thai ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.lagoon)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Speak \(phrase.english) in Thai")
                Button {
                    history.toggleFavorite(phrase)
                } label: {
                    Image(systemName: history.isFavorite(phrase) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(Theme.mango)
                        .frame(minWidth: 44, minHeight: 36)
                }
                .accessibilityLabel(history.isFavorite(phrase) ? "Remove from favorites" : "Add to favorites")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Tap the text to show it full screen.")
    }
}

#Preview {
    NavigationStack { PhrasebookView() }
}
