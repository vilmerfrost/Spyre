import Foundation
import Testing
@testable import SpyreCore

@Suite(.timeLimit(.minutes(1)))
struct ThemeTests {
    @Test(arguments: Theme.builtInNames)
    func builtInThemeLoads(name: String) throws {
        let theme = try Theme.builtIn(name)
        #expect(theme.spyreTheme == Theme.supportedVersion)
        #expect(["light", "dark"].contains(theme.appearance))
    }

    /// `DESIGN.md` 10.1: every built-in theme meets WCAG AA for text and status labels.
    @Test(arguments: Theme.builtInNames)
    func builtInThemeMeetsContrast(name: String) throws {
        let theme = try Theme.builtIn(name).filled(from: Theme.builtIn("light"))
        let foregrounds = ["color.text.primary", "color.text.secondary"]
            + SessionStatus.allCases.filter { $0 != .starting }.map { "color.status.\($0.rawValue)" }
        for background in ["color.background.base", "color.surface.card"] {
            let back = try #require(theme.color(background))
            for token in foregrounds {
                let ratio = try #require(theme.color(token)).contrast(with: back)
                #expect(ratio >= 4.5, "\(name): \(token) on \(background) is \(ratio)")
            }
        }
    }

    @Test func invalidColorIsDroppedWithWarning() throws {
        let json = #"{"spyreTheme":1,"name":"T","appearance":"light","tokens":{"color.accent":"blue","radius.card":8}}"#
        let (theme, warnings) = try Theme.load(from: Data(json.utf8))
        #expect(theme.color("color.accent") == nil)
        #expect(theme.number("radius.card") == 8)
        #expect(warnings.count == 1)
    }

    @Test func newerThemeVersionIsRejected() {
        let json = #"{"spyreTheme":99,"name":"T","appearance":"light","tokens":{}}"#
        #expect(throws: ThemeError.unsupportedVersion(99)) { try Theme.load(from: Data(json.utf8)) }
    }

    @Test func missingTokensComeFromBase() throws {
        let dark = try Theme.builtIn("dark").filled(from: Theme.builtIn("light"))
        #expect(dark.number("radius.card") == 20)
        #expect(dark.color("color.text.primary") == RGBA(hex: "#E8EAED"))
    }

    @Test func hexParsing() {
        #expect(RGBA(hex: "#FFFFFF")?.alpha == 1)
        #expect(RGBA(hex: "#00000080")?.alpha == Double(0x80) / 255)
        #expect(RGBA(hex: "FFFFFF") == nil)
        #expect(RGBA(hex: "#FFF") == nil)
    }
}
