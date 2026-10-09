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
| Menubar item | Spyre icon and a badge. Its window shows the count line, the top rows (Needs you, then Working, at most `size.menu.maxRows`), "Open Spyre", and "Show welcome screen". | Yes |
| Main window | A pill section switcher (Radar, Grab, Lab) and the shortcut hint. Radar shows the count line and the session list (4.2). Grab and Lab show "Coming soon". | Yes |
| Welcome window | The first-run screen (4.8). | Yes |
| macOS Dock icon | Not the dock strip above. Off by default. `showDockIcon` (4.4) turns it on. A click opens the main window. | Yes |
| Dock | A vertical strip on one screen edge. One icon per live session. | No. Planned for v0.2. Default: hidden. |

`DESIGN.md` defines the look of all surfaces. All windows follow the macOS appearance (Fog Light or Fog Dark).

**Reach Spyre without the menubar icon.** The menubar can hide the icon (the notch, a full menubar).
These paths open the main window and bring it to the front:

- Open the app again while it runs: Finder, Raycast, `open`, or the Dock icon.
  Spyre handles the reopen event (`applicationShouldHandleReopen`).
  While the first-run screen is open, reopen brings that screen to the front instead.
- The global shortcut `hotkey` (4.4). Default: Control-Option-S (⌃⌥S).
- "Open Spyre" in the menubar window.

The main window and the welcome window are AppKit windows (`NSWindow` with a SwiftUI view), not SwiftUI scenes.
AppKit code (reopen, the shortcut) cannot open a SwiftUI `Window` scene reliably in a menubar-only app.

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

- Attention effects start only when a session stays `waiting` for longer than the alert delay (3 s).
- Attention effects are the pulse on the dock icon (v0.2) and system notifications (later). The MVP has no attention effects. The alert delay is defined now so that v0.2 uses the same value.
- The badge and the list do not use the alert delay. They always show the current state.

### 4.2 Session list

Click the menubar icon to open the short list. The Radar section in the main window shows the full list.

**Count line.** Above the list: "N needs you", "N working", "N idle", in big numbers with tabular digits.
"Needs you" counts `waiting` sessions (the badge number). "Working" counts `working` and `starting`.
All three always show, so the line does not shift. Only a non-zero "needs you" uses the waiting color.

Each row shows:

| Field | Source |
|-------|--------|
| Title | The session title: Claude Code registry `name` (5.1 A), Codex `threads.title` (5.2 A). When it is missing or empty: the project name. When the folder is not known yet: the agent type. |
| Agent type | `Claude Code` or `Codex` |
| Project name | Last path component of the working directory. A session in the home folder shows `~`. |
| Worktree / branch | Git branch. Show the worktree name if the directory is a git worktree. A detached `HEAD` shows no branch. |
| Status | See 4.4 |
| Last activity | Relative time, for example "2 min ago" |
| No-activity flag | See 4.4. Only on `working` rows. |
| Waiting reason | Only on `waiting` rows, for example "Permission prompt". "Needs input" when the source gives none. |

Line 1 is the title. Line 2 is project · branch · agent, then tags (`exec`, `experimental`, `stale`).
Line 2 leaves out the project when the title is the project name. The right side shows the waiting reason,
the no-activity flag, or a status the group header does not say, then the last activity ("20 s", "4 min").
A working row shows a slow spinner.

Group the rows by status. Show the groups in this order, each with a header:

1. Needs you (the `waiting` status)
2. Working
3. Idle
4. Unknown (shown only when it has rows)
5. Done

- Inside `Working`, rows with the no-activity flag come first.
- Inside each group, the newest last activity comes first.
- Hide a group header when the group is empty.
- A group header shows the number of top-level rows in the group.
- Idle and Done are folded by default. Their header is a disclosure row with the count. A click unfolds the group.
  Spyre remembers unfolded groups in memory for the app run only. Reason: these rows need no action.
