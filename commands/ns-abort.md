---
description: Abort the current Northstar run by marking its state aborted. Does not delete artifacts.
---

# /ns-abort — Northstar run aborter

You are aborting the current Northstar run. This command takes no arguments. It sets `aborted: true` in `.northstar/state.json` and persists it via `northstar-write` (which also re-renders `STATUS.md`). It does NOT delete `.northstar/` or any artifacts — the run record is preserved for inspection.

`/ns-abort` does NOT initialize a run, does NOT advance state, and does NOT resolve blockers. It only flips the abort flag.

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.northstar/state.json`. If it does not exist, end with: "No active Northstar run found — nothing to abort."
2. **Already aborted.** Parse `state.json`. If top-level `aborted == true`, end with: "This Northstar run is already aborted — no action taken."

## Abort

After the guards pass:

1. Read `.northstar/state.json` into memory (the full object).
2. Set `aborted = true`.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Pipe the **complete** updated state JSON to `northstar-write` (platform-detected: `pwsh scripts/northstar-write.ps1 .northstar/state.json` on Windows; `bash scripts/northstar-write.sh .northstar/state.json` on POSIX) with the full JSON on stdin. Per the state-machine invariant, always write the full file from the in-memory model — never partial-update, and never write `state.json` directly.
5. On non-zero exit from `northstar-write`: write `.northstar/parts/<current_part_id>/blocker.md` (`from: orchestrator`) if a current Part exists, otherwise report the failure in one sentence with the exit code. Do NOT retry in a loop.
6. On success: end with a one-sentence confirmation, e.g. "Northstar run aborted — state marked `aborted`, artifacts under `.northstar/` preserved."

## Don't

- Do not delete `.northstar/` or any artifacts. Aborting only flips the flag; the run record stays for inspection.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not INIT a run, advance state, or dispatch any subagent.
- Do not resolve blockers or mutate `blocker.md` (except the write-failure blocker in step 5).
- Do not write `state.json` directly — always go through `northstar-write` so `STATUS.md` stays in sync.
