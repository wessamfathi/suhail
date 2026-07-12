---
description: Abort the current Suhail run by marking its state aborted. Does not delete artifacts.
disable-model-invocation: true
---

# /su-abort — Suhail run aborter

You are aborting the current Suhail run. This command takes no arguments. It sets `aborted: true` in `.suhail/state.json` and persists it via `suhail-write` (which also re-renders `STATUS.md`). It does NOT delete `.suhail/` or any artifacts; the run record stays on disk for inspection.

`/su-abort` does NOT initialize a run, does NOT advance state, and does NOT resolve blockers. It only flips the abort flag.

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.suhail/state.json`. If it does not exist, end with: "No active Suhail run found — nothing to abort."
2. **Already aborted.** Parse `state.json`. If top-level `aborted == true`, end with: "This Suhail run is already aborted — no action taken."

## Abort

After the guards pass:

1. Read `.suhail/state.json` into memory (the full object).
2. Set `aborted = true`.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Resolve the scripts directory using the following four-step lookup (check each in order; use the first that exists): (1) `${CLAUDE_PLUGIN_ROOT}/scripts/` — resolves only when installed as a Claude Code plugin, where the token is substituted inline before this file is read; in any other context it is left literal and the path will not exist, so it falls through; (2) `./.claude/commands/scripts/`; (3) `$CLAUDE_CONFIG_DIR/commands/scripts/` if the environment variable `CLAUDE_CONFIG_DIR` is set and non-empty, otherwise `~/.claude/commands/scripts/`; (4) `./scripts/` (dev-repo fallback). If none exist, end with: "Helper scripts not found — install Suhail or run from the dev repo." Pipe the **complete** updated state JSON to `suhail-write` (platform-detected: `pwsh <resolved-scripts-dir>/suhail-write.ps1 .suhail/state.json` on Windows; `bash <resolved-scripts-dir>/suhail-write.sh .suhail/state.json` on POSIX) with the full JSON on stdin. Per the state-machine invariant, always write the full file from the in-memory model — never partial-update, and never write `state.json` directly.
5. On non-zero exit from `suhail-write`: write `.suhail/parts/<current_part_id>/blocker.md` (`from: orchestrator`) if a current Part exists, otherwise report the failure in one sentence with the exit code. Do NOT retry in a loop.
6. On success: end with a one-sentence confirmation, e.g. "Suhail run aborted — state marked `aborted`, artifacts under `.suhail/` preserved."

## Don't

- Do not delete `.suhail/` or any artifacts. Aborting only flips the flag; the run record stays for inspection.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not INIT a run, advance state, or dispatch any subagent.
- Do not resolve blockers or mutate `blocker.md` (except the write-failure blocker in step 5).
- Do not write `state.json` directly — always go through `suhail-write` so `STATUS.md` stays in sync.