- Freeze the row order while the pointer is over the list. Rows must not move under the pointer. Status text and badges still update. Apply the new order when the pointer leaves the list.
- Reason: rows that jump under the pointer cause wrong clicks. Another session monitor removed status sorting for this reason (`research/competitors.md`).

Child sessions show under their parent row. See 4.6.

- A child row sits directly under its parent row, indented by `space.lg`. It shows in the parent's group, even when its own status is different. Reason: the child belongs to the parent's session.
- Children under one parent: the newest last activity comes first.
- A child whose parent is not in the list is its own top-level row, in its own status group.
- The badge still counts every `waiting` session, also a nested child.

### 4.3 Open a session's project

- Hover a row to show "Open folder". The row's context menu has "Open Folder in Finder" too.
  Both open the session's working directory in Finder (`NSWorkspace`). This only shows the folder. It changes nothing.
- Later, not in the MVP: open the folder in the user's terminal app, picked in Settings (default: Terminal.app),
  in a new window. Jump to the exact terminal tab is not planned.

### 4.4 Status model

| Spyre status | Meaning | Badge |
|--------------|---------|-------|
| `working` | The agent is running a turn. | No |
| `waiting` | The agent is blocked on the user: a permission prompt or a question. | Yes |
| `idle` | The agent finished its turn. The process is still running. | No |
| `done` | The process has ended. | No |
| `unknown` | Spyre cannot read the source, or the sources disagree in a way Spyre cannot resolve. | No |

Remove `done` rows from the list after `doneRowTimeout` (10 min).
Adapters keep reporting `done`. The app hides the rows, so the timeout is set in one place.

**No-activity flag.**
The status `stuck` does not exist.
A `working` session with no activity for longer than the no-activity threshold (10 min) gets the no-activity flag.

- The flag is a visual mark on the row, for example "No activity for 12 min". It is not a status.
- The flag does not count in the badge.
- The flag goes away on the next activity.
- Reason: "no activity" is a guess. A long build or test run is still `working`. A status must come from a source fact.

**Stale mark.**
When an adapter refresh times out (6.4), its sessions keep their last state. Each of these rows gets a "stale" mark until the next successful refresh.
The stale mark is not a status. It does not change the badge count.

**Config values.**
Spyre stores these values in its config, not in code:

| Key | Value | Used by |
|-----|-------|---------|
| `alertDelay` | 3 s | Attention effects (4.1) |
| `noActivityThreshold` | 10 min | No-activity flag (4.4) |
| `adapterRefreshTimeout` | 2 s | Stale mark (4.4, 6.4) |
| `doneRowTimeout` | 10 min | Hiding `done` rows (4.4) |
| `welcomeSeen` | `false` | First-run screen (4.8) |

The MVP has no settings UI for these values.

**Config file.**
Spyre reads the values from `~/Library/Application Support/Spyre/config.json`.

```json
{
  "adapterRefreshTimeout" : 2,
  "alertDelay" : 3,
  "doneRowTimeout" : 600,
  "hotkey" : "ctrl+opt+s",
  "noActivityThreshold" : 600,
  "showDockIcon" : false,
  "welcomeSeen" : false
}
```

- The file is one JSON object. Every value is a number of seconds, except `welcomeSeen` and `showDockIcon`
  (`true` or `false`) and `hotkey` (a string). Every key is optional.
- On launch, Spyre creates the file with the defaults if it does not exist.
- Spyre reloads the file when it changes. This includes an editor that saves by replacing the file.
- Spyre never crashes on a bad file. Each problem gives a warning, and the menubar window shows the first warning.
  Spyre also logs each warning with `os.Logger` (category `config`). A log names the key and the problem only.

| Problem | Result |
|---------|--------|
| Not valid JSON, or not an object | All defaults |
| Unknown key | Ignored |
| Wrong type (string, bool, null, …) | The default for that key |
| Value out of range | Clamped to the range |

