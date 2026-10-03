import SwiftUI
import Translation

/// Split-screen conversation. The top half is upside-down so the person across from you reads
/// Thai and talks in Thai; you read English and talk in English on the bottom half.
struct ConversationView: View {
    @StateObject private var transcriber = SpeechTranscriber()
    @StateObject private var speaker = Speaker.shared
    @State private var translator = TranslatorModel()

    /// Last thing each side should read (already in their language).
    @State private var thaiSideText = "กดปุ่มไมค์ค้างไว้แล้วพูดภาษาไทย"
    @State private var englishSideText = "Hold the mic and speak English. Your partner holds theirs to reply in Thai."
    @State private var speakingSide: TranslationDirection?
    @State private var deniedPermission: PermissionKind?
    @State private var voiceError: String?

    var body: some View {
        VStack(spacing: 0) {
            half(
                text: thaiSideText,
                caption: speakingSide == .thaiToEnglish && transcriber.isListening ? transcriber.transcript : nil,
                isListening: transcriber.isListening && speakingSide == .thaiToEnglish,
                micLabel: "กดค้างเพื่อพูด",
                direction: .thaiToEnglish,
                tint: Theme.lagoon
            )
            .rotationEffect(.degrees(180))

            Divider().overlay(Theme.mango).frame(height: 2)

            half(
                text: englishSideText,
                caption: speakingSide == .englishToThai && transcriber.isListening ? transcriber.transcript : nil,
                isListening: transcriber.isListening && speakingSide == .englishToThai,
                micLabel: "Hold to speak English",
                direction: .englishToThai,
                tint: Theme.mango
            )
        }
        .translationTask(translator.configuration) { session in
            await translator.run(session)
        }
        .onChange(of: translator.output) { _, output in
            guard !output.isEmpty, let side = speakingSide else { return }
            if side == .englishToThai {
                thaiSideText = output
                speaker.speak(output, languageCode: "th")
            } else {
                englishSideText = output
                speaker.speak(output, languageCode: "en")
            }
            speakingSide = nil
        }
        .permissionAlert($deniedPermission)
        .alert("Voice Unavailable", isPresented: Binding(get: { voiceError != nil }, set: { if !$0 { voiceError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceError ?? "")
        }
    }

    private func half(
        text: String,
        caption: String?,
        isListening: Bool,
        micLabel: String,
        direction: TranslationDirection,
        tint: Color
    ) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 30, weight: .semibold))
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            if translator.isTranslating && speakingSide == direction {
                ProgressView()
            }
            Spacer(minLength: 0)
            HoldToTalkButton(isListening: isListening, label: micLabel) {
                Task { await start(direction) }
            } onRelease: {
                Task { await finish(direction) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(0.07))
    }

    private func start(_ direction: TranslationDirection) async {
        guard !transcriber.isListening else { return }
        if let denied = await SpeechTranscriber.requestPermissions() {
            deniedPermission = denied
            return
        }
        speaker.stop()
        speakingSide = direction
        do {
            try transcriber.start(languageCode: direction.sourceCode)
        } catch {
            speakingSide = nil
            voiceError = error.localizedDescription
        }
    }

    private func finish(_ direction: TranslationDirection) async {
        guard speakingSide == direction else { return }
        let heard = await transcriber.stop()
        guard !heard.isEmpty else {
            speakingSide = nil
            return
        }
        translator.translate(heard, direction: direction)
    }
}

#Preview {
    ConversationView()
}
