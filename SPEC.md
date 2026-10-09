# Spyre Specification

Status: draft for MVP.

## 1. Problem

Developers run many AI coding agent sessions at the same time.
The sessions run in different terminals, editors, and desktop apps.
A session can stop and wait for the user. The user often does not see this.
Time is lost. Agents sit idle.

## 2. Target user

- A developer on macOS.
- The developer runs two or more Claude Code or Codex sessions at the same time.
- The developer wants one place to see which session needs attention.

## 3. What Spyre is

Spyre is a macOS menubar app.
It shows every live Claude Code and Codex session on this Mac.
It shows which sessions are working, waiting for the user, stuck, idle, or done.

Spyre is read-only.
It never starts, stops, or changes an agent session.

## 4. MVP features

### 4.1 Menubar icon with badge

- Show a Spyre icon in the menubar.
- The badge counts sessions in the `waiting` state only.
- `idle` and `done` sessions never count in the badge. They show in the list only.
- Hide the badge when the count is 0.

### 4.2 Session list

Click the icon to open the list. Each row shows:

| Field | Source |
|-------|--------|
| Agent type | `Claude Code` or `Codex` |
| Project name | Last path component of the working directory |
| Worktree / branch | Git branch. Show the worktree name if the directory is a git worktree. |
| Status | See 4.4 |
| Last activity | Relative time, for example "2 min ago" |

Sort order: `waiting`, `stuck`, `working`, `idle`, `unknown`, `done`.

### 4.3 Open a session's project

- Click a row to open the session's working directory in the user's terminal app.
- The user picks the terminal app in Settings. Default: Terminal.app.
- Spyre opens a new window at that folder. It does not find the existing tab.
- Jump to the exact terminal tab is not in the MVP.

### 4.4 Status model

| Spyre status | Meaning | Badge |
|--------------|---------|-------|
| `working` | The agent is running a turn. | No |
| `waiting` | The agent is blocked on the user: a permission prompt or a question. | Yes |
| `stuck` | The status is `working`, but there was no activity for longer than a threshold (default: 10 min). | No |
| `idle` | The agent finished its turn. The process is still running. | No |
| `done` | The process has ended. | No |
| `unknown` | Spyre cannot read the source format. | No |

Remove `done` rows from the list after 10 minutes.

### 4.5 Status sources

**Claude Code**

1. **Spyre hook (primary for `waiting`).** The user adds a hook snippet to their Claude Code settings by hand. The hook writes a status file into Spyre's own folder.
2. **Session registry (backup).** Spyre reads `~/.claude/sessions/<pid>.json`. Spyre uses it for liveness, `working`, and `idle`. It also uses it for `waiting` when the hook is not installed.

When both sources have a value for the same session, the newer one wins.

Spyre never edits `~/.claude/settings.json`.
Spyre shows the hook snippet in Settings with a "Copy" button.
The user pastes it.

**Codex**

- Codex shows `working`, `idle`, and `done` in the MVP.
- Codex has no `waiting` status in the MVP. Section 5.2 explains why.

### 4.6 Adapters

- Each data source is a separate adapter: Claude registry, Claude hook, Claude transcript, Codex threads database, Codex rollout, process scan.
- Each adapter returns status values. It never throws to the UI.
- When an adapter cannot parse its source, the session shows `unknown`. The app never crashes.
- Each adapter reports the format version it saw. Spyre logs a warning for a version it has no tests for.

## 5. Data sources

Findings come from tests on one Mac with Claude Code 2.1.293 and 2.1.295 and Codex CLI 0.161.0 (October 2026).

- **Verified** means a real file, payload, or process was observed.
- **Inferred** means it was read from the app binary only.

Spyre must treat all formats as unstable. Parse defensively. Ignore unknown fields.
All example values below are fake.

### 5.1 Claude Code

**A. Session registry**

