import Foundation
import Testing
@testable import SpyreCore

/// First-run screen. `SPEC.md` 4.8. Each test uses its own temp folder, never the real config.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct WelcomePresenterTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("SpyreWelcomeTests-\(UUID().uuidString)", isDirectory: true)
    private var file: ConfigFile { ConfigFile(folder: folder) }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file.url)
    }

    private func readObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url))
        return try #require(object as? [String: Any])
    }

    /// Loads the file like the app does at launch, and gives the presenter the result.
    private func launch() -> WelcomePresenter {
        let presenter = WelcomePresenter(file: file)
        presenter.configLoaded(file.load().config)
        presenter.appLaunched()
        return presenter
    }

    @Test func showsOnFirstLaunchWithMissingFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(launch().isPresented)
        #expect(try readObject()["welcomeSeen"] as? Bool == false)
    }

    @Test func showsWhenFileHasNoKey() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"alertDelay":5}"#)
        #expect(launch().isPresented)
    }

    @Test func notShownAfterSeen() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"welcomeSeen":true}"#)
        #expect(!launch().isPresented)
    }

    @Test func startWatchingWritesFlagAndKeepsOtherKeys() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"alertDelay":5,"doneRowTimeout":120.5,"futureKey":"keep","welcomeSeen":false}"#)
        let presenter = launch()

        try await presenter.startWatching()

        #expect(!presenter.isPresented)
        let object = try readObject()
        #expect(object["welcomeSeen"] as? Bool == true)
        #expect(object["alertDelay"] as? Double == 5)
        #expect(object["doneRowTimeout"] as? Double == 120.5)
        #expect(object["futureKey"] as? String == "keep")
        #expect(file.load().config == SpyreConfig(alertDelay: 5, doneRowTimeout: 120.5, welcomeSeen: true))
        #expect(!launch().isPresented)
    }

    @Test func startWatchingCreatesMissingFile() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try await WelcomePresenter(file: file).startWatching()
        #expect(file.load() == ConfigLoadResult(config: SpyreConfig(welcomeSeen: true), warnings: []))
    }

    @Test func startWatchingNeverReplacesABadFile() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("{not json")
        let presenter = launch()
        await #expect(throws: ConfigWriteError.notAnObject) { try await presenter.startWatching() }
        #expect(!presenter.isPresented)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "{not json")
    }

    @Test(arguments: [#""yes""#, "1", "null"])
    func wrongTypeGivesDefaultAndWarning(value: String) throws {
        let result = ConfigFile.parse(Data(#"{"welcomeSeen":\#(value)}"#.utf8))
        #expect(result.config.welcomeSeen == false)
        #expect(result.warnings == [#""welcomeSeen" must be true or false. Using the default."#])
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"welcomeSeen":\#(value)}"#)
        #expect(launch().isPresented)
    }

    @Test func reopenFromMenuShowsAndKeepsFlag() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"welcomeSeen":true}"#)
        let presenter = launch()

        presenter.reopen()

        #expect(presenter.isPresented)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == #"{"welcomeSeen":true}"#)
        presenter.closed()
        #expect(!presenter.isPresented)
    }

    @Test func closeWithoutButtonDoesNotCountAsSeen() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let presenter = launch()
        presenter.closed()
        #expect(!presenter.isPresented)
        #expect(launch().isPresented)
    }

    @Test func onlyTheFirstLoadDecides() {
        let presenter = WelcomePresenter(file: file)
        presenter.configLoaded(SpyreConfig(welcomeSeen: true))
        presenter.configLoaded(SpyreConfig(welcomeSeen: false))
        #expect(!presenter.isPresented)
    }

    @Test func windowWaitsForLaunchToFinish() {
        let presenter = WelcomePresenter(file: file)
        presenter.configLoaded(SpyreConfig(welcomeSeen: false))
        #expect(presenter.isPresented)
        #expect(!presenter.showsWindow)
        presenter.appLaunched()
        #expect(presenter.showsWindow)
    }

    @Test func reopenBringsWelcomeBackUntilItIsAnswered() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let presenter = launch()
        #expect(presenter.reopenTarget == .welcome)
        try await presenter.startWatching()
        #expect(presenter.reopenTarget == .mainWindow)
        #expect(!presenter.showsWindow)
    }

    @Test func reopenOpensMainWindowAfterCloseOrWhenSeen() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let presenter = launch()
        presenter.closed()
        #expect(presenter.reopenTarget == .mainWindow)
        try write(#"{"welcomeSeen":true}"#)
        #expect(launch().reopenTarget == .mainWindow)
    }
}
