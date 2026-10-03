import AVFoundation

/// Reads text aloud in Thai or English with the system voices.
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var speakingText: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// True when iOS has a voice for the language (Thai may need a download on some phones).
    static func hasVoice(for languageCode: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(languageCode) }
    }

    func speak(_ text: String, languageCode: String, slow: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            if speakingText == trimmed {
                speakingText = nil
                return
            }
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode == "th" ? "th-TH" : "en-US")
        utterance.rate = slow ? AVSpeechUtteranceDefaultSpeechRate * 0.75 : AVSpeechUtteranceDefaultSpeechRate * 0.92
        speakingText = trimmed
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingText = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speakingText = nil }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speakingText = nil }
    }
}
