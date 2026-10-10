import SpyreCore
import SwiftUI

/// The three app sections. Only Radar is in the MVP.
enum AppSection: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case grab = "Grab"
    case lab = "Lab"

    var id: String { rawValue }
}

/// The main window with a section switcher.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var section: AppSection = .radar

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.lg")) {
            Picker("Section", selection: $section) {
                ForEach(AppSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .radar: SessionListView(sessions: model.sessions)
            case .grab, .lab: ComingSoonView(section: section)
            }
            Spacer(minLength: 0)
        }
        .padding(tokens.value("space.xl"))
        .frame(minWidth: tokens.value("size.window.width"), minHeight: tokens.value("size.window.height"))
        .background(tokens.color("color.background.base"))
    }
}

/// The placeholder for sections that are not in the MVP.
struct ComingSoonView: View {
    let section: AppSection
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(spacing: tokens.value("space.sm")) {
            Text(section.rawValue)
                .font(tokens.font("title"))
                .foregroundStyle(tokens.color("color.text.primary"))
            Text("Coming soon")
                .font(tokens.font("body"))
                .foregroundStyle(tokens.color("color.text.secondary"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
