import Foundation
import LocalAuthentication

struct VaultDocument: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case image, pdf
    }

    enum Category: String, Codable, CaseIterable, Identifiable {
        case passport, visa, insurance, flight, hotel, ticket, id, health, money, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .passport: "Passport"
            case .visa: "Visa & Entry"
            case .insurance: "Insurance"
            case .flight: "Flights"
            case .hotel: "Hotels"
            case .ticket: "Tours & Tickets"
            case .id: "ID & Driving Licence"
            case .health: "Health & Vaccines"
            case .money: "Cards & Money"
            case .other: "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .passport: "person.text.rectangle.fill"
            case .visa: "checkmark.seal.fill"
            case .insurance: "cross.case.fill"
            case .flight: "airplane"
            case .hotel: "bed.double.fill"
            case .ticket: "ticket.fill"
            case .id: "car.fill"
            case .health: "syringe.fill"
            case .money: "creditcard.fill"
            case .other: "doc.fill"
            }
        }

        /// Whether an expiry date matters for this kind of document.
        var hasExpiry: Bool { [.passport, .visa, .insurance, .id, .money].contains(self) }
    }

    var id = UUID()
    var title: String
    var fileName: String
    var kind: Kind
    var createdAt = Date()
    // Added later; optional so older saved documents still load.
    var category: Category?
    var expiresAt: Date?
    var pageCount: Int?

    var resolvedCategory: Category { category ?? .other }

    enum ExpiryWarning: Equatable {
        case expired
        /// Thailand requires a passport valid for 6 months after arrival.
        case passportUnderSixMonths(Date)
        case soon(Date)
    }

    /// Warning relative to a trip (passport rule) or today.
    func expiryWarning(tripStart: Date?, now: Date = .now) -> ExpiryWarning? {
        guard let expiresAt else { return nil }
        if expiresAt < now { return .expired }
        let reference = max(tripStart ?? now, now)
        if resolvedCategory == .passport,
           let sixMonths = Calendar.current.date(byAdding: .month, value: 6, to: reference), expiresAt < sixMonths {
            return .passportUnderSixMonths(expiresAt)
        }
        if expiresAt.timeIntervalSince(now) < 45 * 24 * 3600 { return .soon(expiresAt) }
        return nil
    }
}

/// Passport, flight and hotel documents kept ONLY on this phone (never synced or shared),
/// encrypted at rest by iOS file protection and opened with Face ID / passcode.
@MainActor
final class DocumentVault: ObservableObject {
    static let shared = DocumentVault()

    @Published private(set) var documents: [VaultDocument] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var lastError: String?

    private var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Vault", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var indexURL: URL { directory.appending(path: "index.json") }

    func url(for document: VaultDocument) -> URL {
        directory.appending(path: document.fileName)
    }

    // MARK: Lock

    func unlock() async {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = "Set a passcode on this iPhone to use the documents vault."
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your travel documents")
            if success {
                isUnlocked = true
                lastError = nil
                loadIndex()
            }
        } catch {
            lastError = nil // Cancelled — stay locked quietly.
        }
    }

    func lock() {
        isUnlocked = false
        documents = []
    }

    // MARK: Documents

    func add(data: Data, title: String, kind: VaultDocument.Kind, category: VaultDocument.Category = .other, expiresAt: Date? = nil, pageCount: Int? = nil) {
        guard isUnlocked else { return }
        let fileName = "\(UUID().uuidString).\(kind == .pdf ? "pdf" : "jpg")"
        do {
            try data.write(to: directory.appending(path: fileName), options: [.atomic, .completeFileProtection])
            documents.insert(VaultDocument(title: title, fileName: fileName, kind: kind, category: category, expiresAt: expiresAt, pageCount: pageCount), at: 0)
            saveIndex()
        } catch {
            lastError = "Couldn't save the document."
        }
    }

    func update(_ document: VaultDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index] = document
        saveIndex()
    }

    func data(for document: VaultDocument) -> Data? {
        try? Data(contentsOf: url(for: document))
    }

    /// Documents with an expiry problem, read without unlocking (titles and dates only).
    func expiryAlerts(tripStart: Date?) -> [(VaultDocument, VaultDocument.ExpiryWarning)] {
        let list = isUnlocked ? documents : (try? JSONDecoder().decode([VaultDocument].self, from: Data(contentsOf: indexURL))) ?? []
        return list.compactMap { doc in doc.expiryWarning(tripStart: tripStart).map { (doc, $0) } }
    }

    func rename(_ document: VaultDocument, to title: String) {
        guard let index = documents.firstIndex(of: document) else { return }
        documents[index].title = title
        saveIndex()
    }

    func delete(_ document: VaultDocument) {
        try? FileManager.default.removeItem(at: url(for: document))
        documents.removeAll { $0.id == document.id }
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([VaultDocument].self, from: data) else {
            documents = []
            return
        }
        documents = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }
}
