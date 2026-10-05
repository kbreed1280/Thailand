import SwiftUI
import UIKit

/// Calm traveler palette: deep lagoon "ink" as the primary color, warm paper backgrounds with
/// white cards, and sunset mango kept as a small accent. Works in light and dark mode.
enum Theme {
    static let cornerRadius: CGFloat = 22
    static let smallCornerRadius: CGFloat = 14

    /// Primary: deep lagoon blue-teal (buttons, links, selected states).
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#86C6D6") : UIColor(hex: "#15627A") })
    static let inkDeep = Color(hex: "#0C3F52")

    static let mango = Color(hex: "#F4821C")
    static let mangoLight = Color(hex: "#FFB547")
    static let lagoon = Color(hex: "#1BA39C")
    static let coral = Color(hex: "#E8505B")

    /// Hero / call-to-action gradient (deep lagoon with a hint of evening sky).
    static let sunsetGradient = LinearGradient(
        colors: [Color(hex: "#1D7A8F"), Color(hex: "#15627A"), Color(hex: "#0C3F52")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The real sunset, for small accents (weather, badges).
    static let warmGradient = LinearGradient(
        colors: [mangoLight, mango, coral.opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let lagoonGradient = LinearGradient(
        colors: [Color(hex: "#2FB6A8"), Color(hex: "#178A86")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm paper page background and white cards.
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#111315") : UIColor(hex: "#F6F4F0") })
    static let cardBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#1E2124") : UIColor(hex: "#FFFFFF") })
    static let insetBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#2A2D31") : UIColor(hex: "#EFECE6") })
    static let hairline = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "#34383C") : UIColor(hex: "#E5E1DA") })
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
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
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
            .shadow(color: Theme.mango.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.lagoon

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
                .shadow(color: Theme.mango.opacity(0.35), radius: 14, y: 8)
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
