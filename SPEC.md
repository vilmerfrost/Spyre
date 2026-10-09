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
It shows which sessions are working, waiting for the user, stuck, or done.

Spyre is read-only.
It never starts, stops, or changes an agent session.

## 4. MVP features

### 4.1 Menubar icon with badge

- Show a Spyre icon in the menubar.
- Show a badge with the number of sessions in the `waiting` state.
- Hide the badge when the number is 0.

### 4.2 Session list

Click the icon to open the list. Each row shows:

| Field | Source |
|-------|--------|
| Agent type | `Claude Code` or `Codex` |
| Project name | Last path component of the working directory |
| Worktree / branch | Git branch. Show the worktree name if the directory is a git worktree. |
| Status | `working`, `waiting`, `stuck`, `done` (see 4.4) |
| Last activity | Relative time, for example "2 min ago" |

Sort order: `waiting` first, then `stuck`, then `working`, then `done`.

### 4.3 Focus a session

- Click a row to bring the session's window to the front.
- Use the session process ID (PID). Walk up the parent processes to find the host app (terminal, editor, or desktop app).
- Activate that app.
- If Spyre cannot find the window, show the working directory and a "Reveal in Finder" action.

### 4.4 Status model

Spyre shows four statuses:

| Spyre status | Meaning |
|--------------|---------|
| `working` | The agent is running a turn. |
| `waiting` | The agent is blocked on the user: a permission prompt or a question. |
| `stuck` | The status says `working`, but there was no activity for longer than a threshold (default: 10 min). |
| `done` | The agent finished its turn and is idle, or the process has ended. |

Open question 8 asks if a finished turn should also count in the badge.

Spyre gets status from two sources:

1. **Session files** (always on). See section 5.
2. **Spyre status hook** (optional, Claude Code only). The user adds a hook to their Claude Code settings. The hook writes a small status file into Spyre's own folder. Spyre never edits Claude Code settings. Spyre shows the user a snippet to copy.

When both sources exist, the newer one wins.

## 5. Data sources

All findings below come from an investigation on one Mac (Claude Code 2.1.293, Codex CLI 0.161.0, October 2026).
"Verified" means a real file was read.
"Inferred" means it was read from the app binary or a single sample, not from official docs.
Spyre must treat all formats as unstable. Parse defensively. Ignore unknown fields.

### 5.1 Claude Code

**A. Live session registry (primary source)**

- Path: `~/.claude/sessions/<pid>.json` (verified).
- One JSON file per Claude Code process.
- Next to it: `<pid>.<hash>.key`. Spyre must never read `.key` files.
- Files stay after the process exits. Spyre must check that the PID is alive (verified: 4 of 9 files had dead PIDs).

Fields (verified unless marked):

| Field | Example | Use |
|-------|---------|-----|
| `pid` | `37211` | Liveness check, window focus |
| `sessionId` | `01bfc5a6-…` (UUID) | Key to the transcript file |
| `cwd` | `/Users/you/Projects/Spyre` | Project name |
| `startedAt` | `1791555389978` (ms epoch) | PID reuse check |
| `procStart` | `Fri Oct  9 14:16:29 2026` | PID reuse check |
| `kind` | `interactive` | Filter |
| `entrypoint` | `claude-desktop`, `claude-vscode` | Host app hint |
| `name` | `Fix login bug` | Session title |
| `status` | `busy`, `idle` | Status |
| `waitingFor` | not seen in a file | Reason for `waiting` (inferred) |
| `updatedAt`, `statusUpdatedAt` | ms epoch | Last activity |

Status values (inferred from binary): the code maps `running → busy`, `requires_action → waiting`, `idle → idle`.
When `status` is `waiting`, `waitingFor` is `"permission prompt"` or `"input needed"`.
Only `busy` and `idle` were seen in real files.

Mapping to Spyre status:

| `status` | Spyre status |
|----------|--------------|
| `busy` | `working` (or `stuck` after the threshold) |
| `waiting` | `waiting` |
| `idle` | `done` |
| missing, or PID dead | `done` |

**B. Transcript (secondary source)**

