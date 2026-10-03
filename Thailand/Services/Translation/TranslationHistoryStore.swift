import Foundation

struct TranslationRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var source: String
    var result: String
    var fromThai: Bool
    var date = Date()
    var isFavorite = false

    var thaiText: String { fromThai ? source : result }
    var englishText: String { fromThai ? result : source }
}

/// Personal translation history and favorite phrases. Kept on this phone only (never shared).
@MainActor
final class TranslationHistoryStore: ObservableObject {
    static let shared = TranslationHistoryStore()

    @Published private(set) var records: [TranslationRecord] = []
    @Published private(set) var favoritePhraseIDs: Set<String> = []

    private let maxRecords = 200
    private let favoritesKey = "favoritePhraseIDs"

    private var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "translation-history.json")
    }

    init() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) {
            records = decoded
        }
        favoritePhraseIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    var favoriteRecords: [TranslationRecord] { records.filter(\.isFavorite) }

    func add(source: String, result: String, fromThai: Bool) {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !result.isEmpty else { return }
        // Don't stack duplicates of the most recent translation.
        if let first = records.first, first.source == trimmedSource, first.fromThai == fromThai { return }
        records.insert(TranslationRecord(source: trimmedSource, result: result, fromThai: fromThai), at: 0)
        // Keep favorites even when trimming old history.
        if records.count > maxRecords {
            let favorites = records.filter(\.isFavorite)
            records = Array(records.filter { !$0.isFavorite }.prefix(maxRecords - favorites.count)) + favorites
            records.sort { $0.date > $1.date }
        }
        persist()
    }

    func toggleFavorite(_ record: TranslationRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        persist()
    }

    func delete(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func clearHistory() {
        records.removeAll { !$0.isFavorite }
        persist()
    }

    func isFavorite(_ phrase: Phrase) -> Bool { favoritePhraseIDs.contains(phrase.id) }

    func toggleFavorite(_ phrase: Phrase) {
        if favoritePhraseIDs.contains(phrase.id) {
            favoritePhraseIDs.remove(phrase.id)
        } else {
            favoritePhraseIDs.insert(phrase.id)
        }
        UserDefaults.standard.set(Array(favoritePhraseIDs), forKey: favoritesKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
