# AGENTS.md

Rules for all coding agents in this repo. Read `SPEC.md` before you start a task.
Read `DESIGN.md` before you change any view.

## Stack

- Language: Swift 6. Turn on strict concurrency checking.
- UI: SwiftUI. Use `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- Minimum macOS: **14.0 (Sonoma)**.
  - `MenuBarExtra` needs macOS 13.
  - macOS 14 adds the Observation framework (`@Observable`). Use it for app state.
  - macOS 14 adds `SettingsLink`. A menubar app needs it to open Settings.
  - macOS 13 is out of security support. Do not target it.
- Tests: Swift Testing (`import Testing`). Use XCTest only for UI tests.
- Dependencies: none. Ask a human before you add a package.
- SQLite: use the system `SQLite3` module. Open files read-only.

## Read-only rule

Spyre observes. It never acts.

- Never write, rename, move, lock, or delete any file in `~/.claude/` or `~/.codex/`.
- Open SQLite databases with `SQLITE_OPEN_READONLY`. Never run a checkpoint or a write.
- Never edit Claude Code or Codex settings or hooks files. Show the user a snippet to copy.
- Never read credential files: `~/.claude/.credentials.json`, `~/.claude/sessions/*.key`, `~/.codex/auth.json`.
- Never send signals to agent processes. `kill(pid, 0)` for a liveness check is allowed.
- Spyre may write only inside `~/Library/Application Support/Spyre/`.
- In tests, use fixture files in the repo. Never read the real `~/.claude` or `~/.codex`.
- Never read the environment variables of another process.

## Adapters

`SPEC.md` section 6 defines the adapter contract.

- Each agent type is one adapter, for example `ClaudeCodeAdapter` or `CodexAdapter`.
- An adapter is composed of source readers. One source reader reads one data source.
- New agent support means a new adapter. No agent-specific code outside its adapter.
- MVP adapters are observe-only. Do not add steer, approve, or stop code.
- Spyre never types into a terminal or sends keystrokes to another app.
- A source reader that cannot parse its data gives `unknown`. It never crashes the app.

## No network

- App code must not make network calls.
- Do not import `Network`. Do not use `URLSession` for remote URLs.
- Do not add the `com.apple.security.network.client` entitlement.
- Do not add analytics, crash reporting, or update checks.

## Tests

- Every feature needs tests. No tests means the task is not done.
- Every parser needs fixture tests. Put fixtures in `Tests/Fixtures/<agent>/<version>/`.
- Fixtures must be fake data. Never commit real session files, paths with real names, or prompts.
- Never commit screenshots or files with personal data.
- Test the bad cases: missing file, empty file, truncated last line, unknown fields, unknown status values, dead PID.
- Tests must not depend on the clock. Inject a clock.
- Put every test file's tests in a `@Suite(.timeLimit(.minutes(1)))`. A lint test checks this.
- Tests must not depend on the file system outside a temp directory.

## Git workflow

- Never push to `main`. Never force-push to `main`.
- Never create worktrees or build folders inside `~/Desktop` or `~/Documents`. iCloud syncs them, and this breaks code signing. Use `~/Developer`.
- Create a feature branch for each task: `feat/…`, `fix/…`, `docs/…`, `test/…`, `chore/…`.
- Keep PRs small. One concern per PR. Target under 400 changed lines.
- Use Conventional Commits: `type(scope): summary`.
  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`.
  - Example: `feat(claude): parse session registry files`.
- Open a PR to `main`. A human merges it.
- In the PR description, list what you tested and what you did not test.

## Swift code style

- Follow the Swift API Design Guidelines.
- Use 4 spaces for indentation. Keep lines under 120 characters.
- Use `struct` and `enum` by default. Use `class` only for reference semantics.
- Mark types `final` when you use `class`.
- Use `let` by default. Use `var` only when the value changes.
- Do not force-unwrap (`!`) or force-try (`try!`) in app code. Tests may use `#require`.
- Mark UI state `@MainActor`. Do file reading off the main actor.
- Make model types `Sendable`.
- Use `Codable` for JSON. Make all decoded fields optional unless the format guarantees them.
- Decode unknown enum values to an `.unknown(String)` case. Never crash on new values.
- Put each agent behind one adapter protocol. Claude Code and Codex are two implementations.
- Keep views small. Move logic out of views into testable types.
- Views use design tokens only. A hardcoded color or size in a view is a bug. See `DESIGN.md`.
- Use `os.Logger` for logs. Never log prompts, message content, or tokens.
- Write a doc comment for each public type. Do not comment obvious code.
- Run `swift-format` before you commit, if the repo has a config.

## File watching

- Use `DispatchSource` file system events or FSEvents. Do not poll faster than once per second.
- Read only the tail of JSONL files. Do not load a full transcript into memory.
- Handle files that change while you read them.

## Definition of done

A task is done only when all items are true:

1. The code does what the task and `SPEC.md` say.
2. New and changed behavior has tests.
3. All tests pass locally (`swift test` or `xcodebuild test`).
4. The project builds with zero warnings.
5. No new network code. No writes outside Spyre's own folder.
6. No real user data in the repo.
7. `SPEC.md` is updated if behavior or data sources changed. `DESIGN.md` is updated if tokens changed.
8. The commit messages follow Conventional Commits.
9. The PR is open against `main`, with a description of tests run and not run.

## When you are blocked

- If a guard, permission, or hook blocks you, stop and report. Never work around it.

## When you are not sure

- Mark facts you did not verify as UNKNOWN. Do not guess file formats.
- Ask a human before you change the read-only rule, the no-network rule, or the stack.
