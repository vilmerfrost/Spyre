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

Spyre is a macOS menubar app for AI coding agents.

### 3.1 Sections

Spyre has three sections.

| Section | Purpose | In MVP |
|---------|---------|--------|
| **Radar** | Watch live agent sessions. | Yes |
| **Grab** | Capture context with a global hotkey. | No. See 7.1. |
| **Lab** | Test and compare agent skills. | No. See 7.2. |

The MVP builds only Radar.
Sections 4 to 6 describe Radar.

Radar shows every live Claude Code and Codex session on this Mac.
It shows which sessions are working, waiting for the user, idle, or done.

In the MVP, Spyre is read-only.
It never starts, stops, or changes an agent session.

### 3.2 Surfaces

| Surface | Content | In MVP |
|---------|---------|--------|
| Menubar item | Spyre icon, a badge, and a short session list. | Yes |
| Main window | A section switcher: Radar, Grab, Lab. Grab and Lab show "Coming soon". | Yes |
| Dock | A vertical strip on one screen edge. One icon per live session. | Yes. The user can hide it. |

`DESIGN.md` defines the look of all surfaces.

## 4. Radar MVP features

### 4.1 Menubar item with badge

- Show a Spyre icon in the menubar.
- The badge counts sessions in the `waiting` state only.
- `idle` and `done` sessions never count in the badge. They show in the list only.
- Hide the badge when the count is 0.
- Update the badge as soon as a status changes. Do not delay it.

A `waiting` state can last less than 2 s.
For example, a user hook can approve a permission prompt automatically (verified: about 2 s).
Spyre must never assume that a `waiting` state stays.

- Attention effects start only when a session stays `waiting` for longer than the waiting grace time (default: 3 s).
- Attention effects are the pulse on the dock icon and, later, system notifications.
- The badge and the list do not use the grace time. They always show the current state.

### 4.2 Session list

Click the menubar icon to open the short list. The Radar section in the main window shows the full list.
Each row shows:

| Field | Source |
|-------|--------|
| Agent type | `Claude Code` or `Codex` |
| Project name | Last path component of the working directory |
| Worktree / branch | Git branch. Show the worktree name if the directory is a git worktree. |
| Status | See 4.4 |
| Last activity | Relative time, for example "2 min ago" |
| No-activity flag | See 4.4. Only on `working` rows. |

Sort order: `waiting`, `working`, `idle`, `unknown`, `done`.
Inside `working`, rows with the no-activity flag come first.
Inside each status, the newest last activity comes first.

Child sessions show under their parent row. See 4.6.

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
| `idle` | The agent finished its turn. The process is still running. | No |
| `done` | The process has ended. | No |
| `unknown` | Spyre cannot read the source, or the sources disagree in a way Spyre cannot resolve. | No |

Remove `done` rows from the list after 10 minutes.

**No-activity flag.**
The status `stuck` does not exist.
A `working` session with no activity for longer than a threshold (default: 10 min) gets the no-activity flag.

- The flag is a visual mark on the row, for example "No activity for 12 min". It is not a status.
- The flag does not count in the badge.
- The flag goes away on the next activity.
- Reason: "no activity" is a guess. A long build or test run is still `working`. A status must come from a source fact.

### 4.5 Status sources

**Claude Code**

1. **Session registry (main source).** Spyre reads `~/.claude/sessions/<pid>.json`. It gives liveness, `working`, `waiting`, and `idle`. The MVP needs no hook setup.
2. **Spyre hook (optional backup).** The user can add a hook snippet to their Claude Code settings by hand. The hook writes a status file into Spyre's own folder.
3. **Transcript.** Gives git branch and a fallback for last activity.
4. **Process scan.** Gives liveness for sessions without a registry file. See 4.6.

Merge rule for one session:

- When the registry file exists and parses, its status wins.
- Spyre uses the hook status only when the registry has no file for the session, or gives `unknown`.
- Reason: the registry changes faster than the hook `Notification` event (5.1 B).

Spyre never edits `~/.claude/settings.json`.
Spyre shows the hook snippet in Settings with a "Copy" button.
The user pastes it.

**Codex**

- Codex shows `working`, `idle`, and `done` in the MVP.
- Codex has no `waiting` status in the MVP. Section 5.2 explains why.
- Spyre finds live Codex sessions from the process list and the working directory (5.2 C).
- Known limit: two Codex sessions in the same folder show as one session.

### 4.6 Child sessions

