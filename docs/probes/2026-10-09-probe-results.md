# Probe results: 2026-10-09

Experiments that resolve UNKNOWNs 1, 2, 3 and 5 from PR #1.
All IDs, paths and prompts below are fake.

Setup: macOS on Apple silicon, Claude Code 2.1.295 (CLI binary), Codex CLI 0.161.0.
Each session ran in a pseudo-terminal under `expect` in an empty temp folder.

## Test-setup traps

Read these before you repeat the tests.

- **Clean environment.** A session launched from inside another Claude Code session inherits `CLAUDE_CODE_CHILD_SESSION`. With that variable set, Claude Code writes no registry file. Launch with `env -i HOME=… PATH=… TERM=…`.
- **User hooks.** A user-level `PermissionRequest` hook answered the prompt in about 2 s. Use `--setting-sources local --settings <probe-hooks.json>` to load only the probe hook.
- **Trust dialog.** A new folder shows "Do you trust this folder?". The default choice is "No, exit".
- **Codex daemon.** A Codex TUI starts a detached `app-server-daemon`. The daemon keeps any pipe it inherited open. Stop it after the test.

## UNKNOWN 1: does the registry show `waiting`? RESOLVED

Prompt: "Use the Bash tool to run exactly: touch probe.txt". Permission mode: `default`.

| Time | `status` | `waitingFor` |
|------|----------|--------------|
| Prompt open, 0 s | `waiting` | `permission prompt` |
| Prompt open, 30 s | `waiting` | `permission prompt` |
| After deny (Esc) | `idle` | absent |
| After about 2 min idle | `idle` | absent |

## UNKNOWN 2: do CLI sessions write the registry? RESOLVED

- Yes. `~/.claude/sessions/<pid>.json` exists with `"entrypoint": "cli"` and `"kind": "interactive"`.
- No, when `CLAUDE_CODE_CHILD_SESSION` is set. Then only `<pid>.<hash>.key` exists.
- A clean `/exit` deletes both `<pid>.json` and `<pid>.<hash>.key`.

## UNKNOWN 3: real Notification payloads. RESOLVED

The probe hook ran `cat >> /tmp/spyre-probe/notify.jsonl` on stdin. It was loaded with `--settings`.
`~/.claude/settings.json` was never edited. Its SHA-256 was the same before and after, and `diff` showed no change.

Fields in both payloads: `session_id`, `transcript_path`, `cwd`, `prompt_id`, `hook_event_name`, `message`, `notification_type`. Some runs also had `scratchpad_dir`.

| `notification_type` | `message` | Observed |
|---------------------|-----------|----------|
| `permission_prompt` | `Claude needs your permission` | Fired with the prompt open 30 s. Did not fire when the prompt closed at 4 s. |
| `idle_prompt` | `Claude is waiting for your input` | Fired in 1 of 2 runs, within about 2 min. |
| `elicitation_dialog` | n/a | Not triggered. Still UNKNOWN. |

## UNKNOWN 5: Codex live vs dead. RESOLVED (with limits)

Two Codex TUIs (A and B) ran in two folders. Both finished one turn. Then A got `kill -9` and B exited with Ctrl-C.

| Check | Result |
|-------|--------|
| Who holds `thread-writer-locks/<id>.lock` | One `app-server-daemon` process, for both threads. Not the TUIs. |
| Daemon parent | PID 1 (detached). Started by the first TUI. |
| Locks after A killed | Still held by the daemon. |
| Locks after B exited | Still held by the daemon. |
| Rollout tail, killed vs exited | Same: `task_complete` is the last event in both. |
| `threads.updated_at_ms` | No change at exit. |
| TUI process `cwd` | The project folder. |
| TUI ↔ daemon link | Unix domain socket. |

Conclusion:

- Lock files and rollouts cannot tell live from dead.
- The process table can. A `codex` process that is not an app-server, with `cwd` equal to the thread `cwd`, means the session is live.
- Limit: two TUIs in the same folder cannot be told apart.
