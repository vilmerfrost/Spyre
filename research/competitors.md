# Competitor study: Zeron and Evlat

Date: 2026-10-09. Scope: compare two public projects with Spyre's `SPEC.md` and the probe results in `docs/probes/2026-10-09-probe-results.md`.

Evidence labels:

- **VERIFIED**: seen in source code, or in the shipped app with REA.
- **INFERRED**: a conclusion from evidence. Not observed directly.

Sources: `zeronsh/zeron` at default branch (release v0.2.107), `evlat/evlat` at default branch (release v0.2.3). Both were read as source tarballs. Nothing was built or run. File paths below are relative to each repo root.

## Executive summary

- **Evlat is Spyre's direct competitor.** It is a native Swift/SwiftUI status strip for Claude Code and Codex on macOS. It solves the same problem: "which session waits for me?"
- **Zeron is a different product.** It is a Rust/gpui agent client. It starts and drives agents itself, inside its own terminals. It does not watch sessions that run in other terminals. Its ideas help less with Spyre's data layer, but some UI lessons apply.
- **Evlat is not MIT.** It uses the Functional Source License 1.1 (FSL-1.1-ALv2). It forbids a competing product built from its code. Spyre must take ideas only, never code. Zeron is MIT.
- **Terminal jump (old UNKNOWN 6) has a known, permission-free answer** for iTerm2, Warp, cmux and the Claude desktop app. Read the agent's environment with `sysctl(KERN_PROCARGS2)`. Walk parent PIDs to the terminal app. Open the terminal's own tab URL. Terminal.app and Ghostty cannot select a tab without Apple Events, so Evlat only brings them forward.
- **Codex `waiting` is possible with a Codex `PermissionRequest` hook.** Evlat ships this. It only works for Codex CLI sessions. The Codex desktop app runs no hooks.

## Top 5 findings

