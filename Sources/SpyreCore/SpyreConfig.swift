import Foundation

/// Config values from `SPEC.md` 4.4. The MVP has no settings UI for them.
public struct SpyreConfig: Sendable, Equatable {
    /// Seconds a session must stay `waiting` before attention effects start.
    public var alertDelay: TimeInterval
    /// Seconds without activity before a `working` row gets the no-activity flag.
    public var noActivityThreshold: TimeInterval
    /// Seconds before an adapter refresh counts as timed out.
    public var adapterRefreshTimeout: TimeInterval
    /// Seconds a `done` row stays in the list after the session ended.
    public var doneRowTimeout: TimeInterval

    public init(
        alertDelay: TimeInterval = 3,
        noActivityThreshold: TimeInterval = 10 * 60,
        adapterRefreshTimeout: TimeInterval = 2,
        doneRowTimeout: TimeInterval = 10 * 60
    ) {
        self.alertDelay = alertDelay
        self.noActivityThreshold = noActivityThreshold
        self.adapterRefreshTimeout = adapterRefreshTimeout
        self.doneRowTimeout = doneRowTimeout
    }

    public static let `default` = SpyreConfig()

    /// The largest `doneRowTimeout` (24 h). Adapters report `done` sessions at least this long.
    public static let maxDoneRowTimeout: TimeInterval = 86_400
}
