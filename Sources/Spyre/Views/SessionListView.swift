import SpyreCore
import SwiftUI

/// Sessions grouped by status, each group with a header. Child rows sit under their parent, indented. `SPEC.md` 4.2.
struct SessionListView: View {
    let sessions: [SessionRecord]
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.value("space.md")) {
            ForEach(sessions.grouped(), id: \.group) { entry in
                Text(entry.group.title)
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
                ForEach(entry.rows) { row in
                    SessionRow(session: row.session)
                        .padding(.leading, row.isNested ? tokens.value("space.lg") : 0)
                }
            }
        }
    }
}

/// One session row. Status shows as color, icon, and text label, never color alone.
struct SessionRow: View {
    let session: SessionRecord
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(spacing: tokens.value("space.sm")) {
            Image(systemName: tokens.statusIcon(session.status))
                .font(.system(size: tokens.value("size.icon.status")))
                .foregroundStyle(tokens.statusColor(session.status))
            VStack(alignment: .leading, spacing: tokens.value("space.xs")) {
                Text(session.projectName)
                    .font(tokens.font("body"))
                    .foregroundStyle(tokens.color("color.text.primary"))
                Text(detail)
                    .font(tokens.font("label"))
                    .foregroundStyle(tokens.color("color.text.secondary"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, tokens.value("space.md"))
        .frame(minHeight: tokens.value("size.row.height"))
        .background(
            tokens.color("color.surface.card").opacity(tokens.value("opacity.card")),
            in: RoundedRectangle(cornerRadius: tokens.value("radius.row"))
        )
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [session.agent.title, session.status.rawValue.capitalized]
        if let branch = session.branch { parts.insert(branch, at: 1) }
        parts += session.tags
        if session.isStale { parts.append("stale") }
        return parts.joined(separator: " · ")
    }
}

extension StatusGroup {
    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .working: "Working"
        case .idle: "Idle"
        case .unknown: "Unknown"
        case .done: "Done"
        }
    }
}

extension AgentType {
    var title: String { self == .claudeCode ? "Claude Code" : "Codex" }
}
