import SwiftUI
import Translation
import VisionKit

/// Translate tab: text/voice translator, two-person conversation, phrasebook.
struct TranslateTabView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case translate = "Translate"
        case conversation = "Talk"
        case phrasebook = "Phrases"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .translate
    @State private var languagePack = LanguagePackModel()
    @AppStorage("didPromptLanguagePack") private var didPromptLanguagePack = false
    @AppStorage(PoliteParticle.storageKey) private var particle: PoliteParticle = .khrap
    @State private var showingPackPrompt = false
    @State private var showingHistory = false
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if languagePack.state == .needsDownload {
                    LanguagePackBanner { languagePack.download() }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else if languagePack.state == .unsupported {
                    Label("Translation isn't available on this device. The phrasebook still works offline.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                Group {
                    switch mode {
                    case .translate: TextTranslatorView()
                    case .conversation: ConversationView()
                    case .phrasebook: PhrasebookView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if ImageAnalyzer.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan Menu or Sign", systemImage: "text.viewfinder")
                        }
                    }
                    Button {
                        showingHistory = true
                    } label: {
                        Label("History & Favorites", systemImage: "clock.arrow.circlepath")
                    }
                    Menu {
                        Picker("Polite ending", selection: $particle) {
                            ForEach(PoliteParticle.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Polite Ending", systemImage: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showingHistory) { HistoryView() }
            .fullScreenCover(isPresented: $showingScanner) { LiveTextScannerView() }
            .task {
                await languagePack.refresh()
                if languagePack.state == .needsDownload && !didPromptLanguagePack {
                    didPromptLanguagePack = true
                    showingPackPrompt = true
                }
            }
            .alert("Download Thai for Offline Use?", isPresented: $showingPackPrompt) {
                Button("Download") { languagePack.download() }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Do this on Wi-Fi before your flight so translation works without signal. It's about 100 MB.")
            }
            .translationTask(languagePack.prepareConfiguration) { session in
                await languagePack.prepare(session)
            }
        }
    }
}

private struct LanguagePackBanner: View {
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.lagoon)
            VStack(alignment: .leading, spacing: 2) {
                Text("Thai isn't downloaded yet").font(.subheadline.weight(.semibold))
                Text("Download it to translate without internet.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Download", action: onDownload)
                .buttonStyle(.borderedProminent)
                .tint(Theme.lagoon)
        }
        .padding(12)
        .background(Theme.lagoon.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

/// Helpers shared by the translate screens.
enum ThaiText {
    /// True when the string contains any Thai script.
    static func containsThai(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
    }

    /// Rough Latin-letter pronunciation of Thai text (system transliteration; tones not marked).
    static func romanize(_ text: String) -> String? {
        guard containsThai(text) else { return nil }
        return text.applyingTransform(.toLatin, reverse: false)
    }
}

#Preview {
    TranslateTabView()
}
