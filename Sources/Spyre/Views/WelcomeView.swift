import SwiftUI

/// The first-run screen. It only renders. `WelcomePresenter` decides when it shows. `SPEC.md` 4.8.
/// "Start watching" has no keyboard shortcut. A stray Return must not accept the screen. `SPEC.md` 4.8.
struct WelcomeView: View {
    /// The global shortcut in human form, for example "⌃⌥S".
    let shortcut: String
    let onStart: () -> Void
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            Label("Welcome to Spyre", systemImage: tokens.icon("icon.app"))
                .font(tokens.font("title"))
                .foregroundStyle(tokens.color("color.text.primary"))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: tokens.value("space.md")) {
                WelcomeSection(
                    title: "What Spyre does",
                    text: "Spyre shows your Claude Code and Codex sessions in one place."
                )
                WelcomeSection(
                    title: "What Spyre reads",
                    text: "Spyre reads session files and the process list. It reads these folders:\n"
                        + "~/.claude/sessions\n~/.claude/projects\n~/.codex (state database and sessions)"
                )
                WelcomeSection(
                    title: "Privacy",
                    text: "Everything stays on this Mac. Spyre uses no network. Spyre has no telemetry."
                )
                WelcomeSection(
                    title: "Read-only",
                    text: "Spyre never changes your agent sessions or settings."
                )
                WelcomeSection(
                    title: "Open Spyre",
                    text: "Press \(shortcut), or open the Spyre app again. "
                        + "The menubar icon can be hidden when the menubar is full."
                )
            }
            .padding(tokens.value("space.lg"))
            .background(
                tokens.color("color.surface.card").opacity(reduceTransparency ? 1 : tokens.value("opacity.card")),
                in: RoundedRectangle(cornerRadius: tokens.value("radius.card"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.value("radius.card"))
                    .strokeBorder(tokens.color("color.border.subtle"), lineWidth: tokens.value("size.border"))
            )
            Button("Start watching", action: onStart)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(tokens.color("color.accent"))
                .accessibilityLabel("Start watching")
                .accessibilityHint("Closes this screen. It does not show again at launch.")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(tokens.value("space.xl"))
        .frame(width: tokens.value("size.welcome.width"))
        .background(tokens.color("color.background.base"))
    }
}

/// One titled block of text on the first-run screen.
private struct WelcomeSection: View {
    let title: String
    let text: String
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
            Text(title)
                .font(tokens.font("label"))
                .foregroundStyle(tokens.color("color.text.secondary"))
            Text(text)
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.primary"))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