| Key | Range (s) |
|-----|-----------|
| `alertDelay` | 0 – 300 |
| `noActivityThreshold` | 60 – 86400 |
| `adapterRefreshTimeout` | 0.5 – 60 |
| `doneRowTimeout` | 0 – 86400 |

| Key | Default | Meaning |
|-----|---------|---------|
| `welcomeSeen` | `false` | The first-run screen was accepted (4.8). |
| `showDockIcon` | `false` | `true` shows Spyre in the Dock (activation policy `.regular`). `false`: menubar only (`.accessory`). Applied at launch and on each reload. |
| `hotkey` | `"ctrl+opt+s"` | The global shortcut that opens the main window. |

`hotkey` grammar: modifiers and one key, joined by `+`, for example `"cmd+shift+k"`. Case does not matter.
Modifiers: `ctrl`, `opt`, `shift`, `cmd`, each at most once. At least one of `ctrl`, `opt`, `cmd`.
Key: one letter `a`–`z` or one digit `0`–`9`, by its US key position.
A value that does not follow the grammar gives the default and a warning.

Spyre registers the shortcut with Carbon `RegisterEventHotKey`. It needs no Accessibility permission.
Spyre registers it again when the value changes. When macOS refuses the shortcut, Spyre logs a warning
(category `config`), shows it as a config warning, and keeps running.
Limit: macOS does not report a shortcut that another app also registered. Both apps then get it, or only one.

Spyre writes to the file in one case only: "Start watching" on the first-run screen (4.8).
It reads the file, sets `welcomeSeen` to `true`, and keeps every other key, unknown keys too.
The write is atomic. Spyre does not replace a file that is not a JSON object.

### 4.5 Status sources

**Claude Code**

The sources are layered.

1. **Session registry (default).** Spyre reads `~/.claude/sessions/<pid>.json`. It gives liveness, `working`, `waiting`, and `idle`. No setup is needed.
2. **`PermissionRequest` hook (optional).** It gives an instant `waiting` when a permission dialog opens. The user adds it from a snippet that Spyre shows. See 5.1 B.
3. **Transcript.** Gives git branch and a fallback for last activity.
4. **Process scan.** Gives liveness for sessions without a registry file. See 4.6.

**Registry gaps.**
The registry file is not always complete:

- A new file has no `status` for about 500 ms (`research/competitors.md`).
- Claude Code does not write the file atomically. A read can see a partial file.

The registry reader must tolerate these gaps:

- A bad read is a read that fails to parse, or has no `status`.
- On a bad read, keep the last known state for that session. Retry on the next file event, or after 250 ms, whichever comes first.
- A new session with no good read yet does not show a status. Show the row with the label "Starting…". If there is still no good read after `adapterRefreshTimeout`, show `unknown`.
- Never show a state that no source reported.
- A file that parses but has no `status` still gives `cwd` and `sessionId` for the "Starting…" row. Before the first parse, the row ID is `claude-pid-<pid>`. After it, the row ID is the `sessionId`.
- A dead PID or a deleted file gives `done`. A dead file Spyre sees for the first time counts as done since its `updatedAt`, so old leftover files never show.

**Merge rule.**
When both sources have a state for the same session, the hook wins.
Two limits keep the hook from showing a false state:

- A hook state is valid only until the registry writes a newer `statusUpdatedAt`. Example: the user approves the prompt, and the registry changes to `busy`. The hook `waiting` is then cleared.
- A dead process or a deleted registry file always gives `done`. A hook state never keeps an ended session alive.

Spyre never edits `~/.claude/settings.json`.
Spyre shows the hook snippet in Settings with a "Copy" button.
The user pastes it.

**Codex**

