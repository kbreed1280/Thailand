import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → WanderHub" from TikTok (or anywhere with a link). Saves the link to the app group
/// inbox; WanderHub picks it up next time it opens and asks where the video is.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model) { [weak self] in self?.close() })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { @MainActor in
            let (url, text) = await extractLink()
            let screenshots = await extractScreenshotText()
            if let url {
                SharedInbox.append(url: url, text: text)
            }
            for text in screenshots where !text.isEmpty {
                SharedInbox.append(url: nil, text: text)
            }
            if url != nil || !screenshots.isEmpty {
                model.state = .saved(isTikTok: url?.host?.contains("tiktok") == true, screenshots: screenshots.count)
                try? await Task.sleep(for: .seconds(1.6))
                close()
            } else {
                model.state = .noLink
            }
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Text read from any shared screenshots (place names shown on screen).
    private func extractScreenshotText() async -> [String] {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { continue }
            var image: UIImage?
            if let url = item as? URL { image = UIImage(contentsOfFile: url.path) }
            else if let data = item as? Data { image = UIImage(data: data) }
            else if let ui = item as? UIImage { image = ui }
            if let image { texts.append(await ScreenshotText.recognize(image)) }
        }
        return texts
    }

    /// The shared URL, plus any text (TikTok shares "caption + link").
    private func extractLink() async -> (URL?, String?) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var foundURL: URL?
        var foundText: String?
        for provider in providers {
            if foundURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               !url.isFileURL {
                foundURL = url
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                foundText = text
                if foundURL == nil { foundURL = SharedInbox.firstURL(in: text) }
            }
        }
        return (foundURL, foundText)
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case working, saved(isTikTok: Bool, screenshots: Int), noLink }
    @Published var state: State = .working
}

private struct ShareCard: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                switch model.state {
                case .working:
                    ProgressView()
                    Text("Saving to WanderHub…")
                case .saved(let isTikTok, let screenshots):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text(screenshots > 0 && !isTikTok ? "Screenshot\(screenshots == 1 ? "" : "s") saved to WanderHub"
                         : isTikTok ? "TikTok saved to WanderHub" : "Saved to WanderHub").font(.headline)
                    Text("Open WanderHub → Spots to review the places it found.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .noLink:
                    Image(systemName: "link.badge.plus").font(.system(size: 40)).foregroundStyle(.orange)
                    Text("No link found to save").font(.headline)
                    Button("Close", action: onClose).buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
        .onTapGesture { if case .saved = model.state { onClose() } }
    }
}
