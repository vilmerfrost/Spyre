import Foundation
import SQLite3

/// One row of the Codex `threads` table. Holds no messages.
struct CodexThread: Sendable, Equatable {
    var id: String
    var rolloutPath: String
    var cwd: String
    var gitBranch: String?
    var updatedAt: Date
    var cliVersion: String?
    /// `threads.source`, for example `exec` or `vscode`. `nil` when the column is missing.
    var source: String?
    /// `threads.originator`, for example `codex-tui`, `codex_exec`, or `Codex Desktop`.
    var originator: String?
    /// `threads.title`. Codex can derive it from the first prompt. Shown locally only. Never logged.
    var title: String? = nil
}

/// Reads `~/.codex/state_<n>.sqlite`, table `threads`. `SPEC.md` 5.2 A.
///
/// Opens the file with `SQLITE_OPEN_READONLY`. Never writes and never checkpoints.
struct CodexThreadIndex: Sendable {
    /// Why the index could not be read. The message never holds row data.
    struct Failure: Error, Equatable {
        var message: String
    }

    var codexRoot: URL

    /// The state file with the highest schema version, and that version.
    func latestDatabase() -> (url: URL, version: Int)? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: codexRoot.path)) ?? []
        return names.compactMap { name -> (URL, Int)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst("state_".count).dropLast(".sqlite".count))
            else { return nil }
            return (codexRoot.appendingPathComponent(name), version)
        }
        .max { $0.1 < $1.1 }
    }

    /// All threads that are not archived.
    func threads(in url: URL) -> Result<[CodexThread], Failure> {
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            return .failure(Failure(message: "cannot open state database"))
        }
        sqlite3_busy_timeout(db, 200)

        // Later columns. Older schemas may not have them.
        let columns = columnNames(db)
        let optional = ["cli_version", "source", "originator", "title"]
            .map { columns.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        let sql = """
            SELECT id, rollout_path, cwd, git_branch, updated_at_ms, \(optional)
            FROM threads WHERE archived = 0
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
            return .failure(Failure(message: "threads table has an unknown schema"))
        }

        var rows: [CodexThread] = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return .failure(Failure(message: "threads query failed")) }
            guard let id = text(query, 0), let rollout = text(query, 1), let cwd = text(query, 2) else { continue }
            rows.append(CodexThread(
                id: id,
                rolloutPath: rollout,
                cwd: cwd,
                gitBranch: text(query, 3),
                updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(query, 4)) / 1000),
                cliVersion: text(query, 5),
                source: text(query, 6),
                originator: text(query, 7),
                title: text(query, 8)
            ))
        }
        return .success(rows)
    }

    private func columnNames(_ db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK,
              let query = statement
        else { return [] }
        var names: Set<String> = []
        while sqlite3_step(query) == SQLITE_ROW {
            if let name = text(query, 1) { names.insert(name) }
        }
        return names
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }
}
