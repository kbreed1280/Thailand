import SwiftUI
import Translation

/// Type or hold-to-talk, translate English ⇄ Thai, then speak, copy, favorite or "Show".
struct TextTranslatorView: View {
    @StateObject private var transcriber = SpeechTranscriber()
    @StateObject private var speaker = Speaker.shared
    @StateObject private var history = TranslationHistoryStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var translator = TranslatorModel()

    @State private var direction: TranslationDirection = .englishToThai
    @State private var input = ""
    @State private var speakWhenDone = false
    @State private var showText: ShowModeContent?
    @State private var deniedPermission: PermissionKind?
    @State private var voiceError: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                directionBar
                inputCard
                Button {
                    inputFocused = false
                    translator.translate(input, direction: direction)
                } label: {
                    Label("Translate", systemImage: "character.bubble")
                }
                .buttonStyle(.primary)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if translator.isTranslating {
                    ProgressView().padding()
                } else if let error = translator.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else if !translator.output.isEmpty {
                    outputCard
                }

                if !network.isOnline {
                    OfflineBadge(text: "Offline — works if Thai is downloaded")
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .translationTask(translator.configuration) { session in
            await translator.run(session)
        }
        .onAppear {
            translator.onTranslated = { source, result, direction in
                TranslationHistoryStore.shared.add(source: source, result: result, fromThai: direction.isFromThai)
            }
        }
        .onChange(of: translator.output) { _, output in
            if speakWhenDone, !output.isEmpty {
                speakWhenDone = false
                speaker.speak(output, languageCode: direction.targetCode)
            }
        }
        .fullScreenCover(item: $showText) { ShowModeView(content: $0) }
        .permissionAlert($deniedPermission)
        .alert("Voice Unavailable", isPresented: Binding(get: { voiceError != nil }, set: { if !$0 { voiceError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceError ?? "")
        }
    }

    // MARK: Pieces

    private var directionBar: some View {
        HStack {
            Text(direction.sourceName).font(.headline).frame(maxWidth: .infinity)
            Button {
                withAnimation(.snappy) {
                    direction = direction.reversed
                    if !translator.output.isEmpty {
                        input = translator.output
                        translator.clear()
                    }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.sunsetGradient, in: Circle())
            }
            .accessibilityLabel("Swap languages")
            Text(direction.targetName).font(.headline).frame(maxWidth: .infinity)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if input.isEmpty && !transcriber.isListening {
                    Text(direction == .englishToThai ? "Type in English…" : "พิมพ์ภาษาไทย…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: transcriber.isListening ? .constant(transcriber.transcript) : $input)
                    .focused($inputFocused)
                    .font(.title3)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
            }

            HStack {
                HoldToTalkButton(isListening: transcriber.isListening, label: "Hold to speak \(direction.sourceName)") {
                    Task { await startListening() }
                } onRelease: {
                    Task { await finishListening() }
                }
                Spacer()
                if !input.isEmpty {
                    Button {
                        input = ""
                        translator.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear")
                }
            }
        }
        .card()
    }

    private var outputCard: some View {
        let output = translator.output
        let romanized = direction.targetCode == "th" ? ThaiText.romanize(output) : nil
        let record = history.records.first { $0.result == output }

        return VStack(alignment: .leading, spacing: 10) {
            Text(direction.targetName.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.mango)
            Text(output)
                .font(direction.targetCode == "th" ? .system(size: 30, weight: .semibold) : .title2.weight(.semibold))
                .textSelection(.enabled)
            if let romanized {
                Text(romanized)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button {
                    speaker.speak(output, languageCode: direction.targetCode)
                } label: {
                    Label("Speak", systemImage: speaker.speakingText == output ? "stop.circle.fill" : "speaker.wave.2.fill")
                }
                Button {
                    UIPasteboard.general.string = output
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let record {
                    Button {
                        history.toggleFavorite(record)
                    } label: {
                        Label("Favorite", systemImage: record.isFavorite ? "star.fill" : "star")
                    }
                }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(Theme.lagoon)

            Button {
                showText = direction.targetCode == "th"
                    ? ShowModeContent(thai: output, english: input, romanized: romanized)
                    : ShowModeContent(thai: input, english: output, romanized: ThaiText.romanize(input))
            } label: {
                Label("Show to Someone", systemImage: "rectangle.expand.vertical")
            }
            .buttonStyle(.secondary)
        }
        .card()
    }

    // MARK: Voice

    private func startListening() async {
        if let denied = await SpeechTranscriber.requestPermissions() {
            deniedPermission = denied
            return
        }
        speaker.stop()
        do {
            try transcriber.start(languageCode: direction.sourceCode)
        } catch {
            voiceError = error.localizedDescription
        }
    }

    private func finishListening() async {
        let heard = await transcriber.stop()
        guard !heard.isEmpty else { return }
        input = heard
        speakWhenDone = true
        translator.translate(heard, direction: direction)
    }
}

/// A big mic button that listens while held down.
struct HoldToTalkButton: View {
    let isListening: Bool
    let label: String
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.title2)
                .symbolEffect(.variableColor.iterative, isActive: isListening)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(isListening ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.lagoonGradient), in: Circle())
                .scaleEffect(isPressed ? 1.12 : 1)
                .animation(.spring(duration: 0.2), value: isPressed)
            Text(isListening ? "Listening… release to translate" : label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isListening ? .red : .secondary)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Press and hold, speak, then let go.")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    TextTranslatorView()
}