- Path: `~/.claude/sessions/<pid>.json` (verified).
- One JSON file per Claude Code process.
- Written for CLI (`entrypoint: "cli"`), desktop (`claude-desktop`), and VS Code (`claude-vscode`) sessions (verified).
- Not written when the env var `CLAUDE_CODE_CHILD_SESSION` is set (verified). This covers a session launched from inside another Claude session. Spyre does not see these sessions.
- Next to it: `<pid>.<hash>.key`. Spyre must never read `.key` files.
- A clean exit (`/exit`) deletes both files (verified).
- A killed process leaves the files behind (verified: 4 of 9 files had dead PIDs). Spyre must check that the PID is alive. Compare `procStart` to the real process start time to detect PID reuse.

Fields:

| Field | Example | Use |
|-------|---------|-----|
| `pid` | `12345` | Liveness check |
| `sessionId` | UUID | Join key with hook and transcript |
| `cwd` | `/Users/you/Projects/app` | Project name |
| `startedAt` | ms epoch | PID reuse check |
| `procStart` | `Fri Oct  9 14:16:29 2026` | PID reuse check |
| `kind` | `interactive` | Filter |
| `entrypoint` | `cli`, `claude-desktop`, `claude-vscode` | Host app hint |
| `name` | `Fix login bug` | Session title |
| `status` | `busy`, `waiting`, `idle` | Status |
| `waitingFor` | `permission prompt` | Reason for `waiting`. Absent in other states. |
| `updatedAt`, `statusUpdatedAt` | ms epoch | Last activity |

Verified in a CLI test:

- The file changed to `status: "waiting"`, `waitingFor: "permission prompt"` as soon as the permission prompt opened.
- It stayed `waiting` for the full 30 s that the prompt was open.
- It changed to `idle` (and removed `waitingFor`) when the user denied the prompt.
- `waitingFor: "input needed"` exists in the binary. It was not observed (inferred).

Mapping:

| Registry `status` | Spyre status |
|-------------------|--------------|
| `busy` | `working` (or `stuck` after the threshold) |
| `waiting` | `waiting` |
| `idle` | `idle` |
| any other value | `unknown` |
| PID dead or file gone | `done` |

**B. Hook payloads (for the Spyre hook)**

Real `Notification` payloads (verified, values faked):

```json
{
  "session_id": "00000000-0000-0000-0000-000000000000",
  "transcript_path": "/Users/you/.claude/projects/-Users-you-Projects-app/00000000-0000-0000-0000-000000000000.jsonl",
  "cwd": "/Users/you/Projects/app",
  "prompt_id": "00000000-0000-0000-0000-000000000000",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission",
  "notification_type": "permission_prompt"
}
```

The idle payload has the same fields, with `"message": "Claude is waiting for your input"` and `"notification_type": "idle_prompt"`.
Some payloads also have `scratchpad_dir`. Treat all fields except `session_id`, `hook_event_name`, and `notification_type` as optional.

Timing (verified):

- The `permission_prompt` notification is delayed. It did not fire when the prompt was closed after 4 s. It fired when the prompt stayed open for 30 s.
- The `idle_prompt` notification fired in 1 of 2 runs within about 2 min of idle. Do not use it as the "finished" signal.
- The registry changes faster than the notification. This is why the registry stays as the backup.

Hook events for the Spyre hook:

| Event | Spyre status |
|-------|--------------|
| `UserPromptSubmit` | `working` |
| `Notification` with `notification_type: "permission_prompt"` | `waiting` |
| `Notification` with `notification_type: "elicitation_dialog"` | `waiting` (inferred; not observed) |
| `Stop` | `idle` |
| `StopFailure` | `idle` |
| `SessionEnd` | `done` |

The hook writes `~/Library/Application Support/Spyre/status/<session_id>.json`.
The file holds `session_id`, `cwd`, `event`, `notification_type`, and a timestamp. Nothing else.
The hook never writes inside `~/.claude/`.
A `PermissionRequest` hook from another tool can answer a prompt in about 2 s (verified). The `Stop` or `UserPromptSubmit` event then moves the status on.

**C. Transcript (secondary)**

