import Foundation
import LocalAuthentication

struct VaultDocument: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case image, pdf
    }

    var id = UUID()
    var title: String
    var fileName: String
    var kind: Kind
    var createdAt = Date()
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

    func add(data: Data, title: String, kind: VaultDocument.Kind) {
        guard isUnlocked else { return }
        let fileName = "\(UUID().uuidString).\(kind == .pdf ? "pdf" : "jpg")"
        do {
            try data.write(to: directory.appending(path: fileName), options: [.atomic, .completeFileProtection])
            documents.insert(VaultDocument(title: title, fileName: fileName, kind: kind), at: 0)
            saveIndex()
        } catch {
            lastError = "Couldn't save the document."
        }
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