- Codex shows `starting`, `working`, `idle`, `done`, and `unknown` in the MVP.
- Codex has no `waiting` status in the MVP. Section 5.2 explains why. A `codex exec` session is never `waiting`.
- Spyre finds live Codex sessions from the process list and the working directory (5.2 C).
- A live Codex session with no thread row yet shows "Starting…". If there is still no thread row after `adapterRefreshTimeout`, it shows `unknown`.
- A `codex exec` session shows with the label "exec" (5.2 C).
- Known limit: two Codex sessions in the same folder show as one session (5.2 C).
- ChatGPT desktop threads are out of scope. Spyre never shows them (5.2 C).

### 4.6 Child sessions

**EXPERIMENTAL.** The first implementation (`ClaudeCodeAdapter`) has not been verified against a real child session yet.

A Claude Code session started from inside another Claude Code session has `CLAUDE_CODE_CHILD_SESSION` set.
It writes no registry file (verified).

Spyre finds child sessions this way:

1. The process scan lists Claude Code processes. A live Claude Code process with no registry file is a child session candidate.
   A process that has or had a registry file is never a child (verified: a new session runs before it writes the file, and `/exit` deletes the file before the process ends).
2. Spyre reads the process working directory with `proc_pidinfo` (as for Codex, 5.2 C).
3. Spyre finds the newest transcript file in `~/.claude/projects/<encoded-cwd>/` whose `sessionId` is not in any registry file. This gives last activity and git branch.
4. Spyre walks the parent process chain (parent PID, then its parent PID). The first process that has a registry file is the parent session.
5. Spyre shows the child row under the parent row, with a corner arrow and the tag "experimental". The record keeps the label "child session"; the row leaves it out because the arrow says it.
6. When no parent is found, Spyre shows the child as its own top-level row, with the tags "child, no parent" and "experimental".
7. A candidate whose working directory is readable but has no unclaimed transcript is not shown. Desktop-app Claude processes with no registry file and no transcript were observed. They are not sessions.

The record has `isChildSession = true`. Its ID is `claude-child-<pid>`.

Status of a child session:

- The registry has no status for it.
- When the `PermissionRequest` hook is installed and fires for the child, the hook gives `waiting`.
- Otherwise the transcript tail gives the status: a record newer than the last turn end gives `working`, a turn end gives `idle`. The first code PR for child sessions must verify this method.
  - Turn end: an `assistant` record with `message.stop_reason: "end_turn"`, or a `system` record with `subtype` `turn_duration` or `stop_hook_summary`. Spyre reads `stop_reason` only, never message content.
  - Newer activity: a `user` record, or an `assistant` record with any other `stop_reason`. Other record types are ignored.
  - Known limit: a child waiting on a permission prompt shows `working` without the hook.
- The process ending gives `done`.
- Spyre shows `unknown` only when the child's data cannot be read.

Known limit: when two child sessions share a folder, Spyre cannot always match each process to its transcript. Same limit as Codex.

See section 11 for the open UNKNOWNs about child sessions.

Spyre never reads the environment variables of another process. They can hold secrets.

### 4.7 Adapters

Section 6 defines adapters and source readers.

### 4.8 First-run screen

- On launch, Spyre shows a welcome window when `welcomeSeen` (4.4) is `false` or missing.
- Only the first config load decides. A later reload never opens the window.
- The window tells the user what Spyre does, what it reads (5.1, 5.2), the privacy rules (10), and the read-only rule.
- It has one button: "Start watching". The button closes the window and sets `welcomeSeen` to `true`.
- Closing the window without the button does not count as seen. The window shows again on the next launch.
  Reason: Spyre writes its config only after an explicit user action.
- The menubar window has a "Show welcome screen" item. It opens the window at any time. It does not change `welcomeSeen`.
- "Start watching" has no keyboard shortcut. Only a click (or VoiceOver) accepts the screen.
  A stray Return or Escape does nothing.
- The window tells the user the shortcut (in symbols, for example ⌃⌥S) and that opening the app again shows Spyre.
- The window opens after `applicationDidFinishLaunching`. Spyre asks macOS to activate it (`NSApp.activate()`).
  macOS 14 can refuse this when another app is frontmost. So the window also opens in front of all apps
  (`orderFrontRegardless`, floating level, on every Space and over full-screen apps).
  It becomes a normal window when it becomes key. It stays open until "Start watching" or the close button.