- Path: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` (verified).
- `<encoded-cwd>` is the `cwd` with each `/` replaced by `-`. Example: `-Users-you-Projects-app`.
- Format: JSON Lines. The file only grows.
- Useful fields on `user`, `assistant`, and `system` records: `timestamp`, `cwd`, `gitBranch`, `sessionId`.
- Use: git branch and a fallback for last activity.
- Read only the tail of the file. Never parse message content.

### 5.2 Codex

**A. Thread index**

- Path: `~/.codex/state_5.sqlite`, table `threads` (verified).
- The `5` is a schema version. Find the file by pattern `state_*.sqlite`. Pick the highest number.
- Useful columns: `id`, `rollout_path`, `cwd`, `title`, `git_branch`, `updated_at_ms`, `archived`.
- Open read-only. Codex keeps this file open in WAL mode while it runs (verified). Never write, never checkpoint.

**B. Rollout**

- Path: `~/.codex/sessions/YYYY/MM/DD/rollout-<local-timestamp>-<thread-id>.jsonl` (verified).
- Each record has `timestamp`, `ordinal`, `type`, `payload`.
- Status events: `type: "event_msg"` with `payload.type`:

| `payload.type` | Spyre status (if the session is live) |
|----------------|---------------------------------------|
| `task_started` | `working` |
| `task_complete` | `idle` |
| `turn_aborted` | `idle` |

- The rollout has no exit record. A killed session and a cleanly closed session end with the same `task_complete` record (verified).
- Approval events (`exec_approval_request`, `apply_patch_approval_request`, `request_user_input`) exist in the binary. They were not seen in rollout files. This is why Codex has no `waiting` status in the MVP.

**C. Liveness**

Lock files do not show liveness (verified):

- Path: `~/.codex/thread-writer-locks/<thread-id>.lock`.
- The terminal UI process (TUI) does not hold its lock. A shared `app-server-daemon` process holds it.
- The first TUI starts the daemon. The daemon detaches (parent PID 1). It serves later TUIs too.
- After one TUI was killed and the other exited cleanly, the daemon still held both locks.
- The ChatGPT desktop app has its own app-server. It holds the locks for desktop threads.

Use the process table instead:

1. List processes named `codex` that are not `app-server` or `app-server-daemon` processes.
2. Read each process's working directory with `proc_pidinfo` (`PROC_PIDVNODEPATHINFO`). The TUI's working directory is the project folder (verified).
3. Match each TUI to the thread with the same `cwd` and the newest `updated_at_ms`.
4. A thread with a matching live TUI is live. A thread without one is `done`.

Limits:

- Two TUIs in the same folder cannot be told apart. Spyre shows them as one session.
- ChatGPT desktop threads have no TUI. In the MVP, Spyre shows a desktop thread as live only while the ChatGPT app runs and the thread was updated in the last 30 min.

**D. Codex hooks**

`~/.codex/hooks.json` supports `PermissionRequest`, `Stop`, and other events (verified from a user file).
A Codex Spyre hook could add `waiting`. It is not in the MVP.

## 6. Distribution

- No App Sandbox. Spyre must read `~/.claude` and `~/.codex`, and inspect other processes.
- Sign with a Developer ID certificate. Notarize every release.
- Distribute as a notarized `.dmg` on GitHub Releases and as a Homebrew cask.
- No Mac App Store build.

## 7. Non-goals for MVP

- No routing of tasks between agents.
- No starting, stopping, or sending input to agents.
- No jump to the exact terminal tab.
- No Codex `waiting` status.
- No network calls of any kind.
- No telemetry or analytics.
- No cloud sync or accounts.
- No editing of any Claude Code or Codex file, including settings and hooks.
- No reading of message content beyond what status needs.
- No support for agents other than Claude Code and Codex.

## 8. Privacy

- All data stays on this Mac.
- Spyre never uploads anything.
- Spyre has no network code and no network entitlement.
- Spyre reads the minimum fields it needs. It does not store transcript content.
- Spyre never reads credential files: `~/.claude/.credentials.json`, `~/.claude/sessions/*.key`, `~/.codex/auth.json`.

## 9. Open questions

1. Is the `stuck` threshold of 10 minutes right? Should the user set it?
2. How stable are these formats across versions? We need fixture files per version in tests.
3. How does Spyre show a Codex desktop thread more reliably than "ChatGPT runs and recent update"?
4. Which `waitingFor` value does Claude Code write for a question (`AskUserQuestion`) or an MCP elicitation?
5. When should the `elicitation_dialog` notification fire? It was not observed.
