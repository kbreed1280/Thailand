import Foundation
import Speech
import AVFoundation

/// Hold-to-talk speech recognition for one utterance in English or Thai.
final class SpeechTranscriber: NSObject, ObservableObject {
    enum TranscriberError: LocalizedError {
        case unavailable
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .unavailable: "Speech recognition for this language isn't available right now. It may need an internet connection."
            case .noMicrophone: "No microphone input is available."
            }
        }
    }

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Asks for speech + microphone permission. Returns the permission that was denied, if any.
    static func requestPermissions() async -> PermissionKind? {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .speech }
        let micGranted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micGranted = true
        case .undetermined: micGranted = await AVAudioApplication.requestRecordPermission()
        default: micGranted = false
        }
        return micGranted ? nil : .microphone
    }

    func start(languageCode: String) throws {
        stopEngine()
        let locale = Locale(identifier: languageCode == "th" ? "th-TH" : "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriberError.unavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TranscriberError.noMicrophone }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        transcript = ""

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            DispatchQueue.main.async { self?.transcript = text }
        }
    }

    /// Stops listening and returns what was heard (waits briefly for the final words).
    func stop() async -> String {
        guard isListening else { return transcript }
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(400))
        stopEngine()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        stopEngine()
        transcript = ""
    }

    private func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
