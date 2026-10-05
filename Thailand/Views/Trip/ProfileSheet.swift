import StoreKit
import PhotosUI
import SwiftUI

/// Your profile: name (shown as "added by" and on lists you share), a @username and an avatar.
/// Once trip sharing is on, your iCloud name is used for the name.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""
    @AppStorage(AppSettings.usernameKey) private var username = ""
    @AppStorage(AppSettings.avatarEmojiKey) private var avatarEmoji = ""
    @AppStorage(DayReminders.enabledKey) private var dayReminders = true
    @AppStorage(CommunityService.enabledKey) private var community = false
    @AppStorage(CommunityService.showUsernameKey) private var showUsername = false
    @Environment(\.managedObjectContext) private var context
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPaywall = false
    @State private var redeeming = false
    @ObservedObject private var store = Subscription.shared
    @State private var photoVersion = 0

    private static let emojis = ["🧳", "🐘", "🌴", "🍜", "🛺", "🏝️", "🦩", "🌞", "🥥", "🐒", "🌺", "✈️"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        AvatarView(size: 96).id(photoVersion)
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $photoItem, matching: .images) { Text("Choose photo") }
                            if FileManager.default.fileExists(atPath: AppSettings.avatarPhotoURL.path) {
                                Button("Remove photo", role: .destructive) {
                                    try? FileManager.default.removeItem(at: AppSettings.avatarPhotoURL)
                                    photoVersion += 1
                                }
                            }
                        }
                        .font(.callout)
                        .buttonStyle(.borderless)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.emojis, id: \.self) { e in
                                    Text(e).font(.title2)
                                        .frame(width: 40, height: 40)
                                        .background(e == avatarEmoji ? Theme.mango.opacity(0.3) : .clear, in: Circle())
                                        .onTapGesture { avatarEmoji = e == avatarEmoji ? "" : e }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    TextField("Your first name", text: $displayName)
                        .textContentType(.givenName)
                        .font(.title3)
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, new in
                                let cleaned = String(new.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(24))
                                if cleaned != new { username = cleaned }
                            }
                    }
                } footer: {
                    Text("Shown next to places, expenses and packing items you add, and on lists you share, so your travel partner knows who added what.")
                }
                Section {
                    Button { showingPaywall = true } label: {
                        LabeledContent("WanderHub Pro", value: store.isPro ? "Active" : store.isTestBuild ? "Unlocked (test build)" : "Free plan")
                    }
                    Button("Redeem a promo code", systemImage: "giftcard") { redeeming = true }
                }
                Section {
                    Toggle("Share my spots with the community", isOn: $community)
                        .onChange(of: community) { _, on in
                            Task {
                                if on { await CommunityService.shared.shareAll(in: context) }
                                else { await CommunityService.shared.withdrawAll() }
                            }
                        }
                    Toggle("Show my @username on tips", isOn: $showUsername)
                        .disabled(!community || username.isEmpty)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Off by default. When on, places you confirm are shared anonymously with other travelers: the place, the inside scoop and a link to the original post. Your notes, photos, trips and lists stay private. Turning it off removes what you shared.")
                }
                Section {
                    Link(destination: URL(string: "https://kbreed1280.github.io/Thailand/support.html")!) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: PaywallView.privacyURL) { Label("Privacy Policy", systemImage: "hand.raised") }
                    Link(destination: PaywallView.termsURL) { Label("Terms of Use", systemImage: "doc.text") }
                }
                Section {
                    Toggle("Evening reminder for tomorrow's plan", isOn: $dayReminders)
                } footer: {
                    Text("At 8 PM the night before each planned day: how many stops, the first one, and the weather and heat.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await store.refreshEntitlements() } }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.preparingThumbnail(of: CGSize(width: 400, height: 400))?.jpegData(compressionQuality: 0.8)
                    else { return }
                    try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
                    try? jpeg.write(to: AppSettings.avatarPhotoURL)
                    photoVersion += 1
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Your avatar: photo if set, else your emoji, else your initial.
struct AvatarView: View {
    var size: CGFloat = 32
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""
    @AppStorage(AppSettings.avatarEmojiKey) private var avatarEmoji = ""

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: AppSettings.avatarPhotoURL.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if !avatarEmoji.isEmpty {
                Text(avatarEmoji).font(.system(size: size * 0.55))
            } else {
                Text(String(AppSettings.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.mango.gradient, in: Circle())
        .clipShape(Circle())
    }
}
