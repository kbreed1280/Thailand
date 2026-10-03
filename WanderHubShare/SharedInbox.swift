import Foundation
import Security

/// Links shared into WanderHub from other apps (Share → WanderHub), waiting until the app opens.
/// Stored in a keychain group shared by the app and its Share extension.
/// NOTE: identical copies live at Thailand/Services/Video/SharedInbox.swift and
/// WanderHubShare/SharedInbox.swift. Keep both in sync.
struct SharedLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var text: String?
    var sharedAt = Date()
}

enum SharedInbox {
    /// "<Team ID>.com.kbreed.thailandtrip.shared": must match keychain-access-groups in both targets.
    static let accessGroup = "A64T2JKGRD.com.kbreed.thailandtrip.shared"
    private static let service = "com.kbreed.thailandtrip.shared-links"
    private static let account = "inbox"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup]
    }

    static func load() -> [SharedLink] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([SharedLink].self, from: data)) ?? []
    }

    static func save(_ links: [SharedLink]) {
        guard let data = try? JSONEncoder().encode(links) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func append(url: URL, text: String?) {
        var links = load()
        guard !links.contains(where: { $0.url == url }) else { return }
        links.append(SharedLink(url: url, text: text))
        save(links)
    }

    static func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    /// First http(s) link in a block of text.
    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }
}
