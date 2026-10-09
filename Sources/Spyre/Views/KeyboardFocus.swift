import SpyreCore
import SwiftUI

/// The keyboard focus areas of the main window, in Tab order. `SPEC.md` 4.2.
enum MainFocus: Hashable {
    case switcher
    case list
}

/// The bounds of the item with keyboard focus. The list draws one ring there, above every panel,
/// so a panel's clip shape never cuts the ring.
struct FocusRingKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Reports this view's bounds as the focus ring place while `isFocused`.
    func focusRingAnchor(_ isFocused: Bool) -> some View {
        anchorPreference(key: FocusRingKey.self, value: .bounds) { isFocused ? $0 : nil }
    }

    /// Draws the keyboard focus ring reported by `focusRingAnchor`: `color.focus`, `size.focus.width`
    /// (`size.focus.widthIncreased` under Increase Contrast), `size.focus.offset` outside the item, `radius.row`.
    func focusRingOverlay() -> some View {
        overlayPreferenceValue(FocusRingKey.self) { anchor in
            FocusRing(anchor: anchor)
        }
    }
}

private struct FocusRing: View {
    let anchor: Anchor<CGRect>?
    @Environment(\.tokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            if let anchor {
                let width = tokens.value(contrast == .increased ? "size.focus.widthIncreased" : "size.focus.width")
                let outset = tokens.value("size.focus.offset") + width / 2
                let rect = proxy[anchor].insetBy(dx: -outset, dy: -outset)
                RoundedRectangle(cornerRadius: tokens.value("radius.row") + outset)
                    .stroke(tokens.color("color.focus"), lineWidth: width)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension RadarKey {
    /// The Radar key for a key press. `nil` for keys the list does not handle (Tab, letters, modifiers).
    init?(_ press: KeyPress) {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return nil }
        switch press.key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .space: self = .space
        case .return: self = .return
        case .escape: self = .escape
        default: return nil
        }
    }

    /// The keys `RadarKey(_:)` maps.
    static let keys: Set<KeyEquivalent> = [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return, .escape]
}