1. **Tab jump without permissions** (VERIFIED, Evlat `Sources/EvlatApp/SessionHost/TabLink.swift:71-97`, `SessionHost.swift:145-172`). Details in section 4.
2. **Use `PermissionRequest` as the instant `waiting` signal** (VERIFIED, Evlat `Sources/EvlatCore/HooksProvider.swift:127-160`). Spyre's probe showed that the `permission_prompt` notification is delayed. `PermissionRequest` fires when the dialog opens. A status-only hook must print nothing on stdout, or it can grant or deny the prompt.
3. **Do not let "newest source wins" decide merges.** Evlat uses a compatibility rule on source fidelity. "Hook wins" froze sessions that ended while the app was closed (VERIFIED, Evlat `AGENTS.md:270-280`).
4. **Do not reorder rows by status.** Zeron removed its attention-bucket sort. Rows moved under the pointer when a status changed (VERIFIED, Zeron `crates/proto/src/view.rs:96-112`). Spyre's spec sorts by status.
5. **The registry has traps.** A new `<pid>.json` has no `status` field for about 500 ms. The file is not written at hook rate. It is written in place, not atomically. A `status` value `shell` was seen once (VERIFIED as Evlat's documented measurements, `AGENTS.md:751-757`, `Sources/EvlatAgents/Claude/SessionsProvider.swift:163-173`).

## 1. Overview

| | Zeron | Evlat |
|---|---|---|
| What it is | Desktop + headless client that runs coding agents. Optional multi-device sync. | Status strip on the screen edge. Shows each agent session's state. |
| Agents | Claude Code, Codex, Cursor, Devin, Grok, Hermes, Pi, Antigravity, OpenCode | Claude Code, Codex, Antigravity |
| Sees sessions started elsewhere | No. Open request zeronsh/zeron#743 asks for it. | Yes. Hooks + Claude session registry. |
| Language / UI | Rust, gpui (Zed's UI framework) | Swift 5, AppKit + SwiftUI, macOS 14+ |
| License | MIT (VERIFIED, `LICENSE`) | FSL-1.1-ALv2 (VERIFIED, `LICENSE.md`). Becomes Apache 2.0 two years after each release. CLA for contributors. |
| Size / activity | ~3.1k stars, release 2026-10-08 | ~12 stars, release 2026-10-09, 0 issues |

## 2. Per-repo answers

### 2.1 Zeron

**Q1. What it does.** Zeron is an "engine + viewport" app. The engine starts agent processes and stores transcripts as Loro CRDT docs. The UI renders them (VERIFIED, `ARCHITECTURE.md` §1-2).

**Q2. Session discovery.** Zeron does not discover sessions. It only knows sessions it started (VERIFIED, `ARCHITECTURE.md` §5 "Harness"; no reads of `~/.claude/sessions` or `state_*.sqlite` in `crates/`; zeronsh/zeron#743).

**Q3. Waiting detection.** Zeron owns the agent's stdio, so it sees requests directly:

- Claude Code: `claude -p --input-format stream-json --output-format stream-json --permission-prompt-tool stdio`. The CLI sends `control_request` frames with subtype `can_use_tool`. Zeron auto-allows tools and turns `AskUserQuestion` into a question panel (VERIFIED, `crates/harness/src/claude/mod.rs:1-40`, `:1326-1372`).
- Codex: `codex app-server` JSON-RPC. Approval methods are `item/commandExecution/requestApproval` and `item/fileChange/requestApproval`. Questions are `item/tool/requestUserInput`. Zeron sets `approvalPolicy: "never"` by default (VERIFIED, `crates/harness/src/codex/mod.rs:14-22`, `:1075-1079`, `:2066-2094`).
- Status enum: `Idle`, `Working`, `AwaitingInput`, `Errored`. A `Working` or `AwaitingInput` row older than 45 s without a heartbeat shows as nothing (VERIFIED, `crates/proto/src/entities.rs:296-301`, `crates/proto/src/view.rs:37-62`).

None of this works for sessions Spyre does not own. Spyre cannot attach to another process's app-server socket.

**Q4. Terminal jump.** Not needed. Zeron embeds its own terminals (`alacritty_terminal` + `portable-pty`) and sets `TERM_PROGRAM=Zeron` (VERIFIED, `ARCHITECTURE.md` §4, `crates/engine/src/terminals.rs:282`). It has no code for Terminal.app, iTerm2, Ghostty, Warp or VS Code.

**Q5. Sandbox.** Not sandboxed. Hardened runtime on. The only entitlement is `com.apple.security.device.audio-input` (VERIFIED with REA on the installed app 0.2.106, and in `dist/macos/*.entitlements`). It also registers a `zeron://` URL scheme (VERIFIED, REA `inspect_plist`).

**Q6. Format changes.** Parsers are "tolerant by construction": every field has a default; unknown frame types map to `Frame::Other` (VERIFIED, `crates/harness/src/claude/wire.rs:1-25`). Fixtures carry the CLI version in the file name, for example `crates/harness/tests/fixtures/claude/live-2.1.228-background-subagent.jsonl` and `.../codex/live-0.146.1-multi-agent.jsonl`. Fake agent scripts drive tests (`fake-claude.sh`, `fake-codex.sh`).

**Q7. UI stack.** Rust workspace: `proto`, `doc`, `sync`, `harness`, `engine`, `rpc`, `theme`, `ui` and more. One binary runs headed or headless (VERIFIED, `ARCHITECTURE.md` §3).

**Q8. Theming.** Large theme system. It imports VS Code themes (file or extension package), keeps "last known good" on bad edits, and has accent overrides and a frosted/opaque surface preference (VERIFIED, `CONTEXT.md`, `crates/theme`).

**Q9. Open issues (relevant).**

- zeronsh/zeron#806: UI freezes after a Space or app switch on macOS.
- zeronsh/zeron#644, zeronsh/zeron#668: question tool does not show or hangs. Questions are a fragile path.
- zeronsh/zeron#845: background subagents show as "done" at spawn.
- zeronsh/zeron#831: idle reaper ends a session while a background shell runs.
- zeronsh/zeron#743: no import or discovery of existing sessions.

### 2.2 Evlat

**Q1. What it does.** A non-activating `NSPanel` on the screen edge with a mascot and one ring per session. Hover shows a list; a card shows "Go to session". It also shows Claude/Codex usage limits, `evlat watch <cmd>` jobs, remote machines over SSH, Docker sandboxes and a chat bubble (VERIFIED, `README.md`, `AGENTS.md:13-21`).

**Q2. Session discovery.** Two providers merge into one row per session (VERIFIED, `AGENTS.md:180-191`, `:270-280`):

- `hooks` (primary): Evlat writes hook commands into `~/.claude/settings.json` and `~/.codex/hooks.json`, after user consent in its setup. The hook is `curl --unix-socket ~/.config/evlat/run/evlat.sock ... -H "X-Evlat-Pid: $PPID" --data-binary @- ... >/dev/null 2>&1 || true` (VERIFIED, `Sources/EvlatCore/LocalAPI.swift:481-490`). `$PPID` gives the agent PID.
- `claude-sessions` (supplement): reads `~/.claude/sessions/*.json`, checks PID liveness and start time against PID reuse (VERIFIED, `Sources/EvlatAgents/Claude/SessionsProvider.swift:101-160`).
- Codex has no file provider. Codex rows come only from hooks.

**Q3. Waiting detection.** Hook event table (VERIFIED, `Sources/EvlatCore/HooksProvider.swift:127-160`; strings `elicitation_dialog` and `agent_needs_input` VERIFIED in the shipped binary 0.2.2 with REA):

| Event | Evlat phase |
|---|---|
| `SessionStart` | idle |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | working |
| `PostToolUseFailure`, `PermissionDenied` | working (the wait is over) |
| `PermissionRequest` | waiting |
| `Notification` with `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` | waiting |
| `Notification` with `idle_prompt` | no change |
| `Stop` (unless `stop_hook_active`) | review (finished, unseen) |
| `StopFailure` | failed |
| `SessionEnd` | row ends |
| Codex `Interrupt` | translated to `Stop` |

More rules:

- A blocking phase remembers its owner (`agent_id` for a subagent). Only that owner, or `Stop` / `UserPromptSubmit`, can lift it. Without this, a sibling subagent's `PostToolUse` cleared a real wait (VERIFIED, `HooksProvider.swift:163-205`).
- `AskUserQuestion` arrives as `PermissionRequest` with `tool_name: "AskUserQuestion"`. Evlat labels the wait as "answer" not "approval" (VERIFIED, `HooksProvider.swift:213-225`, `Sources/EvlatCore/AskQuestion.swift`).
- The registry mapping is `busy` → working, `idle` → idle, `waiting` → waiting. Unknown words stay visible as raw status. Evlat says it never saw `waiting` in the registry; it saw `shell` once (VERIFIED as a code comment, `SessionsProvider.swift:163-173`). Spyre's probe did see `waiting`, so the registry may have changed since Evlat measured.

**Q4. Terminal jump.** See section 4. This is the strongest part of Evlat.

**Q5. Sandbox.** Not sandboxed. Hardened runtime on. No entitlements at all. `LSUIElement` is true. No Apple Events usage string (VERIFIED with REA on installed Evlat 0.2.2: `inspect_signature` → `entitlements: null`, `hardened_runtime: true`; `inspect_plist`). Policy: "No macOS permission is requested", except notifications on opt-in. A new permission is an architecture decision (VERIFIED, `AGENTS.md:417-427`). Smart-hide reads other windows' bounds with `CGWindowListCopyWindowInfo`, but never window names, so Screen Recording is not needed.

**Q6. Format changes.**

- Registry provider is marked `derived` fidelity. Unknown `status` values go to a diagnostics set, not into silence. Missing `statusUpdatedAt` is counted as a drift signal (VERIFIED, `SessionsProvider.swift:16-56`).
- Installed hook commands are "contracts" pinned by golden-string tests (VERIFIED, `AGENTS.md:467-476`, `Tests/EvlatAgentsTests/LocalAPITests.swift`).
- Fake agent binaries in `Tests/Fixtures/` (`fake-claude`, `fake-codex-app-server`).
- Each measurement names the agent version (for example "2.1.285", "codex-cli 0.160.0").
- Weak point: no per-version JSON fixture files for the registry, unlike Zeron.

**Q7. UI stack.** Three Swift package targets with one-way imports: `EvlatCore` (Foundation only) ← `EvlatAgents` ← `EvlatApp` (AppKit + SwiftUI). Boundary tests fail when shared code names an agent (VERIFIED, `AGENTS.md:61-107`). The working spinner is a Core Animation layer, not a SwiftUI animation, for CPU reasons (VERIFIED, `AGENTS.md:320-332`). Sparkle for updates.

**Q8. Theming.** Mascots: built-in characters, a published `character.json` format, Codex pet sheets from `~/.codex/pets`, and a `evlat mascot check` linter. Body modes (Always visible, Smart hide, Tucked, Hidden). Sound packs from the OpenPeon registry. 12 languages (VERIFIED, `README.md`, `AGENTS.md:333-363`).

**Q9. Open issues.** None. The repo has 0 issues, open or closed (VERIFIED, `gh issue list --state all`). Pain points come from its own "Pitfalls" list in `AGENTS.md:747-953` instead. The most relevant are in sections 5 and 6.

## 3. REA usage

| Tool | Target | Result |
|---|---|---|
| `open_binary` | installed `Evlat.app` 0.2.2, `Zeron.app` 0.2.106 | Both are arm64 Mach-O. |
| `inspect_signature` | both | Both Developer ID signed with hardened runtime. Evlat: no entitlements. Zeron: audio input only. Neither is sandboxed. |
| `inspect_plist` | both | Evlat: `LSUIElement`, Sparkle feed, macOS 14. Zeron: `zeron://` URL scheme, microphone string, macOS 12. |
| `search_strings` | Evlat | Found `iterm2:reveal?sessionid=`, `ITERM_SESSION_ID`, `elicitation_dialog`, `agent_needs_input`. This confirms the shipped build matches the source. |

Limitation: `WARP_FOCUS_URL` (14 chars) and `CMUX_SURFACE_ID` (15 chars) were not found. INFERRED cause: Swift stores strings of 15 bytes or fewer inline in code, not in the string table. The changelog says Warp support shipped in 0.1.3 and cmux in 0.1.7. No app was launched. No user data file was read.

## 4. Terminal jump (old UNKNOWN 6): answer

Evlat's method needs no macOS permission (VERIFIED, `SessionHost.swift`, `ProcessReads.swift`, `TabLink.swift`):

1. **Get the agent PID.** Claude: `pid` in the registry file. Hooks: `$PPID` in the hook command.
2. **Find the terminal app.** Walk parent PIDs with `sysctl(KERN_PROC_PID)` until a process is a `.regular` `NSRunningApplication`. Fallbacks, in order:
   - The outermost `.app` in any ancestor's executable path (catches helpers that launchd adopted).
   - iTerm2's server binary under `~/Library/Application Support/iTerm2/iTermServer-*`.
   - Processes that hold the pty master of the agent's tty (`proc_pidinfo(PROC_PIDLISTFDS)`). All holders must reach the same app.
   - For tmux or herdr panes: ask the multiplexer for its client, then walk from the client.
3. **Read the tab ID.** Read the agent's exec-time environment with `sysctl(KERN_PROCARGS2)`. This works for processes of the same user without a permission. Validate each value with a strict pattern before use.
4. **Open the terminal's own URL** with `NSWorkspace.open([url], withApplicationAt: <running app bundle>)`. On failure, `activate` the app.

| Terminal | Variable | URL | Tab selected |
|---|---|---|---|
| iTerm2 | `ITERM_SESSION_ID` (`w0t0p0:<UUID>`) | `iterm2:reveal?sessionid=<whole value>` | Yes |
| Warp | `WARP_FOCUS_URL` | the value (`warp://session/<hex>`) | Yes |
| cmux | `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID` | `cmux://workspace/<id>/surface/<id>` | Yes |
| Claude desktop | `CLAUDE_CODE_HOST_SESSION_ID` (`local_...`) | `claude://code/continue?session=<id>` | Yes (undocumented) |
| Bateri, Metalterm | `BATERI_TAB_URL`, `METALTERM_TAB_URL` | the value | Yes |
| Terminal.app | none | none | No. App comes forward only. |
| Ghostty | none | none | No. App comes forward only. |
| VS Code | not in Evlat's table | none | No (INFERRED: app comes forward only). |

Notes:

- Only use iTerm2's `reveal` command. Other iTerm2 URL commands run code (VERIFIED as a comment, `TabLink.swift:10-14`).
- The environment is the one at `exec`. Inside tmux it can be stale. Evlat does not name a tab when the walk passed a multiplexer server without finding its client (VERIFIED, `SessionHost.swift:150-167`).
- Terminal.app and Ghostty tab selection needs Apple Events (Automation permission), for example matching each tab's `tty` in AppleScript. Evlat refuses this by policy (VERIFIED, `TabLink.swift:32-33`). Whether Ghostty's newer scripting support allows it is UNKNOWN.
- Resolve the host at click time. Do not cache it. The app may have quit (VERIFIED, `SessionHost.swift:17-18`).

Recommendation for Spyre: replace "open the project folder" with this ladder after the MVP: tab URL → bring the app forward → open the folder (today's MVP behavior) as the last fallback.

## 5. Other UNKNOWNs

| Spyre UNKNOWN | Answer | Status |
|---|---|---|
| Codex waiting / approval detection | Codex supports a `PermissionRequest` hook in `~/.codex/hooks.json`. Evlat maps it to `waiting` and maps `Interrupt` to `Stop` (`Sources/EvlatAgents/Codex/Codex.swift:14-18`, `CodexHookAdapter.swift:9-23`). Codex trusts hooks by hash in `config.toml`. A changed hook command runs only after the user trusts it again in `/hooks` (`AGENTS.md:815-820`). The ChatGPT/Codex desktop app runs no hooks (`AGENTS.md:777-782`). The rollout file still shows no approval events. | Answered for Codex CLI. Not possible for Codex desktop. |
| Codex same-folder ambiguity | Hook payloads carry `session_id`, so two threads in one folder become two rows. Evlat also sends `$PPID`. | Partly answered. Whether `$PPID` is the TUI or the shared `app-server-daemon` on Codex 0.161 is UNKNOWN. Spyre's probe found that the daemon does the thread work. Measure it before using `$PPID` for liveness. |
| Child sessions (`CLAUDE_CODE_CHILD_SESSION`) | Evlat confirms these are parent-session markers and strips them before it starts `claude` (`Sources/EvlatAgents/Claude/Chat/ClaudeInvocation.swift:23-34`). Hooks come from settings files, not the registry, so a child session should still fire Spyre's hook. | INFERRED. Not measured by either project. |
| `elicitation_dialog` | Evlat treats `elicitation_dialog`, `elicitation_url_dialog` and `agent_needs_input` as `waiting`. Strings are in its shipped binary. | Mapping VERIFIED. Firing conditions still UNKNOWN. Add the two extra types to Spyre's table. |
| `waitingFor` for a question | Not answered. Evlat detects questions from the hook (`PermissionRequest` with `tool_name: "AskUserQuestion"`), not from the registry. | UNKNOWN. Spyre can use the same hook signal. |

## 6. Ideas to adopt

1. **Add `PermissionRequest` to the Spyre hook as `waiting`.** It fires when the dialog opens. The notification fires late. The hook must write nothing to stdout and always exit 0. A JSON reply on stdout can answer the prompt (VERIFIED, `AGENTS.md:470-473`).
2. **Add "wait is over" events.** `PostToolUse`, `PostToolUseFailure` and `PermissionDenied` move `waiting` back to `working`. Without them, an approved tool that later fails can leave `waiting` forever.
3. **Track the block owner** (`agent_id`). Subagent events must not clear the main thread's wait.
4. **Ignore `Stop` when `stop_hook_active` is true.** Treating it as a real stop loops.
5. **Add a "finished, not seen" state.** Both projects separate "done and unseen" from "idle" (Evlat `review`, Zeron `Completed`). It answers "what finished while I was away?" without adding to the waiting badge.
6. **Stable row order.** Keep `waiting` rows on top if wanted, but do not resort other rows on every status change. Zeron's users complained about rows moving.
7. **Count unknown values.** Keep the raw status word visible in diagnostics. Count records with missing timestamps as format drift. This fits Spyre's adapter rule 4.6.
8. **Name fixtures by version.** Follow Zeron: `fixtures/claude/registry-2.1.295-waiting.json`.
9. **Pin the hook snippet with a golden-string test.** The snippet is a contract that lives on users' machines.
10. **Tab jump ladder** from section 4.

## 7. Mistakes to avoid

1. **"Newest source wins" merge.** A stale hook state can outlive a dead process. Prefer: PID dead → `done`, always. Accept a hook phase only when it can be true together with the registry phase (for example hook `waiting` beside registry `busy`).
2. **Treating a missing `status` as `idle`.** A new registry file lacks `status` for about 500 ms. Show the last known state or `unknown`.
3. **Assuming atomic writes.** The registry file is written in place. Retry once on a JSON parse error before showing `unknown`.
4. **Using `idle_prompt` as a state.** Evlat ignores it. Spyre already does not use it as "finished". Keep it that way.
5. **Writing user config files.** Evlat edits `settings.json` and `hooks.json` and now needs an "update your hooks" flow and Codex re-trust after each change (Evlat `CHANGELOG.md` 0.2.3). Spyre's "user pastes the snippet" rule avoids this. Keep the snippet stable, because every change forces Codex users through `/hooks` again.
6. **Inheriting agent environment.** If Spyre ever starts `claude` or `codex`, strip `CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION` and the other parent markers first.
7. **Continuous SwiftUI animation in a menubar app.** Evlat measured about 7% CPU for any continuous SwiftUI animation. Use a Core Animation layer for a spinner, or no animation.
8. **Feature sprawl.** Zeron's issue list is mostly about sync, harnesses and platform ports. Spyre's read-only scope is a strength.

## 8. License notes for later reuse

- Evlat: FSL-1.1-ALv2. Do not copy code into Spyre. A version becomes Apache 2.0 two years after its release. `TabLink.swift` and `SessionHost.swift` are the files to revisit after that date. Until then, use the documented technique only (public OS APIs and the terminals' own URL schemes).
- Zeron: MIT. Reuse is allowed with the copyright notice. Little of it fits Spyre, because it is Rust and owns its agents.

## 9. Test plan for this research

- Both repos were downloaded as source tarballs with `gh api repos/<owner>/<repo>/tarball` into a temporary folder. Nothing was built or executed.
- Licenses were read from `LICENSE` (Zeron) and `LICENSE.md` (Evlat), and checked against `gh repo view --json licenseInfo`.
- Issues were listed with `gh issue list --state open --limit 50` (Zeron) and `--state all` (Evlat, which has none). Relevant Zeron issues were read with `gh issue view`.
- REA was used read-only on the installed apps, as in section 3. Neither app was launched, changed or stopped. No session, transcript or credential file was read.
- Not tested: any claim that needs a live run. This includes when `elicitation_dialog` fires, what `$PPID` is in a Codex 0.161 hook, and whether child sessions fire hooks.
