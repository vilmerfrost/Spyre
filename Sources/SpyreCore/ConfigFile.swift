import Foundation

/// The file operations that config loading needs. Tests inject a temp folder; the app uses `FileManager`.
public protocol ConfigFileSystem: Sendable {
    func contents(of url: URL) -> Data?
    func write(_ data: Data, to url: URL) throws
    func createFolder(at url: URL) throws
}

/// The real file system.
public struct LocalConfigFileSystem: ConfigFileSystem {
    public init() {}

    public func contents(of url: URL) -> Data? {
        FileManager.default.contents(atPath: url.path)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func createFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

/// A loaded config and the problems found in the file. A warning never stops the app.
public struct ConfigLoadResult: Sendable, Equatable {
    public var config: SpyreConfig
    public var warnings: [String]
}

/// Reads `config.json` from Spyre's own folder. See `SPEC.md` 4.4 for the format.
public struct ConfigFile: Sendable {
    public static let fileName = "config.json"

    /// Valid range per key, in seconds. A value outside the range is clamped.
    static let ranges: [String: ClosedRange<Double>] = [
        "alertDelay": 0...300,
        "noActivityThreshold": 60...86_400,
        "adapterRefreshTimeout": 0.5...60,
    ]

    public let folder: URL
    private let fileSystem: any ConfigFileSystem

    public var url: URL { folder.appendingPathComponent(Self.fileName) }

    public init(folder: URL, fileSystem: any ConfigFileSystem = LocalConfigFileSystem()) {
        self.folder = folder
        self.fileSystem = fileSystem
    }

    /// `~/Library/Application Support/Spyre`, the only folder Spyre writes to.
    public static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Spyre", isDirectory: true)
    }

    /// Loads the file. A missing file is created with the defaults.
    public func load() -> ConfigLoadResult {
        guard let data = fileSystem.contents(of: url) else {
            do {
                try fileSystem.createFolder(at: folder)
                try fileSystem.write(Self.encode(.default), to: url)
                return ConfigLoadResult(config: .default, warnings: [])
            } catch {
                return ConfigLoadResult(config: .default, warnings: ["Cannot create config.json. Using defaults."])
            }
        }
        return Self.parse(data)
    }

    /// Parses the file. Bad keys fall back per key; a bad file falls back to all defaults.
    public static func parse(_ data: Data) -> ConfigLoadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            let warning = "config.json is not a valid JSON object. Using defaults."
            return ConfigLoadResult(config: .default, warnings: [warning])
        }
        var config = SpyreConfig.default
        var warnings: [String] = []
        for key in root.keys.sorted() where ranges[key] == nil {
            warnings.append("Unknown key \"\(key)\" in config.json is ignored.")
        }
        for (key, range) in ranges.sorted(by: { $0.key < $1.key }) {
            guard let raw = root[key] else { continue }
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                warnings.append("\"\(key)\" must be a number of seconds. Using the default.")
                continue
            }
            let value = min(max(number.doubleValue, range.lowerBound), range.upperBound)
            if value != number.doubleValue {
                warnings.append("\"\(key)\" is out of range \(range). Using \(value).")
            }
            config[key] = value
        }
        return ConfigLoadResult(config: config, warnings: warnings)
    }

    static func encode(_ config: SpyreConfig) throws -> Data {
        let object = ranges.keys.reduce(into: [String: Double]()) { $0[$1] = config[$1] }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

extension SpyreConfig {
    /// Access by JSON key. Unknown keys read as 0 and are not written.
    subscript(key: String) -> TimeInterval {
        get {
            switch key {
            case "alertDelay": alertDelay
            case "noActivityThreshold": noActivityThreshold
            case "adapterRefreshTimeout": adapterRefreshTimeout
            default: 0
            }
        }
        set {
            switch key {
            case "alertDelay": alertDelay = newValue
            case "noActivityThreshold": noActivityThreshold = newValue
            case "adapterRefreshTimeout": adapterRefreshTimeout = newValue
            default: break
            }
        }
    }
}
