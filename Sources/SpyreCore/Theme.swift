import Foundation

/// One token value from a theme file. `DESIGN.md` 4.1 lists the units.
public enum TokenValue: Sendable, Equatable, Decodable {
    case number(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

/// A color in 0...1 components. UI code converts it to a SwiftUI color.
public struct RGBA: Sendable, Equatable {
    public var red, green, blue, alpha: Double

    /// Parses `#RRGGBB` or `#RRGGBBAA`. Returns `nil` for any other form.
    public init?(hex: String) {
        guard hex.hasPrefix("#"), [7, 9].contains(hex.count),
              let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        let full = hex.count == 7 ? (value << 8) | 0xFF : value
        red = Double((full >> 24) & 0xFF) / 255
        green = Double((full >> 16) & 0xFF) / 255
        blue = Double((full >> 8) & 0xFF) / 255
        alpha = Double(full & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// This color drawn over an opaque `background`. The result is opaque.
    /// Contrast checks use it for translucent tokens (`DESIGN.md` 10.1).
    public func composited(over background: RGBA) -> RGBA {
        var result = background
        result.red = red * alpha + background.red * (1 - alpha)
        result.green = green * alpha + background.green * (1 - alpha)
        result.blue = blue * alpha + background.blue * (1 - alpha)
        result.alpha = 1
        return result
    }

    /// WCAG contrast ratio between two opaque colors.
    public func contrast(with other: RGBA) -> Double {
        let (light, dark) = luminance > other.luminance ? (self, other) : (other, self)
        return (light.luminance + 0.05) / (dark.luminance + 0.05)
    }
}

/// A theme: a set of token values. Light and dark are two themes, not special cases.
public struct Theme: Sendable, Equatable, Decodable {
    public static let supportedVersion = 1

    public var spyreTheme: Int
    public var name: String
    public var appearance: String
    public var tokens: [String: TokenValue]

    public init(spyreTheme: Int, name: String, appearance: String, tokens: [String: TokenValue]) {
        self.spyreTheme = spyreTheme
        self.name = name
        self.appearance = appearance
        self.tokens = tokens
    }

    /// Decodes a theme file. Drops color tokens that are not valid hex and reports them as warnings.
    public static func load(from data: Data) throws -> (theme: Theme, warnings: [String]) {
        var theme = try JSONDecoder().decode(Theme.self, from: data)
        guard theme.spyreTheme <= supportedVersion else { throw ThemeError.unsupportedVersion(theme.spyreTheme) }
        var warnings: [String] = []
        for (key, value) in theme.tokens where key.hasPrefix("color.") {
            if case .string(let hex) = value, RGBA(hex: hex) != nil { continue }
            theme.tokens[key] = nil
            warnings.append("Invalid color for \(key). The default value is used.")
        }
        return (theme, warnings.sorted())
    }

    /// Loads a built-in theme by file name: `light`, `dark`, or `high-contrast`.
    public static func builtIn(_ name: String) throws -> Theme {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Themes") else {
            throw ThemeError.missingBuiltIn(name)
        }
        return try load(from: Data(contentsOf: url)).theme
    }

    public static let builtInNames = ["light", "dark", "high-contrast"]

    /// The built-in theme that follows the macOS appearance: Fog Dark for Dark Mode, else Fog Light.
    /// High Contrast is light only and never chosen automatically. `DESIGN.md` 8.1.
    public static func builtInName(systemIsDark: Bool) -> String {
        systemIsDark ? "dark" : "light"
    }

    /// The hidden launch argument `-SpyreAppearance light|dark`. It forces the appearance that the theme
    /// follows, for visual checks without a change to the system setting. Read from the launch arguments only.
    /// Nothing is stored. Returns `true` for dark, `false` for light, and `nil` when the argument is missing or bad.
    public static func appearanceOverride(arguments: [String]) -> Bool? {
        guard let index = arguments.firstIndex(of: "-SpyreAppearance"), index + 1 < arguments.count else {
            return nil
        }
        switch arguments[index + 1].lowercased() {
        case "dark": return true
        case "light": return false
        default: return nil
        }
    }

    /// `true` when the theme sets the dark macOS window appearance.
    public var isDark: Bool { appearance == "dark" }

    /// Returns this theme with missing tokens filled from `base`. `DESIGN.md` 3, rule 6.
    public func filled(from base: Theme) -> Theme {
        var copy = self
        copy.tokens = base.tokens.merging(tokens) { _, own in own }
        return copy
    }

    public func color(_ token: String) -> RGBA? {
        guard case .string(let hex) = tokens[token] else { return nil }
        return RGBA(hex: hex)
    }

    public func number(_ token: String) -> Double? {
        guard case .number(let value) = tokens[token] else { return nil }
        return value
    }

    public func string(_ token: String) -> String? {
        guard case .string(let value) = tokens[token] else { return nil }
        return value
    }
}

public enum ThemeError: Error, Equatable {
    case unsupportedVersion(Int)
    case missingBuiltIn(String)
}
