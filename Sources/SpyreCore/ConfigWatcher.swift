import Foundation

/// Reloads `config.json` when the file or its folder changes.
/// It watches the folder too, because editors often save by replacing the file (atomic rename).
/// All state lives on one private serial queue.
public final class ConfigWatcher: @unchecked Sendable {
    private let file: ConfigFile
    private let onChange: @Sendable (ConfigLoadResult) -> Void
    private let queue = DispatchQueue(label: "spyre.config-watcher")
    private var folderSource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var reloadPending = false

    /// Calls `onChange` once with the current config, then again after each change. Runs on a background queue.
    public init(file: ConfigFile, onChange: @escaping @Sendable (ConfigLoadResult) -> Void) {
        self.file = file
        self.onChange = onChange
        queue.async { self.reload() }
    }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    /// Watches before it reads, so a change after the read always fires an event.
    /// On first launch `load()` creates the folder and file. Then it watches and reads again.
    private func reload() {
        reloadPending = false
        let watching = watch()
        var result = file.load()
        if !watching, watch() { result = file.load() }
        onChange(result)
    }

    /// Watches the folder and the current file. Returns `true` when both are watched.
    private func watch() -> Bool {
        if folderSource == nil {
            folderSource = makeSource(file.folder.path, events: .write)
        }
        fileSource?.cancel()
        fileSource = makeSource(file.url.path, events: [.write, .extend, .delete, .rename])
        return folderSource != nil && fileSource != nil
    }

    /// Coalesces bursts of events (an editor save can fire several) into one reload.
    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        queue.asyncAfter(deadline: .now() + 0.2) { self.reload() }
    }

    private func makeSource(
        _ path: String, events: DispatchSource.FileSystemEvent
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
