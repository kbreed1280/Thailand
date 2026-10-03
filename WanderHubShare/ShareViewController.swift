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
            if let url {
                SharedInbox.append(url: url, text: text)
                model.state = .saved(isTikTok: url.host?.contains("tiktok") == true)
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

    /// The shared URL, plus any text (TikTok shares "caption + link").
    private func extractLink() async -> (URL?, String?) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var foundURL: URL?
        var foundText: String?
        for provider in providers {
            if foundURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
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
    enum State { case working, saved(isTikTok: Bool), noLink }
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
                case .saved(let isTikTok):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text(isTikTok ? "TikTok saved to WanderHub" : "Link saved to WanderHub").font(.headline)
                    Text("Open WanderHub → TikTok to put it on your map.")
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
