import Foundation
import Testing
@testable import SpyreCore

/// Each test gets its own temp folder. Tests never touch the real Application Support folder.
private func tempFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SpyreConfigTests-\(UUID().uuidString)", isDirectory: true)
}

private func load(_ json: String) -> ConfigLoadResult {
    ConfigFile.parse(Data(json.utf8))
}

@Suite(.timeLimit(.minutes(1)))
struct ConfigFileTests {
    @Test func validFileLoads() {
        let result = load(#"{"alertDelay":5,"noActivityThreshold":900,"adapterRefreshTimeout":1.5}"#)
        #expect(result.config == SpyreConfig(alertDelay: 5, noActivityThreshold: 900, adapterRefreshTimeout: 1.5))
        #expect(result.warnings.isEmpty)
    }

    @Test func partialFileKeepsOtherDefaults() {
        let result = load(#"{"alertDelay":7}"#)
        #expect(result.config == SpyreConfig(alertDelay: 7))
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: ["{not json", "", "[1,2]", "42"])
    func invalidJSONGivesDefaultsAndWarning(json: String) {
        let result = load(json)
        #expect(result.config == .default)
        #expect(result.warnings.count == 1)
    }

    @Test func unknownKeysAreIgnoredWithWarning() {
        let result = load(#"{"alertDelay":4,"theme":"dark"}"#)
        #expect(result.config == SpyreConfig(alertDelay: 4))
        #expect(result.warnings == [#"Unknown key "theme" in config.json is ignored."#])
    }

    @Test func wrongTypeFallsBackPerKey() {
        let result = load(#"{"alertDelay":"5","noActivityThreshold":true,"adapterRefreshTimeout":3}"#)
        #expect(result.config == SpyreConfig(adapterRefreshTimeout: 3))
        #expect(result.warnings.count == 2)
    }

    @Test func outOfRangeIsClamped() {
        let result = load(#"{"alertDelay":-1,"noActivityThreshold":1}"#)
        #expect(result.config.alertDelay == 0)
        #expect(result.config.noActivityThreshold == 60)
        #expect(result.warnings.count == 2)
    }

    @Test func doneRowTimeoutDefaultInvalidAndClamp() {
        #expect(SpyreConfig.default.doneRowTimeout == 600)
        #expect(load(#"{"doneRowTimeout":120}"#).config.doneRowTimeout == 120)
        let wrongType = load(#"{"doneRowTimeout":"10 min"}"#)
        #expect(wrongType.config.doneRowTimeout == 600)
        #expect(wrongType.warnings.count == 1)
        #expect(load(#"{"doneRowTimeout":-5}"#).config.doneRowTimeout == 0)
        let high = load(#"{"doneRowTimeout":1000000}"#)
        #expect(high.config.doneRowTimeout == 86_400)
        #expect(high.warnings.count == 1)
    }

    @Test func missingFileIsCreatedWithDefaults() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = ConfigFile(folder: folder)

        let first = file.load()
        #expect(first.config == .default)
        #expect(first.warnings.isEmpty)
        let written = try Data(contentsOf: file.url)
        #expect(ConfigFile.parse(written) == ConfigLoadResult(config: .default, warnings: []))
    }

    @Test func existingFileIsReadNotOverwritten() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = ConfigFile(folder: folder)
        try Data(#"{"alertDelay":9}"#.utf8).write(to: file.url)

        #expect(file.load().config.alertDelay == 9)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == #"{"alertDelay":9}"#)
    }

    @Test(.timeLimit(.minutes(1))) func watcherReloadsAfterAtomicReplace() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (stream, continuation) = AsyncStream.makeStream(of: ConfigLoadResult.self)
        let watcher = ConfigWatcher(file: ConfigFile(folder: folder)) { continuation.yield($0) }
        var results = stream.makeAsyncIterator()

        #expect(await results.next()?.config == .default)
        // `.atomic` writes a temp file and renames it over the old one, like most editors.
        try Data(#"{"alertDelay":11}"#.utf8).write(to: folder.appendingPathComponent("config.json"), options: .atomic)
        // `next()` gives `nil` after a time-limit cancel. Stop then, so the test fails instead of spinning.
        var latest = await results.next()
        while let result = latest, result.config.alertDelay != 11 { latest = await results.next() }
        #expect(latest?.config.alertDelay == 11)
        withExtendedLifetime(watcher) {}
    }
}
