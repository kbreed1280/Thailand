import Foundation
import Observation
import Translation

enum TranslationDirection: String, CaseIterable, Identifiable {
    case englishToThai
    case thaiToEnglish

    var id: String { rawValue }

    static let english = Locale.Language(identifier: "en")
    static let thai = Locale.Language(identifier: "th")

    var source: Locale.Language { self == .englishToThai ? Self.english : Self.thai }
    var target: Locale.Language { self == .englishToThai ? Self.thai : Self.english }
    var sourceCode: String { self == .englishToThai ? "en" : "th" }
    var targetCode: String { self == .englishToThai ? "th" : "en" }
    var sourceName: String { self == .englishToThai ? "English" : "Thai" }
    var targetName: String { self == .englishToThai ? "Thai" : "English" }
    var reversed: TranslationDirection { self == .englishToThai ? .thaiToEnglish : .englishToThai }
    var isFromThai: Bool { self == .thaiToEnglish }
}

/// Drives Apple's on-device Translation framework.
///
/// `TranslationSession`s only exist inside SwiftUI's `.translationTask` modifier, so a view
/// attaches `.translationTask(model.configuration) { await model.run($0) }` and calls
/// `translate(_:direction:)`; changing/invalidating the configuration triggers `run`.
@MainActor
@Observable
final class TranslatorModel {
    var configuration: TranslationSession.Configuration?
    private(set) var output = ""
    private(set) var isTranslating = false
    private(set) var errorMessage: String?
    private(set) var direction: TranslationDirection = .englishToThai

    /// Called after every successful translation with (source text, result, direction).
    var onTranslated: (@MainActor (String, String, TranslationDirection) -> Void)?

    private var pendingText: String?

    func translate(_ text: String, direction: TranslationDirection) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            output = ""
            return
        }
        pendingText = trimmed
        self.direction = direction
        isTranslating = true
        errorMessage = nil

        if let current = configuration, current.source == direction.source, current.target == direction.target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: direction.source, target: direction.target)
        }
    }

    func clear() {
        output = ""
        errorMessage = nil
    }

    func run(_ session: TranslationSession) async {
        guard let text = pendingText else {
            isTranslating = false
            return
        }
        pendingText = nil
        do {
            let response = try await session.translate(text)
            output = response.targetText
            onTranslated?(text, response.targetText, direction)
        } catch {
            errorMessage = "Couldn't translate. If you're offline, download Thai first (banner at the top of this screen)."
        }
        isTranslating = false
    }
}

/// Checks whether English ⇄ Thai is downloaded for offline use, and downloads it.
@MainActor
@Observable
final class LanguagePackModel {
    enum State { case checking, installed, needsDownload, unsupported }

    private(set) var state: State = .checking
    var prepareConfiguration: TranslationSession.Configuration?

    func refresh() async {
        let status = await LanguageAvailability().status(from: TranslationDirection.english, to: TranslationDirection.thai)
        switch status {
        case .installed: state = .installed
        case .supported: state = .needsDownload
        case .unsupported: state = .unsupported
        @unknown default: state = .needsDownload
        }
    }

    func download() {
        prepareConfiguration = TranslationSession.Configuration(source: TranslationDirection.english, target: TranslationDirection.thai)
    }

    func prepare(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
        prepareConfiguration = nil
        await refresh()
    }
}
