import SwiftUI
import PhotosUI
import VisionKit
import Translation

/// Take or pick a photo of a menu or sign. Live Text lets you select any text (the system menu
/// includes Translate), and "Translate All" translates everything it found.
struct LiveTextScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var transcript = ""
    @State private var isAnalyzing = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var translator = TranslatorModel()
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image {
                    LiveTextImageView(image: image) { found in
                        transcript = found
                        isAnalyzing = false
                    }
                    .background(Color.black)
                } else {
                    EmptyStateView(
                        systemImage: "text.viewfinder",
                        title: "Scan a Menu or Sign",
                        message: "Take a photo or pick one from your library. Then press on any text to select, copy or translate it."
                    ) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera.fill")
                            }
                            .buttonStyle(.primary)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose Photo", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.secondary)
                    }
                }

                if image != nil {
                    bottomBar
                }
            }
            .background(Theme.background)
            .navigationTitle("Scan Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if image != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Photo") {
                            image = nil
                            transcript = ""
                            translator.clear()
                        }
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        load(picked)
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    if let captured = UIImage(data: data) { load(captured) }
                }
                .ignoresSafeArea()
            }
            .translationTask(translator.configuration) { session in
                await translator.run(session)
            }
            .sheet(isPresented: $showingResult) {
                ScanResultSheet(original: transcript, translator: translator)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if isAnalyzing {
                ProgressView("Reading text…")
            } else if transcript.isEmpty {
                Text("No text found. Try a closer, sharper photo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Press and hold on text to select it, or translate everything:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    let direction: TranslationDirection = ThaiText.containsThai(transcript) ? .thaiToEnglish : .englishToThai
                    translator.translate(transcript, direction: direction)
                    showingResult = true
                } label: {
                    Label("Translate All", systemImage: "character.bubble.fill")
                }
                .buttonStyle(.primary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func load(_ newImage: UIImage) {
        transcript = ""
        translator.clear()
        isAnalyzing = true
        image = newImage
    }
}

private struct ScanResultSheet: View {
    let original: String
    let translator: TranslatorModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if translator.isTranslating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let error = translator.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text(translator.output)
                            .font(.title3)
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text("Original").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Translation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// UIImageView with VisionKit's Live Text interaction.
private struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    let onTranscript: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        view.addInteraction(context.coordinator.interaction)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        context.coordinator.analyze(image, onTranscript: onTranscript)
    }

    @MainActor
    final class Coordinator {
        let interaction = ImageAnalysisInteraction()
        private let analyzer = ImageAnalyzer()
        private var task: Task<Void, Never>?

        func analyze(_ image: UIImage, onTranscript: @escaping (String) -> Void) {
            task?.cancel()
            interaction.analysis = nil
            task = Task {
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try? await analyzer.analyze(image, configuration: configuration)
                guard !Task.isCancelled else { return }
                interaction.analysis = analysis
                interaction.preferredInteractionTypes = .automatic
                onTranscript(analysis?.transcript ?? "")
            }
        }
    }
}

#Preview {
    LiveTextScannerView()
}
