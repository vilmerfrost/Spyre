import SpyreCore
import SwiftUI

/// The pill section switcher: Radar, Grab, Lab. A custom control, so it reads the theme tokens
/// and never follows the system appearance on its own. `DESIGN.md` 2.
struct SectionSwitcher: View {
    @Binding var selection: AppSection
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { section in
                segment(section)
            }
        }
        .padding(tokens.value("space.xxs"))
        .frame(height: tokens.value("size.switcher.height"))
        .background(
            tokens.color(reduceTransparency ? "color.surface.row" : "color.surface.control"), in: Capsule()
        )
        .overlay(Capsule().strokeBorder(tokens.color("color.border.subtle"), lineWidth: tokens.value("size.border")))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section")
    }

    private func segment(_ section: AppSection) -> some View {
        let selected = section == selection
        return Button {
            withAnimation(.snappy(duration: tokens.duration("motion.duration.normal", reduceMotion: reduceMotion))) {
                selection = section
            }
        } label: {
            Text(section.rawValue)
                .font(tokens.font("control"))
                .foregroundStyle(tokens.color(selected ? "color.text.primary" : "color.text.secondary"))
                .padding(.horizontal, tokens.value("space.md"))
                .frame(maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule()
                            .fill(tokens.color("color.surface.controlSelected"))
                            .overlay(Capsule().strokeBorder(
                                tokens.color("color.border.subtle"), lineWidth: tokens.value("size.border")
                            ))
                            .shadow(color: tokens.color("color.shadow.panel"), radius: tokens.value("space.xxs"))
                            .matchedGeometryEffect(id: "selection", in: selectionSpace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Spyre's buttons. Primary is the one frost-blue action on a screen. `DESIGN.md` 2.
struct SpyreButtonStyle: ButtonStyle {
    enum Kind {
        /// Accent fill. One per screen.
        case primary
        /// Quiet text that brightens on hover.
        case quiet
    }

    var kind: Kind
    @Environment(\.tokens) private var tokens
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tokens.font("control"))
            .foregroundStyle(tokens.color(foreground))
            .padding(.horizontal, kind == .primary ? tokens.value("space.md") : tokens.value("space.xs"))
            .padding(.vertical, kind == .primary ? tokens.value("space.xs") + tokens.value("space.xxs") : 0)
            .background {
                if kind == .primary {
                    RoundedRectangle(cornerRadius: tokens.value("radius.button"))
                        .fill(tokens.color("color.accent"))
                        .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.03 : 0))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: tokens.value("motion.duration.fast")), value: hovering)
    }

    private var foreground: String {
        switch kind {
        case .primary: "color.text.onAccent"
        case .quiet: hovering ? "color.text.primary" : "color.text.secondary"
        }
    }
}

/// The status glyph at the start of a row. Working sessions show a slow spinner.
/// Under Reduce Motion the spinner is a static partial arc. `DESIGN.md` 10.3.
struct StatusGlyph: View {
    let status: SessionStatus
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if status == .working {
                SpinnerArc(
                    color: tokens.cgColor("color.status.working"),
                    lineWidth: tokens.value("size.spinner.line"),
                    period: reduceMotion ? 0 : tokens.value("motion.duration.ring")
                )
                .frame(width: tokens.value("size.icon.status"), height: tokens.value("size.icon.status"))
            } else {
                Image(systemName: tokens.statusIcon(status))
                    .font(.system(size: tokens.value("size.icon.status"), weight: .medium))
                    .foregroundStyle(tokens.statusColor(status))
            }
        }
        .frame(width: tokens.value("size.status.column"), height: tokens.value("size.status.column"))
        .accessibilityHidden(true)
    }
}

/// A partial arc that turns once per `period` seconds. Core Animation turns it in the render server,
/// so a working row costs almost no app CPU. A `period` of 0 draws a static arc.
private struct SpinnerArc: NSViewRepresentable {
    let color: CGColor
    let lineWidth: CGFloat
    let period: CGFloat

    func makeNSView(context: Context) -> SpinnerLayerView { SpinnerLayerView() }

    func updateNSView(_ view: SpinnerLayerView, context: Context) {
        view.configure(color: color, lineWidth: lineWidth, period: period)
    }
}

/// The layer-backed view behind `SpinnerArc`. It redraws the arc when its size changes.
final class SpinnerLayerView: NSView {
    private let arc = CAShapeLayer()
    private var lineWidth: CGFloat = 1
    private var period: CGFloat = 0
    /// The visible part of the circle.
    private let arcLength: CGFloat = 0.72
    private let spinKey = "spin"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        arc.strokeEnd = arcLength
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { nil }

    func configure(color: CGColor, lineWidth: CGFloat, period: CGFloat) {
        arc.strokeColor = color
        self.lineWidth = lineWidth
        if self.period != period {
            self.period = period
            arc.removeAnimation(forKey: spinKey)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        arc.frame = bounds
        arc.lineWidth = lineWidth
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        guard period > 0, arc.animation(forKey: spinKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = Double(period)
        spin.repeatCount = .infinity
        arc.add(spin, forKey: spinKey)
    }
}

/// A small bordered tag on a row: `exec`, `experimental`, `stale`.
struct RowTag: View {
    let text: String
    @Environment(\.tokens) private var tokens

    var body: some View {
        Text(text)
            .font(tokens.font("tag"))
            .foregroundStyle(tokens.color("color.text.secondary"))
            .padding(.horizontal, tokens.value("space.xs"))
            .overlay(
                RoundedRectangle(cornerRadius: tokens.value("radius.tag"))
                    .strokeBorder(tokens.color("color.border.row"), lineWidth: tokens.value("size.border"))
            )
    }
}

/// A thin bordered panel that holds rows. Not a card: small radius, hairline border, soft shadow.
struct Panel<Content: View>: View {
    var surface = "color.surface.row"
    var border = "color.border.row"
    @ViewBuilder let content: () -> Content
    @Environment(\.tokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.value("radius.panel"))
        VStack(spacing: 0, content: content)
            .background(tokens.color(surface), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(tokens.color(border), lineWidth: tokens.value("size.border")))
            .shadow(
                color: tokens.color("color.shadow.panel"),
                radius: tokens.value("shadow.panel.radius"), y: tokens.value("shadow.panel.y")
            )
    }
}

/// A hairline between rows. By default it starts at the title column, past the status glyph.
struct RowDivider: View {
    var inset = true
    @Environment(\.tokens) private var tokens

    var body: some View {
        Rectangle()
            .fill(tokens.color("color.border.divider"))
            .frame(height: tokens.value("size.border"))
            .padding(.leading, inset ? tokens.value("space.md") * 2 + tokens.value("size.status.column") : 0)
    }
}
