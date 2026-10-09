import SpyreCore
import SwiftUI

/// The three app sections. Only Radar is in the MVP.
enum AppSection: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case grab = "Grab"
    case lab = "Lab"

    var id: String { rawValue }
}

/// The main window: atmosphere, a header with the section switcher, and one centered content column.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var section: AppSection = .radar

    var body: some View {
        ZStack(alignment: .top) {
            AtmosphereView(density: .dense)
            VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
                header
                switch section {
                case .radar: RadarView()
                case .grab, .lab: ComingSoonView(section: section)
                }
            }
            .frame(maxWidth: tokens.value("size.content.maxWidth"), maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, tokens.value("space.xl"))
        }
        .frame(minWidth: tokens.value("size.window.width"), minHeight: tokens.value("size.window.height"))
        .background(tokens.color("color.background.base"))
    }

    private var header: some View {
        HStack {
            SectionSwitcher(selection: $section)
            Spacer()
            Text(model.config.hotkey.displayString)
                .font(tokens.font("control").monospacedDigit())
                .foregroundStyle(tokens.color("color.text.secondary"))
                .help("Opens Spyre from any app")
                .accessibilityLabel("Shortcut \(model.config.hotkey.displayString) opens Spyre")
        }
        .padding(.top, tokens.value("space.sm"))
    }
}

/// The Radar section: the count line, then the grouped session list.
private struct RadarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
                CountLine(counts: SessionCounts(model.sessions))
                if model.sessions.isEmpty {
                    EmptyRadarView()
                } else {
                    ScrollView {
                        SessionListView(sessions: model.sessions, now: context.date)
                            .padding(.bottom, tokens.value("space.xl"))
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
    }
}

/// No sessions. Short, calm, and says what to do next.
private struct EmptyRadarView: View {
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
            Text("Quiet out here.")
                .font(tokens.font("rowTitle"))
                .foregroundStyle(tokens.color("color.text.primary"))
            Text("Start Claude Code or Codex in a terminal. Spyre picks it up within a second or two.")
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.secondary"))
        }
        .padding(.top, tokens.value("space.sm"))
    }
}

/// The placeholder for sections that are not in the MVP.
struct ComingSoonView: View {
    let section: AppSection
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
            Text(section.rawValue)
                .font(tokens.font("title"))
                .foregroundStyle(tokens.color("color.text.primary"))
            Text(section == .grab ? "Coming soon. Capture context with a global shortcut."
                 : "Coming soon. Test and compare agent skills.")
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.secondary"))
        }
        .padding(.top, tokens.value("space.sm"))
    }
}