**Root cause of the v0.1 first-run bug.** Confirmed with the unified log and a local reproduction.
Spyre was launched with `open` from a terminal. macOS refused the activation (`NSApp.activate()` is a request).
The terminal stayed frontmost, and WindowServer marked the welcome window "occluded", so the user did not see it.
Opening Spyre from Raycast then showed nothing. A second `open` from the terminal activated Spyre (`SETFRONT`),
and the window became "visible".
1.6 s later a mouse click hit "Start watching" (`trackMouse send action on mouseUp`). No key event went to
Spyre. Spyre wrote `welcomeSeen: true` and closed the window. Opening Spyre again showed nothing,
because Spyre did not handle reopen, and the menubar icon was hidden.
Fixes: the window shows in front without activation; reopen and the shortcut open Spyre; no Return default.
A Return accepted the old window in the reproduction, so the Return guard stays.

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
  - `startedAt` matched the real start time within 1 s (verified). Spyre uses it first. A process that started more than 5 s after it has a reused PID.
  - `procStart` is in UTC in 2.1.293 (verified). Older versions (2.1.268 to 2.1.291) wrote a number with unknown meaning. Spyre uses `procStart` only when `startedAt` is missing.

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
| `name` | `Fix login bug` | Session title (the row title, 4.2). Shown locally only. |
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

**B. Hooks (optional)**

The optional Spyre hook uses the `PermissionRequest` event.
It fires when the permission dialog opens (`research/competitors.md`). The `Notification` event comes later (see timing below).

Rules for the hook snippet:

- The hook must print nothing to stdout. Claude Code can read hook output as an answer to the prompt. A status hook must never approve or deny.
- The hook must exit with code 0 and finish fast.
- The hook writes `~/Library/Application Support/Spyre/status/<session_id>.json`. The file holds `session_id`, `cwd`, `event`, and a timestamp. Nothing else.
- The hook never writes inside `~/.claude/`.
- Spyre shows the snippet with a "Copy" button. The user adds it to their settings by hand. Spyre never edits a settings file.

Real `Notification` payloads (verified, values faked). They are kept here as format evidence:

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
- The registry changes faster than the notification. This is why the optional hook uses `PermissionRequest`, not `Notification`.

Hook event used in the MVP:

| Event | Spyre status |
|-------|--------------|
| `PermissionRequest` | `waiting` |

All other states come from the registry.
A `PermissionRequest` hook from another tool can answer a prompt in about 2 s (verified). The registry then writes a newer status, and the merge rule (4.5) clears the hook state.

**C. Transcript (secondary)**