A Claude Code session started from inside another Claude Code session has `CLAUDE_CODE_CHILD_SESSION` set.
It writes no registry file (verified).

Spyre finds child sessions this way:

1. The process scan lists Claude Code processes. A live Claude Code process with no registry file is a child session candidate.
2. Spyre reads the process working directory with `proc_pidinfo` (as for Codex, 5.2 C).
3. Spyre finds the newest transcript file in `~/.claude/projects/<encoded-cwd>/` whose `sessionId` is not in any registry file. This gives last activity and git branch.
4. Spyre walks the parent process chain (parent PID, then its parent PID). The first process that has a registry file is the parent session.
5. Spyre shows the child row under the parent row, with the label "child session".
6. When no parent is found, Spyre shows the child as a top-level row.

Status of a child session:

- The registry has no status for it. Without the hook, the status is `unknown` while the process lives, and `done` when it ends.
- With the Spyre hook installed, the hook status is used.

UNKNOWN:

- The exact process name of a Claude Code process on every host (CLI, desktop, VS Code).
- Whether the parent process chain always reaches the parent session. A host app or daemon may sit in between.
- Whether hooks fire in a child session.
- How to match a child process to its transcript when two child sessions share a folder. Same limit as Codex.

Spyre never reads the environment variables of another process. They can hold secrets.

### 4.7 Adapters

Section 6 defines adapters and source readers.

## 5. Data sources

Findings come from tests on one Mac with Claude Code 2.1.293 and 2.1.295 and Codex CLI 0.161.0 (October 2026).
Full probe log: `docs/probes/2026-10-09-probe-results.md`.

- **Verified** means a real file, payload, or process was observed.
- **Inferred** means it was read from the app binary only.

Spyre must treat all formats as unstable. Parse defensively. Ignore unknown fields.
All example values below are fake.

### 5.1 Claude Code

**A. Session registry (main source)**

- Path: `~/.claude/sessions/<pid>.json` (verified).
- One JSON file per Claude Code process.
- Written for CLI (`entrypoint: "cli"`), desktop (`claude-desktop`), and VS Code (`claude-vscode`) sessions (verified).
- Not written when the env var `CLAUDE_CODE_CHILD_SESSION` is set (verified). This covers a session launched from inside another Claude session. Section 4.6 explains how Spyre finds these sessions.
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
| `busy` | `working` (the no-activity flag can apply, see 4.4) |
| `waiting` | `waiting` |
| `idle` | `idle` |
| any other value | `unknown` |
| PID dead or file gone | `done` |

**B. Hook payloads (optional Spyre hook)**

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
- The registry changes faster than the notification. This is why the registry is the main source and the hook is only a backup.

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
- Use: git branch, a fallback for last activity, and child session discovery (4.6).
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

## 6. Adapter architecture

### 6.1 Terms

- **Adapter**: all support for one agent type. MVP adapters: `ClaudeCodeAdapter`, `CodexAdapter`. A new agent gets a new adapter.
- **Source reader**: reads one data source for one adapter. Examples: registry reader, transcript reader, hook reader, process scan.
- **Session record**: one session, as an adapter reports it to the app.

An adapter is composed of source readers. It merges their results into session records.

| Adapter | Source readers |
|---------|----------------|
| `ClaudeCodeAdapter` | Registry reader (5.1 A), hook reader (5.1 B), transcript reader (5.1 C), process scan (4.6) |
| `CodexAdapter` | Thread index reader (5.2 A), rollout reader (5.2 B), process scan (5.2 C) |

The process scan can be shared code. Each adapter applies its own filter to the scan result.

Agent-specific code lives only inside its adapter. The rest of the app knows only session records.

### 6.2 Capabilities

Each adapter declares its capabilities.

| Capability | Meaning | In MVP |
|------------|---------|--------|
| `observe` | Read session status. | Yes |
| `steer` | Send input to a session. | No |
| `approve` | Answer a permission prompt. | No |
| `stop` | End a session. | No |

MVP adapters declare `observe` only.

### 6.3 Session kinds

| Kind | Started by | Allowed capabilities | In MVP |
|------|------------|----------------------|--------|
| **Observed** | The user, outside Spyre | `observe` only. Always. | Yes |
| **Owned** | Spyre, through an official agent SDK or API | Any capability the adapter declares | No |

- An observed session is always read-only, even when the adapter declares more capabilities.
- Spyre never types into a terminal. Spyre never injects keystrokes into another app.
- Only owned sessions can be steered, approved, or stopped.
- Every session record carries its kind.

