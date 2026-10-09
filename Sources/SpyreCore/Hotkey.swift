import Foundation

/// The global shortcut that opens the main window. `SPEC.md` 4.4.
/// Grammar: modifiers and one key, joined by `+`, for example `ctrl+opt+s`. Case does not matter.
/// Modifiers: `ctrl`, `opt`, `shift`, `cmd`. At least one of `ctrl`, `opt`, `cmd` is required.
/// Key: one letter `a`–`z` or one digit `0`–`9`.
public struct Hotkey: Sendable, Equatable {
    /// The modifier keys. The raw values are the Carbon modifier masks (`controlKey`, `optionKey`, …).
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 0x0100)
        public static let shift = Modifiers(rawValue: 0x0200)
        public static let option = Modifiers(rawValue: 0x0800)
        public static let control = Modifiers(rawValue: 0x1000)
    }

    public let modifiers: Modifiers
    /// The key, as one lowercase letter or digit.
    public let key: Character

    /// Control-Option-S.
    public static let `default` = Hotkey(modifiers: [.control, .option], key: "s")

    /// In macOS menu order: ⌃ ⌥ ⇧ ⌘.
    private static let names: [(modifier: Modifiers, config: String, symbol: String)] = [
        (.control, "ctrl", "⌃"), (.option, "opt", "⌥"), (.shift, "shift", "⇧"), (.command, "cmd", "⌘"),
    ]

    /// Virtual key codes (`kVK_ANSI_*`) for the US key positions.
    private static let keyCodes: [Character: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,
    ]

    init(modifiers: Modifiers, key: Character) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses a config string. Returns `nil` for a string that does not follow the grammar.
    public init?(_ text: String) {
        var modifiers: Modifiers = []
        var key: Character?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            if let entry = Self.names.first(where: { $0.config == part }) {
                guard !modifiers.contains(entry.modifier) else { return nil }
                modifiers.insert(entry.modifier)
            } else if part.count == 1, let character = part.first, Self.keyCodes[character] != nil, key == nil {
                key = character
            } else {
                return nil
            }
        }
        guard let key, !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        self.init(modifiers: modifiers, key: key)
    }

    /// The canonical config string, for example `ctrl+opt+s`.
    public var configString: String {
        (Self.names.filter { modifiers.contains($0.modifier) }.map(\.config) + [String(key)]).joined(separator: "+")
    }

    /// The form people read, for example `⌃⌥S`.
    public var displayString: String {
        Self.names.filter { modifiers.contains($0.modifier) }.map(\.symbol).joined() + key.uppercased()
    }

    /// The virtual key code for `RegisterEventHotKey`.
    public var keyCode: UInt32 { Self.keyCodes[key] ?? 0 }

    /// The config warning when macOS does not accept the shortcut, for example because another app uses it.
    public func registrationWarning(status: Int32) -> String {
        "Cannot use the shortcut \(displayString) (error \(status)). Another app may use it."
    }
}
