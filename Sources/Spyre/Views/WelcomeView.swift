import SwiftUI

/// The first-run screen. It only renders. `WelcomePresenter` decides when it shows. `SPEC.md` 4.8.
/// "Start watching" has no keyboard shortcut. A stray Return must not accept the screen. `SPEC.md` 4.8.
struct WelcomeView: View {
    /// The global shortcut in human form, for example "⌃⌥S".
    let shortcut: String
    let onStart: () -> Void
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
                Label("Welcome to Spyre", systemImage: tokens.icon("icon.app"))
                    .font(tokens.font("title"))
                    .foregroundStyle(tokens.color("color.text.primary"))
                    .accessibilityAddTraits(.isHeader)
                Text("Spyre shows your Claude Code and Codex sessions in one place, so you see which one needs you.")
                    .font(tokens.font("body"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Panel(surface: "color.surface.card") {
                WelcomeSection(
                    title: "What Spyre reads",
                    text: "Session files and the process list, in these folders:\n"
                        + "~/.claude/sessions\n~/.claude/projects\n~/.codex (state database and sessions)"
                )
                RowDivider(inset: false)
                WelcomeSection(
                    title: "Privacy",
                    text: "Everything stays on this Mac. Spyre uses no network. Spyre has no telemetry."
                )
                RowDivider(inset: false)
                WelcomeSection(
                    title: "Read-only",
                    text: "Spyre never changes your agent sessions or settings."
                )
                RowDivider(inset: false)
                WelcomeSection(
                    title: "Open Spyre",
                    text: "Press \(shortcut), or open the Spyre app again. "
                        + "The menubar icon can be hidden when the menubar is full."
                )
            }
            HStack {
                Spacer()
                Button("Start watching", action: onStart)
                    .buttonStyle(SpyreButtonStyle(kind: .primary))
                    .accessibilityLabel("Start watching")
                    .accessibilityHint("Closes this screen. It does not show again at launch.")
            }
        }
        .padding(.horizontal, tokens.value("space.xl"))
        .padding(.top, tokens.value("space.lg"))
        .padding(.bottom, tokens.value("size.welcome.scenery"))
        .frame(width: tokens.value("size.welcome.width"))
        .background {
            ZStack {
                tokens.color("color.background.base")
                AtmosphereView(density: .scenic, sceneryHeight: tokens.value("size.welcome.sceneHeight"))
            }
        }
    }
}

/// One titled block of text on the first-run screen.
private struct WelcomeSection: View {
    let title: String
    let text: String
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.xxs")) {
            Text(title)
                .font(tokens.font("section"))
                .foregroundStyle(tokens.color("color.text.secondary"))
            Text(text)
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.primary"))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, tokens.value("space.md"))
        .padding(.vertical, tokens.value("space.sm") + tokens.value("space.xxs"))
        .accessibilityElement(children: .combine)
    }
}