- Path: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` (verified).
- `<encoded-cwd>` is the `cwd` with each `/` replaced by `-`. Example: `-Users-you-Projects-app`. A `.` also becomes `-` (verified). Spyre replaces each character that is not a letter, digit, or `-` (inferred for other characters).
- Format: JSON Lines. The file only grows.
- Useful fields on `user`, `assistant`, and `system` records: `timestamp`, `cwd`, `gitBranch`, `sessionId`.
- Use: git branch, a fallback for last activity, and child session discovery (4.6).
- Read only the tail of the file. Never parse message content.

**D. Process names**

Verified on one Mac with `proc_name` and `proc_pidpath` (example paths are fake):

| Host | `proc_name` | Executable path (`proc_pidpath`) | Parent process |
|------|-------------|-----------------------------------|----------------|
| CLI, native installer | the version, for example `2.1.295` | `~/.local/share/claude/versions/<version>` | the shell |
| Desktop app | `claude` | `~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude` | `/Applications/Claude.app/Contents/Helpers/disclaimer` |
| VS Code extension | `claude` | `~/.vscode/extensions/anthropic.claude-code-<version>-<platform>/resources/native-binary/claude` | not observed |

Rules for the process scan:

- Do not match on `proc_name` alone. The CLI name is a version string.
- Match on the executable path. A Claude Code process has a path that ends in `/claude`, or that matches `/.local/share/claude/versions/<version>`.
- Cursor uses the same extension layout under `~/.cursor/extensions/` (verified: files only).
- An npm install runs Claude Code under `node`. The path is then the Node binary (inferred, not tested). The MVP does not support npm installs in the process scan. Those sessions still show from the registry file.
- The VS Code row is verified by running the extension binary directly. The parent process inside VS Code is not verified.

### 5.2 Codex

**A. Thread index**

- Path: `~/.codex/state_5.sqlite`, table `threads` (verified).
- The `5` is a schema version. Find the file by pattern `state_*.sqlite`. Pick the highest number.
- Useful columns: `id`, `rollout_path`, `cwd`, `git_branch`, `updated_at_ms`, `archived`, `cli_version`, `source`, `originator`, `title`.
- `title` is the thread title. Codex can derive it from the first prompt. Spyre shows it as the row title (4.2), on this Mac only. Spyre never logs it, stores it, or sends it anywhere. An empty `title`, or a schema without the column, gives no title.
- `source` and `originator` values seen with CLI 0.161.0 (verified):

| Started by | `source` | `originator` |
|------------|----------|--------------|
| TUI (`codex`) | `vscode` | `codex-tui` |
| `codex exec` | `exec` | `codex_exec` |
| ChatGPT desktop app | `vscode`, `exec`, or JSON (subagent) | `Codex Desktop` |

Older rows have other values, and often an empty `originator`.
- JSON `source` example (verified with writer 0.162.0-alpha.2): `{"subagent":{"thread_spawn":{"parent_thread_id":"…","depth":1,…}}}`. Spyre compares `source` as plain text. Only the exact value `exec` gives the exec label. A JSON value never fails parsing.
- **Writer version.** The daemon writes the thread row and the rollout, not the TUI (verified). A TUI 0.162.0 that started the installed daemon 0.161.0 wrote `cli_version` `0.161.0` and the 0.161.0 format. So `cli_version` and the `codex.cli` format version name the writer, which is the daemon. A Codex update changes the format only when the daemon package updates.
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

- Other event types are ignored. Writer 0.162.0-alpha.2 adds `thread_settings_applied` and `item_completed` around the status events (verified). Fixtures: `Tests/Fixtures/codex/0.161.0/` and `Tests/Fixtures/codex/0.162.0-alpha.2/`.
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

1. List processes whose executable (`proc_pidpath`) is named `codex` and that have a controlling terminal (`sysctl` `KERN_PROC_ALL`, flag `P_CONTROLT`). Drop executables under an `/app-server-daemon/` folder or inside an `.app` bundle. This keeps the TUI and `codex exec`. It drops the `app-server`, `app-server-daemon`, and `exec-server` processes, and the `codex` binaries that the ChatGPT app bundles.
   - The ChatGPT app's `app-server` and `exec-server` have no controlling terminal (verified).
   - The `app-server-daemon` has no controlling terminal (verified with CLI 0.161.0). The TUI starts it from its own copy, `~/.codex/packages/app-server-daemon/releases/<version>/bin/codex`. The TUI runs from `~/.codex/packages/standalone/releases/<version>/bin/codex`. One TUI started two daemon processes. Both are session leaders with no terminal. Their parent is the TUI at first, and PID 1 after the TUI exits.
   - Spyre does not read process arguments. On macOS, `KERN_PROCARGS2` returns the arguments and the environment in one buffer. So Spyre cannot tell `codex exec` from the TUI by its process. The thread index tells them apart (step 3).
   - All adapters share one process scanner (`ProcessScanner`). It lists processes once per refresh. Each adapter keeps its own filter.
2. Read each process's working directory with `proc_pidinfo` (`PROC_PIDVNODEPATHINFO`). The TUI's working directory is the project folder (verified).
3. Match each TUI to the non-archived thread with the same `cwd` and the newest `updated_at_ms`. Threads with `originator` `Codex Desktop` are skipped.
   - A thread with `source` `exec` is a `codex exec` run (verified). Its record has `label` `exec`. It is never `waiting`.
   - A live TUI in a folder with no thread row shows `starting` ("Starting…"), with the ID `codex:cwd:<folder>`. If there is still no thread row after `adapterRefreshTimeout` (2 s, measured with the injected clock), it shows `unknown`. A TUI has no thread row before its first turn.
4. A thread with a matching live TUI is live. Its rollout tail gives `working` or `idle` (B). A rollout with records but no status event gives `idle`. An unreadable or unparsable rollout gives `unknown` and a diagnostic.
5. A thread without a live TUI is `done`. Spyre reports it only while its `updated_at_ms` is less than 10 min old.
6. When the thread index cannot be read, each live TUI folder shows as one `unknown` row, with a diagnostic.

Limits:

- Two TUIs in the same folder cannot be told apart. Spyre shows one row for that folder: the thread with the newest `updated_at_ms`, with that thread's status. The other thread in that folder does not show, not even as `done`. The row stays live until the last TUI in that folder exits.
- A `codex exec` run with no controlling terminal, for example from a script, is not live. Its thread shows only as `done`.
- Spyre compares paths as strings after it removes `.`, `..`, and a trailing `/`. It does not resolve symlinks.
- ChatGPT desktop threads are out of scope. Spyre never shows them, not as live and not as `done`. Spyre skips each thread with `originator` `Codex Desktop`. Older desktop rows with an empty `originator` are not skipped. They come from older app versions, so in practice they are older than 10 min and do not show.

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
  - an optional mode label, for example `exec` for a `codex exec` run,
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
- A refresh that takes longer than `adapterRefreshTimeout` (2 s) counts as timed out. The app keeps the last snapshot, marks its rows "stale" (4.4), and logs a warning.

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

Before Lab work starts:

- Lab needs its own design doc. That doc defines how Spyre starts, limits, and stops agents.
- A human must approve the change to the observe-only rule.
- Spyre must get explicit user opt-in before it starts any agent. Opt-in is off by default.

## 8. Distribution

- No App Sandbox. Spyre must read `~/.claude` and `~/.codex`, and inspect other processes.
- Sign with a Developer ID certificate. Notarize every release.
- Distribute as a notarized `.dmg` on GitHub Releases and as a Homebrew cask.
- No Mac App Store build.
- Bundle id: `io.github.vilmerfrost.spyre`. `LSUIElement` is true, so Spyre has no Dock icon.
- `scripts/build-app.sh` builds a local, ad-hoc signed `.build/app/Spyre.app`. Release steps: `docs/release.md`.

## 9. Non-goals for MVP

- No Grab and no Lab sections. They show "Coming soon".
- No dock. Planned for v0.2.
- No settings UI for config values (4.4).
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
- Session titles (Claude Code registry `name`, Codex `threads.title`) can contain words from a prompt.
  Spyre shows them in its own windows only. It never logs them, writes them to disk, or sends them anywhere.
- Spyre never reads credential files: `~/.claude/.credentials.json`, `~/.claude/sessions/*.key`, `~/.codex/auth.json`.
- Spyre never reads the environment variables of another process.

## 11. Open questions

1. How stable are these formats across versions? We need fixture files per version in tests.

**Later**

These UNKNOWNs do not block the MVP.

- UNKNOWN: in a Codex hook, is `$PPID` the TUI process or the shared app-server daemon?
- UNKNOWN: do hooks fire in a child session? Does the parent process chain always reach the parent session, or can a host app or daemon sit in between?
- UNKNOWN: when does the `elicitation_dialog` notification fire? Which `waitingFor` value does the registry write for a question (`AskUserQuestion`) or an MCP elicitation?
