import SwiftUI
import UIKit

/// "Sky & sunrise" palette that matches the app icon: vivid sky blue as the primary color, a
/// sunrise orange accent, cool airy backgrounds and floating cards. Works in light and dark mode.
enum Theme {
    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 14

    private static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// Primary: sky blue (buttons, links, selected states).
    static let ink = dynamic("#2563EB", "#7AA7FF")
    /// Night sky, for deep backgrounds and shadows.
    static let inkDeep = Color(hex: "#0B1430")

    /// Sunrise orange accent.
    static let mango = Color(hex: "#F97316")
    static let mangoLight = Color(hex: "#FDBA74")
    /// Fresh teal for "go" and positive states.
    static let lagoon = Color(hex: "#0EA5A4")
    static let coral = Color(hex: "#F43F5E")
    static let violet = Color(hex: "#7C3AED")

    /// Hero / call-to-action gradient: deep sky into bright blue.
    static let sunsetGradient = LinearGradient(
        colors: [Color(hex: "#1E3A8A"), Color(hex: "#1D4ED8"), Color(hex: "#3B82F6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Blue into violet, for highlights.
    static let auroraGradient = LinearGradient(
        colors: [Color(hex: "#2563EB"), Color(hex: "#7C3AED")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The sunrise itself, for small accents (weather, badges).
    static let warmGradient = LinearGradient(
        colors: [mangoLight, mango, coral.opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let lagoonGradient = LinearGradient(
        colors: [Color(hex: "#2DD4BF"), Color(hex: "#0EA5A4")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Cool, airy page background and floating cards.
    static let background = dynamic("#F2F5FB", "#070B14")
    static let cardBackground = dynamic("#FFFFFF", "#111827")
    static let insetBackground = dynamic("#E8EDF6", "#1A2236")
    static let hairline = dynamic("#E2E8F2", "#253049")
    /// Soft glow tint behind floating cards.
    static let shadow = dynamic("#1E3A8A", "#000000")
}

/// The page background: a soft sky wash at the top fading into the page color.
struct SkyBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(colors: scheme == .dark
                           ? [Color(hex: "#1E3A8A").opacity(0.55), Color(hex: "#312E81").opacity(0.25), .clear]
                           : [Color(hex: "#BFDBFE").opacity(0.9), Color(hex: "#E0E7FF").opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
            // A warm sunrise glow in the corner.
            Circle()
                .fill(RadialGradient(colors: [Theme.mangoLight.opacity(scheme == .dark ? 0.18 : 0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: 170, y: -200)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Sky-wash page background (use on the main tab screens).
    func skyBackground() -> some View { background(SkyBackdrop()) }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count == 6 {
            self.init(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        } else {
            self.init(white: 0.5, alpha: 1)
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

// MARK: Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 0.5))
            .shadow(color: Theme.shadow.opacity(0.10), radius: 18, y: 8)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: Buttons

/// Big gradient capsule for the main action (easy to hit one-handed while walking).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.sunsetGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.ink.opacity(isEnabled ? 0.45 : 0), radius: 14, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Small pieces

struct StatPill: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(text).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

/// Category icon in a tinted rounded square.
struct CategoryBadge: View {
    let category: ItemCategory
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Color(hex: category.colorHex))
            .frame(width: size, height: size)
            .background(Color(hex: category.colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel(category.title)
    }
}

/// Branded empty state with a gradient icon tile.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Theme.sunsetGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Theme.ink.opacity(0.4), radius: 16, y: 8)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                actions()
            }
            .frame(maxWidth: 320)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Placeholder for tabs that arrive in a later build step.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            EmptyStateView(systemImage: systemImage, title: title, message: message)
                .background(Theme.background)
                .navigationTitle(title)
        }
    }
}
