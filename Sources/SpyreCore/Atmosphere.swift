import Foundation

/// The fixed geometry of the atmospheric background: fog over distant mountain ridges. `DESIGN.md` 2.1.
///
/// All values are fractions of the view size, so the scene scales with the window.
/// Colors, opacities, blur, and drift come from tokens. This type holds only shape.
/// The ridges stay still. Only the fog bands drift.
public enum Atmosphere {
    /// One mountain ridge. Heights are fractions of the view height, measured from the top.
    public struct Ridge: Sendable, Equatable {
        /// The ridge line from left to right: `samples` evenly spaced heights, each in 0...1.
        public var heights: [Double]
    }

    /// Where the sky tone turns into the horizon tone, from the top.
    public static let horizonStop = 0.6
    /// The center of the faint warm light behind the far ridge, as (x, y) fractions.
    public static let lightCenter = (x: 0.72, y: 0.5)
    /// The warm light radius, as a fraction of the view width.
    public static let lightRadius = 0.42
    /// Fog bands: (center y, height) as fractions of the view height.
    public static let fogBands: [(y: Double, height: Double)] = [(0.66, 0.2), (0.84, 0.24)]
    /// Fog band width as a fraction of the view width. Wider than the view, so drift never shows an edge.
    public static let fogBandWidth = 1.4
    /// How far a ridge line runs past each side, as a fraction of the view width, so blur never shows an edge.
    public static let ridgeOverscan = 0.05

    /// Far, middle, and near ridges. Far ridges sit higher and are softer.
    public static let ridges: [Ridge] = [
        ridge(base: 0.66, amplitude: 0.24, seed: 1),
        ridge(base: 0.78, amplitude: 0.15, seed: 2),
        ridge(base: 0.9, amplitude: 0.08, seed: 3),
    ]

    /// Points per ridge line.
    public static let samples = 48

    /// A soft, deterministic ridge line: a broad wave, peaks, shoulders, and fine detail. No randomness at run time.
    static func ridge(base: Double, amplitude: Double, seed: Double) -> Ridge {
        let heights = (0..<samples).map { index -> Double in
            let x = Double(index) / Double(samples - 1)
            let broad = 0.5 + 0.5 * sin(2 * .pi * (0.7 * x + 0.13 * seed))
            let peaks = pow(1 - abs(sin(.pi * (1.7 * x + 0.37 * seed))), 2.2)
            let shoulders = pow(1 - abs(sin(.pi * (3.9 * x + 0.59 * seed))), 2)
            let detail = 0.5 + 0.5 * sin(2 * .pi * (7.3 * x + 0.71 * seed))
            let lift = 0.3 * broad + 0.45 * peaks + 0.2 * shoulders + 0.05 * detail
            return min(1, max(0, base - amplitude * lift))
        }
        return Ridge(heights: heights)
    }
}
