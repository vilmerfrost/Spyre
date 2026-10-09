import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct WelcomeReturnGuardTests {
    /// `SPEC.md` 4.8: only a click accepts the first-run screen. A stray Return or Escape must do nothing,
    /// so the welcome view has no keyboard shortcut.
    @Test func welcomeViewHasNoKeyboardShortcut() throws {
        let view = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Spyre/Views/WelcomeView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)
        #expect(source.contains("Start watching"))
        #expect(!source.contains(".keyboardShortcut("))
    }
}
