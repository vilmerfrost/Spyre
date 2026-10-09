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

    func color(_ token: String) -> Color {
        guard let rgba = theme.color(token) else { return .primary }
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    func value(_ token: String) -> CGFloat {
        CGFloat(theme.number(token) ?? 0)
    }

    func font(_ role: String) -> Font {
        .system(size: value("font.\(role).size"))
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