- Path: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` (verified).
- `<encoded-cwd>` is the `cwd` with `/` replaced by `-`. Example: `-Users-you-Projects-Spyre`.
- Format: JSON Lines. One record per line. The file only grows.
- Record `type` values seen: `user`, `assistant`, `system`, `attachment`, `custom-title`, `agent-name`, `last-prompt`, `queue-operation`, `file-history-snapshot`.
- Useful fields on `user` / `assistant` / `system` records: `timestamp` (ISO 8601), `cwd`, `gitBranch`, `sessionId`.
- Use: git branch and a fallback for last activity.
- Read only the tail of the file. Never parse message content.

**C. Hooks (for the optional Spyre hook)**

Hook events found in Claude Code 2.1.293 (inferred from binary):
`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Notification`, `Stop`, `StopFailure`, `PermissionRequest`, `Elicitation`, `SubagentStop`, and others.

| Signal | Hook event |
|--------|-----------|
| Working | `UserPromptSubmit` |
| Waiting for input | `Notification` with `notification_type` = `permission_prompt`, `idle_prompt`, or `elicitation_dialog`. Also `PermissionRequest`, `Elicitation`. |
| Finished turn | `Stop` |
| Failed turn | `StopFailure` |
| Session ended | `SessionEnd` |

The Spyre hook writes to `~/Library/Application Support/Spyre/status/<session_id>.json`.
It never writes inside `~/.claude/`.

### 5.2 Codex

Codex has no per-process registry like Claude Code (verified: none found in `~/.codex/`).

**A. Thread index (primary source for metadata)**

- Path: `~/.codex/state_5.sqlite`, table `threads` (verified).
- The `5` is a schema version. Spyre must find the file by pattern `state_*.sqlite` and pick the highest number.
- Useful columns: `id`, `rollout_path`, `cwd`, `title`, `git_branch`, `git_sha`, `updated_at_ms`, `archived`, `originator`, `source`.
- Open read-only (`SQLITE_OPEN_READONLY`). Codex uses WAL mode on other databases. Never write, never checkpoint.

**B. Rollout transcript (primary source for status)**

- Path: `~/.codex/sessions/YYYY/MM/DD/rollout-<local-timestamp>-<thread-id>.jsonl` (verified).
- Format: JSON Lines. Each record has `timestamp`, `ordinal`, `type`, `payload`.
- First record: `type = session_meta`. Payload has `id`, `cwd`, `originator` (for example `Codex Desktop`), `cli_version`, `source`.
- Status events: `type = event_msg` with `payload.type`:

| `payload.type` | Spyre status |
|----------------|--------------|
| `task_started` | `working` |
| `task_complete` | `done` |
| `turn_aborted` | `done` |

- Approval events (`exec_approval_request`, `apply_patch_approval_request`, `request_user_input`) exist in the binary. They were not seen in rollout files.

**C. Liveness**

- Path: `~/.codex/thread-writer-locks/<thread-id>.lock` (verified).
- A live Codex process holds the lock file open (verified with `lsof`: the `codex` app-server process).
- Spyre can treat a held lock as "session is live" (inferred).

**D. Codex hooks**

- `~/.codex/hooks.json` exists and supports `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `PermissionRequest`, and others (verified from the user's file).
- A Codex version of the Spyre hook is possible. It is not in the MVP.

## 6. Non-goals for MVP

- No routing of tasks between agents.
- No starting, stopping, or sending input to agents.
- No network calls of any kind.
- No telemetry or analytics.
- No cloud sync or accounts.
- No editing of any Claude Code or Codex file, including settings and hooks.
- No reading of message content beyond what status needs.
- No support for agents other than Claude Code and Codex.

## 7. Privacy

- All data stays on this Mac.
- Spyre never uploads anything.
- Spyre has no network code and no network entitlement.
- Spyre reads the minimum fields it needs. It does not store transcript content.
- Spyre never reads credential files: `~/.claude/.credentials.json`, `~/.claude/sessions/*.key`, `~/.codex/auth.json`.

## 8. Open questions

1. Does Claude Code ever write `status: "waiting"` to the registry for terminal (CLI) sessions? Only desktop and VS Code sessions were observed.
2. Does Codex write approval-request events to the rollout file? If not, Spyre cannot show Codex `waiting` for approvals without a hook.
3. How do we map a PID to one specific terminal tab (not only the app)? Terminal.app, iTerm2, Ghostty, Warp, and VS Code each need a different method.
4. How do we detect a dead Codex session when the app-server process serves many threads?
5. Is the `stuck` threshold of 10 minutes right? Should the user set it?
6. Does the App Sandbox allow read access to `~/.claude` and `~/.codex`? If not, ship outside the Mac App Store, unsandboxed, notarized.
7. How stable are these formats across versions? We need fixture files per version in tests.
8. Should a finished turn (`done`) also count in the badge until the user opens the list?
