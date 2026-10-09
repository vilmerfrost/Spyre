import Foundation

/// What an adapter can do. `SPEC.md` 6.2. MVP adapters declare `observe` only.
public struct AdapterCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let observe = AdapterCapabilities(rawValue: 1 << 0)
    public static let steer = AdapterCapabilities(rawValue: 1 << 1)
    public static let approve = AdapterCapabilities(rawValue: 1 << 2)
    public static let stop = AdapterCapabilities(rawValue: 1 << 3)
}

/// A problem a source reader found. Never holds message content or secrets.
public struct AdapterDiagnostic: Sendable, Equatable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

/// A full snapshot of all sessions one adapter can see. Not a list of changes.
public struct AdapterSnapshot: Sendable, Equatable {
    public var sessions: [SessionRecord]
    public var diagnostics: [AdapterDiagnostic]
    /// The format version of each source the adapter read, keyed by source name.
    public var formatVersions: [String: String]

    public init(
        sessions: [SessionRecord],
        diagnostics: [AdapterDiagnostic] = [],
        formatVersions: [String: String] = [:]
    ) {
        self.sessions = sessions
        self.diagnostics = diagnostics
        self.formatVersions = formatVersions
    }
}

/// All support for one agent type. `SPEC.md` 6.4 is the full contract.
///
/// The app injects root folders, a process list provider, and a clock at init.
/// An adapter never writes agent files, reads secrets, makes network calls, or touches UI state.
public protocol AgentAdapter: Sendable {
    var agent: AgentType { get }
    var capabilities: AdapterCapabilities { get }

    /// Reads all sources and returns a snapshot. Never throws.
    /// A source that cannot be read gives `unknown` sessions and a diagnostic.
    func refresh() async -> AdapterSnapshot

    /// Emits a value when a source changes, so the app can refresh.
    func changes() -> AsyncStream<Void>
}
