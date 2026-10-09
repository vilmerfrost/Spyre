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

    /// `DESIGN.md` 10.1: every built-in theme meets WCAG AA (4.5:1) for every text pair the UI draws:
    /// text and status labels on the background, the atmosphere, row surfaces, and controls.
    @Test(arguments: Theme.builtInNames)
    func builtInThemeMeetsContrast(name: String) throws {
        let theme = try Theme.builtIn(name).filled(from: Theme.builtIn("light"))
        let foregrounds = ["color.text.primary", "color.text.secondary", "color.flag.noActivity"]
            + SessionStatus.allCases.filter { $0 != .starting }.map { "color.status.\($0.rawValue)" }
        let opaque = [
            "color.background.base", "color.surface.card", "color.surface.row", "color.surface.rowHover",
            "color.surface.waiting", "color.surface.controlSelected",
            "color.atmosphere.sky", "color.atmosphere.horizon", "color.atmosphere.fog",
        ]
        var backgrounds: [(String, RGBA)] = try opaque.map { ($0, try #require(theme.color($0))) }
        // The section switcher track is translucent. It sits on the top of the atmosphere.
        let track = try #require(theme.color("color.surface.control"))
        let sky = try #require(theme.color("color.atmosphere.sky"))
        backgrounds.append(("color.surface.control over sky", track.composited(over: sky)))
        // Row tags are a faint fill on the row and "Needs you" surfaces.
        let tag = try #require(theme.color("color.surface.tag"))
        for surface in ["color.surface.row", "color.surface.waiting"] {
            let base = try #require(theme.color(surface))
            backgrounds.append(("color.surface.tag over \(surface)", tag.composited(over: base)))
        }
        for (background, back) in backgrounds {
            #expect(back.alpha == 1, "\(name): \(background) must be opaque")
            for token in foregrounds {
                let ratio = try #require(theme.color(token)).contrast(with: back)
                #expect(ratio >= 4.5, "\(name): \(token) on \(background) is \(ratio)")
            }
        }
        let accent = try #require(theme.color("color.accent"))
        let onAccent = try #require(theme.color("color.text.onAccent"))
        #expect(onAccent.contrast(with: accent) >= 4.5, "\(name): onAccent on accent")
    }

    /// `DESIGN.md` 3, rule 6: the light theme holds the full set, so every theme has every token after the fill.
    @Test(arguments: Theme.builtInNames)
    func everyThemeHasEveryTokenAfterFill(name: String) throws {
        let light = try Theme.builtIn("light")
        let theme = try Theme.builtIn(name).filled(from: light)
        #expect(Set(theme.tokens.keys) == Set(light.tokens.keys))
        for token in Self.requiredTokens {
            #expect(theme.tokens[token] != nil, "\(name) has no \(token)")
        }
    }

    /// The tokens the redesigned views read. `DESIGN.md` 5.
    static let requiredTokens = [
        "color.atmosphere.sky", "color.atmosphere.horizon", "color.atmosphere.fog", "color.atmosphere.ridgeFar",
        "color.atmosphere.ridgeMid", "color.atmosphere.ridgeNear", "color.atmosphere.light",
        "color.surface.row", "color.surface.rowHover", "color.surface.waiting", "color.surface.control",
        "color.surface.controlSelected", "color.border.row", "color.border.divider", "color.border.waiting",
        "color.text.onAccent", "color.shadow.panel", "color.flag.noActivity",
        "opacity.atmosphere.scenery", "opacity.atmosphere.dense", "opacity.atmosphere.fog",
        "opacity.atmosphere.light", "blur.atmosphere.ridge",
        "radius.panel", "radius.row", "radius.button", "radius.tag", "space.xxs",
        "size.row.height", "size.row.compactHeight", "size.content.maxWidth", "size.status.column",
        "size.spinner.line", "size.switcher.height", "size.window.maxWidth", "size.window.maxHeight",
        "size.row.disclosureHeight", "size.child.indent", "size.icon.empty", "icon.empty",
        "color.surface.tag", "color.border.segment", "color.shadow.segment", "shadow.segment.radius",
        "shadow.segment.y", "size.icon.agent", "size.selection.line", "size.hoverButton", "icon.agent.claudeCode",
        "icon.agent.codex", "icon.action.showApp", "icon.action.copy", "font.hint.size", "font.reason.size", "font.calm.size", "font.calmCompact.size",
        "size.menu.maxRows", "size.atmosphere.drift", "size.welcome.scenery", "size.welcome.sceneHeight",
        "shadow.panel.radius", "shadow.panel.y",
        "font.rowTitle.size", "font.section.size", "font.control.size", "font.tag.size", "font.count.size",
        "font.countCompact.size", "font.count.weight", "motion.duration.drift",
        "icon.action.openFolder", "icon.disclosure", "icon.child",
    ]

    /// Pixel fixes 2 and 11: the "Needs you" border is about 30 % alpha, and the dark warm light is faint.
    @Test func waitingBorderAndDarkLightAreQuiet() throws {
        for name in ["light", "dark"] {
            let border = try #require(Theme.builtIn(name).color("color.border.waiting"))
            #expect(abs(border.alpha - 0.3) < 0.02, "\(name)")
        }
        #expect(try Theme.builtIn("dark").number("opacity.atmosphere.light") == 0.2)
        let light = try Theme.builtIn("light")
        #expect(light.string("font.reason.weight") == "regular")
        #expect(light.number("font.hint.size") == 11)
    }

    @Test func darkAndLightAreDifferentAppearances() throws {
        #expect(try !Theme.builtIn("light").isDark)
        #expect(try Theme.builtIn("dark").isDark)
        #expect(try !Theme.builtIn("high-contrast").isDark)
        #expect(try Theme.builtIn("light").name == "Fog Light")
        #expect(try Theme.builtIn("dark").name == "Fog Dark")
    }

    /// The theme follows the macOS appearance. `DESIGN.md` 8.1.
    @Test func themeFollowsSystemAppearance() {
        #expect(Theme.builtInName(systemIsDark: true) == "dark")
        #expect(Theme.builtInName(systemIsDark: false) == "light")
    }

    @Test func appearanceOverrideReadsOnlyTheHiddenArgument() {
        #expect(Theme.appearanceOverride(arguments: ["Spyre", "-SpyreAppearance", "dark"]) == true)
        #expect(Theme.appearanceOverride(arguments: ["Spyre", "-SpyreAppearance", "Light"]) == false)
        #expect(Theme.appearanceOverride(arguments: ["Spyre", "-SpyreAppearance", "blue"]) == nil)
        #expect(Theme.appearanceOverride(arguments: ["Spyre", "-SpyreAppearance"]) == nil)
        #expect(Theme.appearanceOverride(arguments: ["Spyre"]) == nil)
    }

    @Test func compositingTranslucentColor() throws {
        let half = try #require(RGBA(hex: "#00000080"))
        let white = try #require(RGBA(hex: "#FFFFFF"))
        let result = half.composited(over: white)
        #expect(result.alpha == 1)
        #expect(abs(result.red - (1 - Double(0x80) / 255)) < 0.0001)
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
        #expect(dark.number("radius.panel") == 8)
        #expect(dark.color("color.text.primary") == RGBA(hex: "#E4E7EA"))
    }

    @Test func hexParsing() {
        #expect(RGBA(hex: "#FFFFFF")?.alpha == 1)
        #expect(RGBA(hex: "#00000080")?.alpha == Double(0x80) / 255)
        #expect(RGBA(hex: "FFFFFF") == nil)
        #expect(RGBA(hex: "#FFF") == nil)
    }
}
