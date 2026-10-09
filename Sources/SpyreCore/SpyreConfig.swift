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
    /// Seconds after its last activity before an idle row folds into "Earlier". `SPEC.md` 4.2.
    public var idleFoldAfter: TimeInterval
    /// Seconds after its last activity before an idle row is hidden. `SPEC.md` 4.2.
    public var idleHideAfter: TimeInterval
    /// `true` after the user clicked "Start watching" on the first-run screen. `SPEC.md` 4.8.
    public var welcomeSeen: Bool
    /// The global shortcut that opens the main window.
    public var hotkey: Hotkey
    /// `true` shows Spyre in the Dock. `false` keeps it in the menubar only.
    public var showDockIcon: Bool

    public init(
        alertDelay: TimeInterval = 3,
        noActivityThreshold: TimeInterval = 10 * 60,
        adapterRefreshTimeout: TimeInterval = 2,
        doneRowTimeout: TimeInterval = 10 * 60,
        idleFoldAfter: TimeInterval = 4 * 3_600,
        idleHideAfter: TimeInterval = 24 * 3_600,
        welcomeSeen: Bool = false,
        hotkey: Hotkey = .default,
        showDockIcon: Bool = false
    ) {
        self.alertDelay = alertDelay
        self.noActivityThreshold = noActivityThreshold
        self.adapterRefreshTimeout = adapterRefreshTimeout
        self.doneRowTimeout = doneRowTimeout
        self.idleFoldAfter = idleFoldAfter
        self.idleHideAfter = idleHideAfter
        self.welcomeSeen = welcomeSeen
        self.hotkey = hotkey
        self.showDockIcon = showDockIcon
    }

    public static let `default` = SpyreConfig()

    /// The largest `doneRowTimeout` (24 h). Adapters report `done` sessions at least this long.
    public static let maxDoneRowTimeout: TimeInterval = 86_400
}
