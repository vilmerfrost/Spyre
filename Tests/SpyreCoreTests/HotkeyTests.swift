import Carbon.HIToolbox
import Foundation
import Testing
@testable import SpyreCore

/// The global shortcut and the `hotkey` and `showDockIcon` config keys. `SPEC.md` 4.4.
@Suite(.timeLimit(.minutes(1)))
struct HotkeyTests {
    @Test func defaultIsControlOptionS() {
        #expect(Hotkey.default.configString == "ctrl+opt+s")
        #expect(Hotkey.default.displayString == "⌃⌥S")
        #expect(SpyreConfig.default.hotkey == .default)
        #expect(Hotkey("ctrl+opt+s") == .default)
    }

    @Test(arguments: [
        ("CTRL+OPT+S", "ctrl+opt+s", "⌃⌥S"),
        ("opt+ctrl+s", "ctrl+opt+s", "⌃⌥S"),
        ("cmd+shift+1", "shift+cmd+1", "⇧⌘1"),
        ("cmd+shift+opt+ctrl+z", "ctrl+opt+shift+cmd+z", "⌃⌥⇧⌘Z"),
    ])
    func validStringsParse(text: String, canonical: String, display: String) throws {
        let hotkey = try #require(Hotkey(text))
        #expect(hotkey.configString == canonical)
        #expect(hotkey.displayString == display)
        #expect(Hotkey(hotkey.configString) == hotkey)
    }

    @Test(arguments: [
        "", "s", "shift+s", "ctrl+opt", "ctrl+ctrl+s", "ctrl+opt+s+t", "ctrl+opt+ss",
        "ctrl+opt+é", "ctrl++s", "ctrl+opt+f1", "control+option+s", " ctrl+opt+s",
    ])
    func invalidStringsAreRejected(text: String) {
        #expect(Hotkey(text) == nil)
    }

    @Test func keyCodesAndModifiersMatchCarbon() throws {
        let expected: [String: Int] = [
            "a": kVK_ANSI_A, "s": kVK_ANSI_S, "z": kVK_ANSI_Z, "m": kVK_ANSI_M, "q": kVK_ANSI_Q,
            "0": kVK_ANSI_0, "5": kVK_ANSI_5, "9": kVK_ANSI_9,
        ]
        for (key, code) in expected {
            #expect(try #require(Hotkey("ctrl+\(key)")).keyCode == UInt32(code))
        }
        for key in "abcdefghijklmnopqrstuvwxyz0123456789" {
            #expect(Hotkey("cmd+\(key)") != nil)
        }
        #expect(Hotkey.Modifiers.control.rawValue == UInt32(controlKey))
        #expect(Hotkey.Modifiers.option.rawValue == UInt32(optionKey))
        #expect(Hotkey.Modifiers.shift.rawValue == UInt32(shiftKey))
        #expect(Hotkey.Modifiers.command.rawValue == UInt32(cmdKey))
    }

    @Test func registrationWarningNamesTheShortcut() {
        let warning = Hotkey.default.registrationWarning(status: Int32(eventHotKeyExistsErr))
        #expect(warning == "Cannot use the shortcut ⌃⌥S (error -9878). Another app may use it.")
    }

    @Test func configReadsHotkey() {
        let result = ConfigFile.parse(Data(#"{"hotkey":"cmd+shift+k"}"#.utf8))
        #expect(result.config.hotkey == Hotkey("cmd+shift+k"))
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: [#""s""#, #""ctrl+opt+f1""#, "42", "true", "null"])
    func badHotkeyGivesDefaultAndWarning(value: String) {
        let result = ConfigFile.parse(Data(#"{"hotkey":\#(value)}"#.utf8))
        #expect(result.config.hotkey == .default)
        #expect(result.warnings == [#""hotkey" must be like "ctrl+opt+s". Using the default."#])
    }

    @Test func showDockIconDefaultAndValid() {
        #expect(SpyreConfig.default.showDockIcon == false)
        #expect(ConfigFile.parse(Data(#"{"showDockIcon":true}"#.utf8)).config.showDockIcon)
        #expect(ConfigFile.parse(Data(#"{"showDockIcon":true}"#.utf8)).warnings.isEmpty)
    }

    @Test(arguments: [#""yes""#, "1", "null"])
    func badShowDockIconGivesDefaultAndWarning(value: String) {
        let result = ConfigFile.parse(Data(#"{"showDockIcon":\#(value)}"#.utf8))
        #expect(result.config.showDockIcon == false)
        #expect(result.warnings == [#""showDockIcon" must be true or false. Using the default."#])
    }

    @Test func newFileHasBothKeys() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpyreHotkeyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = ConfigFile(folder: folder)
        #expect(file.load() == ConfigLoadResult(config: .default, warnings: []))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        #expect(object["hotkey"] as? String == "ctrl+opt+s")
        #expect(object["showDockIcon"] as? Bool == false)
    }

    @Test func markWelcomeSeenKeepsBothKeys() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpyreHotkeyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = ConfigFile(folder: folder)
        try Data(#"{"hotkey":"cmd+shift+k","showDockIcon":true}"#.utf8).write(to: file.url)

        try file.markWelcomeSeen()

        let config = SpyreConfig(welcomeSeen: true, hotkey: try #require(Hotkey("cmd+shift+k")), showDockIcon: true)
        #expect(file.load() == ConfigLoadResult(config: config, warnings: []))
    }
}
