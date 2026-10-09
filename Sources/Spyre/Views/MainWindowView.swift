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
/// The window height fits the content (`DESIGN.md` 2.5). The fog fills the rest.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var section: AppSection = .radar
    @State private var headerHeight: CGFloat = 0
    @State private var sectionHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            AtmosphereView(density: .dense)
            VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
                header.measuredHeight($headerHeight)
                switch section {
                case .radar: RadarView(height: $sectionHeight)
                case .grab, .lab:
                    ComingSoonView(section: section)
                        .padding(.bottom, tokens.value("space.xl"))
                        .measuredHeight($sectionHeight)
                }
            }
            .frame(maxWidth: tokens.value("size.content.maxWidth"), maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, tokens.value("space.xl"))
        }
        .background(tokens.color("color.background.base"))
        .onChange(of: headerHeight + sectionHeight, initial: true) { _, height in
            model.mainContentHeightChanged(height + tokens.value("space.lg"))
        }
    }

    private var header: some View {
        HStack {
            SectionSwitcher(selection: $section)
            Spacer()
            Text(model.config.hotkey.displayString)
                .font(tokens.font("hint"))
                .foregroundStyle(tokens.color("color.text.secondary"))
                .help("Opens Spyre from any app")
                .accessibilityLabel("Shortcut \(model.config.hotkey.displayString) opens Spyre")
        }
        .padding(.top, tokens.value("space.sm"))
    }
}

/// The Radar section: the count line, then the grouped session list. With no sessions: the empty state.
/// It reports the height it needs, so the window can fit it.
private struct RadarView: View {
    @Binding var height: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var topHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let sessions = model.visibleSessions(now: context.date)
            VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
                if sessions.isEmpty {
                    EmptyRadarView()
                        .padding(.bottom, tokens.value("space.xl"))
                        .measuredHeight($topHeight)
                        .onAppear { listHeight = 0 }
                } else {
                    CountLine(content: CountLineContent(SessionCounts(sessions))).measuredHeight($topHeight)
                    ScrollView {
                        SessionListView(sessions: sessions, now: context.date)
                            .padding(.bottom, tokens.value("space.xl"))
                            .measuredHeight($listHeight)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .onChange(of: topHeight + listHeight, initial: true) {
            height = topHeight + (listHeight > 0 ? tokens.value("space.lg") + listHeight : 0)
        }
    }
}

/// No sessions. A still outline ice cube, a short title, and what to do next. No animation.
private struct EmptyRadarView: View {
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: tokens.value("space.sm")) {
            Image(systemName: tokens.icon("icon.empty"))
                .font(.system(size: tokens.value("size.icon.empty"), weight: .light))
                .foregroundStyle(tokens.color("color.text.secondary"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
                Text(EmptyRadar.title)
                    .font(tokens.font("rowTitle"))
                    .foregroundStyle(tokens.color("color.text.primary"))
                Text(EmptyRadar.body)
                    .font(tokens.font("body"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, tokens.value("space.sm"))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Writes the view's height to `height` when it changes.
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
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
