import SwiftUI

struct ShowModeContent: Identifiable {
    let id = UUID()
    let thai: String
    let english: String
    var romanized: String?
}

/// Full-screen, huge Thai text to hand the phone to a taxi driver or vendor.
/// The screen stays awake while it's open; "Flip" turns it upside-down for someone across a table.
struct ShowModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = Speaker.shared
    let content: ShowModeContent
    @State private var flipped = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Text(content.thai)
                    .font(.system(size: 64, weight: .bold))
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
                    .accessibilityLabel("Thai: \(content.thai)")
                if let romanized = content.romanized, !romanized.isEmpty {
                    Text(romanized)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
                Divider()
                Text(content.english)
                    .font(.title2)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(28)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            .animation(.spring(duration: 0.4), value: flipped)

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Color.black.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        flipped.toggle()
                    } label: {
                        Label("Flip", systemImage: "rotate.right")
                    }
                    Button {
                        speaker.speak(content.thai, languageCode: "th", slow: true)
                    } label: {
                        Label("Speak Thai", systemImage: "speaker.wave.2.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mango)
                .controlSize(.large)
            }
            .foregroundStyle(.black)
            .padding()
        }
        .environment(\.colorScheme, .light)
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

#Preview {
    ShowModeView(content: ShowModeContent(thai: "ไม่เผ็ดครับ", english: "Not spicy, please", romanized: "mâi phèt khráp"))
}
