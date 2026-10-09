import SpyreCore
import SwiftUI

/// The atmospheric background: soft fog over faint distant ridges. `DESIGN.md` 2.1.
///
/// It is environment, not content: hidden from VoiceOver and never hit-tested.
/// The scene is static SwiftUI. Only the fog bands drift, and Core Animation moves them in the render server,
/// so the drift costs almost no app CPU and never re-lays out the window. Under Reduce Motion the drift stops.
struct AtmosphereView: View {
    /// How strong the scenery is. Dense screens (the session list) use less.
    enum Density {
        case scenic, dense
    }

    var density: Density = .scenic
    /// The scenery (light, ridges, fog bands) fills only this many points at the bottom. `nil` fills the view.
    /// The sky tone always fills the view.
    var sceneryHeight: CGFloat?
    @Environment(\.tokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size
            let size = CGSize(width: full.width, height: min(full.height, sceneryHeight ?? full.height))
            ZStack(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: tokens.color("color.atmosphere.sky"), location: 0),
                        .init(color: tokens.color("color.atmosphere.horizon"), location: Atmosphere.horizonStop),
                        .init(color: tokens.color("color.atmosphere.fog"), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                ZStack {
                    warmLight(size)
                    ridge(0, "color.atmosphere.ridgeFar")
                    fogBand(0, size: size, direction: -1)
                    ridge(1, "color.atmosphere.ridgeMid")
                    fogBand(1, size: size, direction: 1)
                    ridge(2, "color.atmosphere.ridgeNear")
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(width: full.width, height: full.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var strength: Double {
        let scenery = tokens.value("opacity.atmosphere.scenery")
        return density == .dense ? scenery * tokens.value("opacity.atmosphere.dense") : scenery
    }

    private func warmLight(_ size: CGSize) -> some View {
        let light = tokens.color("color.atmosphere.light")
        return RadialGradient(
            colors: [light.opacity(tokens.value("opacity.atmosphere.light") * strength), light.opacity(0)],
            center: UnitPoint(x: Atmosphere.lightCenter.x, y: Atmosphere.lightCenter.y),
            startRadius: 0, endRadius: size.width * Atmosphere.lightRadius
        )
    }

    private func ridge(_ index: Int, _ color: String) -> some View {
        RidgeShape(heights: Atmosphere.ridges[index].heights)
            .fill(tokens.color(color))
            .blur(radius: tokens.value("blur.atmosphere.ridge") * Atmosphere.ridgeBlurScales[index])
            .opacity(strength)
    }

    private func fogBand(_ index: Int, size: CGSize, direction: CGFloat) -> some View {
        let band = Atmosphere.fogBands[index]
        return FogBand(
            color: tokens.cgColor("color.atmosphere.fog"),
            opacity: tokens.value("opacity.atmosphere.fog"),
            drift: reduceMotion ? 0 : tokens.value("size.atmosphere.drift") * direction,
            period: tokens.value("motion.duration.drift")
        )
        .frame(width: size.width * Atmosphere.fogBandWidth, height: size.height * band.height)
        .position(x: size.width / 2, y: size.height * band.y)
    }
}

/// A filled ridge: a smooth line through the heights, closed along the bottom edge.
/// The line runs a little past both edges, so the blur never shows an edge.
private struct RidgeShape: Shape {
    let heights: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard heights.count > 1 else { return path }
        let overscan = rect.width * Atmosphere.ridgeOverscan
        let left = rect.minX - overscan
        let step = (rect.width + 2 * overscan) / CGFloat(heights.count - 1)
        let points = heights.enumerated().map { index, height in
            CGPoint(x: left + CGFloat(index) * step, y: rect.minY + rect.height * height)
        }
        path.move(to: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let middle = CGPoint(x: (previous.x + points[index].x) / 2, y: (previous.y + points[index].y) / 2)
            path.addQuadCurve(to: middle, control: previous)
        }
        if let last = points.last { path.addLine(to: last) }
        path.addLine(to: CGPoint(x: rect.maxX + overscan, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One soft fog band: a radial fade from the fog color to transparent.
/// It drifts `drift` points left and right, once per `period` seconds. A `drift` of 0 keeps it still.
private struct FogBand: NSViewRepresentable {
    let color: CGColor
    let opacity: CGFloat
    let drift: CGFloat
    let period: CGFloat

    func makeNSView(context: Context) -> FogLayerView { FogLayerView() }

    func updateNSView(_ view: FogLayerView, context: Context) {
        view.configure(color: color, opacity: opacity, drift: drift, period: period)
    }
}

/// The layer-backed view behind `FogBand`.
final class FogLayerView: NSView {
    private let fog = CAGradientLayer()
    private var drift: CGFloat = 0
    private var period: CGFloat = 0
    private let driftKey = "drift"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fog.type = .radial
        fog.startPoint = CGPoint(x: 0.5, y: 0.5)
        fog.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(fog)
    }

    required init?(coder: NSCoder) { nil }

    func configure(color: CGColor, opacity: CGFloat, drift: CGFloat, period: CGFloat) {
        // A smooth falloff: full at the center, a third at mid radius, none at the edge. No hard band edge.
        fog.colors = [1, 0.6, 0.25, 0].map { color.copy(alpha: opacity * $0) ?? color }
        fog.locations = [0, 0.35, 0.65, 1]
        if self.drift != drift || self.period != period {
            self.drift = drift
            self.period = period
            fog.removeAnimation(forKey: driftKey)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fog.frame = bounds
        CATransaction.commit()
        guard drift != 0, period > 0, fog.animation(forKey: driftKey) == nil else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = -drift
        move.toValue = drift
        move.duration = Double(period) / 2
        move.autoreverses = true
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fog.add(move, forKey: driftKey)
    }
}