### 6.4 Adapter contract

This is the contract in plain language. The code protocol must follow it.

**Inputs**

- The root folders to read, for example `~/.claude`. The app injects them. Tests inject a temp folder with fixtures.
- A process list provider. The app injects it. Tests inject a fake.
- A clock. The app injects it. Tests inject a fixed clock.

**Outputs**

- A full snapshot of all sessions the adapter can see. Not a list of changes.
- For each session, a session record with:
  - a session ID that stays the same across refreshes,
  - agent type and session kind,
  - working directory, project name, git branch or worktree name,
  - status (`working`, `waiting`, `idle`, `done`, `unknown`),
  - waiting reason, when the source gives one,
  - last activity time,
  - parent session ID, for a child session,
  - the format version of each source it read.
- A list of diagnostics, for example "registry file could not be parsed". Diagnostics never contain message content or secrets.
- A signal when the adapter's sources change, so the app can refresh.

**Guarantees**

- A refresh never throws to the UI.
- When a source reader cannot read or parse its source, its sessions get `unknown`. Other source readers still give their data.
- When a whole adapter fails, its sessions show `unknown` and the other adapters still work.
- The app never crashes because of adapter data.
- The same input gives the same output.
- The adapter logs a warning for a format version it has no tests for.

**Threading**

- Refresh runs off the main actor.
- Session records and diagnostics are `Sendable` values.
- The app calls refresh for one adapter one at a time. Adapters can refresh in parallel with each other.
- A refresh that takes longer than 2 s counts as failed. The app keeps the last snapshot and logs a warning.

**An adapter must never**

- write, rename, move, lock, or delete a file in the agent's folders,
- read credential files or `.key` files,
- read message content beyond what status needs,
- read the environment variables of another process,
- send a signal to a process, except `kill(pid, 0)` for a liveness check,
- make a network call,
- touch UI state,
- in the MVP: steer, approve, or stop a session.

## 7. Future sections

These sections are not in the MVP. Each needs its own spec before work starts.

### 7.1 Grab

Grab captures context with a global hotkey.
The user presses the hotkey. Spyre captures context from the screen, for example the front window or the selected text.
The user can then hand that context to an agent.
Grab needs two macOS permissions: Screen Recording and Accessibility.
Captured data stays on this Mac.
UNKNOWN: what Grab captures exactly, and how it hands context to an agent.

### 7.2 Lab

Lab tests and compares agent skills.
The user picks a task and two or more skills or agents. Spyre runs them and shows the results side by side.
Lab must start and run agents.
This conflicts with the MVP observe-only rule.
Lab will use owned sessions only (6.3), started through an official agent SDK or API.
A human must approve this rule change before Lab work starts.

## 8. Distribution

- No App Sandbox. Spyre must read `~/.claude` and `~/.codex`, and inspect other processes.
- Sign with a Developer ID certificate. Notarize every release.
- Distribute as a notarized `.dmg` on GitHub Releases and as a Homebrew cask.
- No Mac App Store build.

## 9. Non-goals for MVP

- No Grab and no Lab sections. They show "Coming soon".
- No owned sessions.
- No routing of tasks between agents.
- No starting, stopping, or sending input to agents.
- No jump to the exact terminal tab.
- No Codex `waiting` status.
- No system notifications.
- No network calls of any kind.
- No telemetry or analytics.
- No cloud sync or accounts.
- No editing of any Claude Code or Codex file, including settings and hooks.
- No reading of message content beyond what status needs.
- No support for agents other than Claude Code and Codex.

## 10. Privacy

- All data stays on this Mac.
- Spyre never uploads anything.
- Spyre has no network code and no network entitlement.
- Spyre reads the minimum fields it needs. It does not store transcript content.
- Spyre never reads credential files: `~/.claude/.credentials.json`, `~/.claude/sessions/*.key`, `~/.codex/auth.json`.
- Spyre never reads the environment variables of another process.

## 11. Open questions

1. Is the no-activity threshold of 10 minutes right? Should the user set it?
2. How stable are these formats across versions? We need fixture files per version in tests.
3. How does Spyre show a Codex desktop thread more reliably than "ChatGPT runs and recent update"?
4. Which `waitingFor` value does Claude Code write for a question (`AskUserQuestion`) or an MCP elicitation?
5. When should the `elicitation_dialog` notification fire? It was not observed.
6. Is a waiting grace time of 3 s right for attention effects?
7. Child sessions: see the UNKNOWN list in 4.6.
