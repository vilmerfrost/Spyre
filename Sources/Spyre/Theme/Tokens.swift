import AppKit
import SpyreCore
import SwiftUI

/// The active design tokens. Views read visual values only through this type.
/// This is the only place that turns token values into SwiftUI colors and fonts.
struct Tokens: Sendable {
    let theme: Theme

    /// Loads a built-in theme and fills missing tokens from the light theme.
    static func builtIn(_ name: String) -> Tokens {
        do {
            let base = try Theme.builtIn("light")
            return Tokens(theme: try Theme.builtIn(name).filled(from: base))
        } catch {
            return fallback
        }
    }

    /// Used only when a built-in theme file is missing. Keeps the app running.
    static let fallback = Tokens(
        theme: Theme(spyreTheme: Theme.supportedVersion, name: "Fallback", appearance: "light", tokens: [:])
    )

    /// The macOS appearance for windows and system controls. It always matches the theme. `DESIGN.md` 7.
    var appearance: NSAppearance? {
        NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    var colorScheme: ColorScheme { theme.isDark ? .dark : .light }

    func color(_ token: String) -> Color {
        guard let rgba = theme.color(token) else { return .primary }
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// A token color for Core Animation layers.
    func cgColor(_ token: String) -> CGColor {
        guard let rgba = theme.color(token) else { return CGColor(gray: 0.5, alpha: 1) }
        return CGColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    func value(_ token: String) -> CGFloat {
        CGFloat(theme.number(token) ?? 0)
    }

    /// The font for a role: `font.<role>.size` and `font.<role>.weight`.
    func font(_ role: String) -> Font {
        .system(size: value("font.\(role).size"), weight: weight(theme.string("font.\(role).weight")))
    }

    func icon(_ token: String) -> String {
        theme.string(token) ?? "circle"
    }

    func statusColor(_ status: SessionStatus) -> Color {
        color("color.status.\(status.tokenName)")
    }

    func statusIcon(_ status: SessionStatus) -> String {
        icon("icon.status.\(status.tokenName)")
    }

    /// A motion duration. `0` under Reduce Motion, so changes happen at once. `DESIGN.md` 10.3.
    func duration(_ token: String, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(value(token))
    }

    private func weight(_ name: String?) -> Font.Weight {
        switch name {
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        default: .regular
        }
    }
}

extension SessionStatus {
    /// `starting` has no own tokens. It uses the `unknown` look until the first good read.
    var tokenName: String { self == .starting ? "unknown" : rawValue }
}

private struct TokensKey: EnvironmentKey {
    static let defaultValue = Tokens.builtIn("light")
}

extension EnvironmentValues {
    var tokens: Tokens {
        get { self[TokensKey.self] }
        set { self[TokensKey.self] = newValue }
    }
}
