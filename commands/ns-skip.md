---
description: Mark the current Northstar Part skipped and optionally advance to the next.
---

# /ns-skip — Northstar Part skipper

You are skipping the **current Part** of the active Northstar run. This command takes no arguments. It marks `current_part_id` as `status: skipped`, persists state via `northstar-write`, and then offers to continue. It does NOT run any subagent itself — advancement is delegated to the orchestrator (`ns.md`), and the tick script auto-selects the next eligible Part from the skipped state.

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.northstar/state.json`. If it does not exist, end with: "No active Northstar run found — nothing to skip."
2. **Aborted run.** Parse `state.json`. If top-level `aborted == true`, end with: "This Northstar run has been aborted — no Part can be skipped."
3. **Nothing to skip.** If `current_part_id` is null/empty, OR the run is already terminal (`run_phase` is `finished`/`completed`, or every entry in `state.parts` has `status` of `completed` or `skipped`), end with: "No active Part to skip — the run has no Part in progress."

## Skip

After the guards pass:

1. Read `.northstar/state.json` into memory (the full object).
2. Set the Part whose `id == current_part_id` to `status: "skipped"`. Leave `current_part_id` pointing at it — the tick script's `skipped` branch selects the next eligible Part on the next tick (`advance_to_part`), so you do not compute the next Part yourself.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Pipe the **complete** updated state JSON to `northstar-write` (platform-detected: `pwsh scripts/northstar-write.ps1 .northstar/state.json` on Windows; `bash scripts/northstar-write.sh .northstar/state.json` on POSIX) with the full JSON on stdin. Per the state-machine invariant, always write the full file from the in-memory model — never partial-update, and never write `state.json` directly. On non-zero exit: write `.northstar/parts/<current_part_id>/blocker.md` (`from: orchestrator`) and end the turn.
5. Narrate one sentence: "🧭 Orchestrator — Part N skipped."
6. AskUserQuestion: "Part N skipped. Advance to the next eligible Part now?" with options `Continue` / `Pause`.
   - **Continue** → locate `ns.md` (see below), read it, and follow its instructions for **exactly one tick** as if the user had typed `/ns continue`. The orchestrator's tick will resolve `advance_to_part` and dispatch the next Part. Do not loop beyond what the orchestrator does for a single `/ns continue`.
   - **Pause** → end the turn with one sentence: "Paused — run `/ns` or `/ns-next` to advance when ready."

## Locating `ns.md`

Check these paths in order:

1. The same directory as this command file (sibling): project install `<repo>/.claude/commands/ns.md`; user install `~/.claude/commands/ns.md`.
2. If neither contains the file, fall back to `northstar.md` in the same locations. If neither contains `northstar.md` either, end with: "Cannot locate `ns.md` — reinstall Northstar."

Do not duplicate or summarize the orchestrator logic here. The canonical state machine lives in `ns.md`.

## Don't

- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not compute the next Part yourself — mark the current Part skipped and let the tick script select the next eligible Part.
- Do not dispatch a scout, executer, or verifier directly. Advancement goes through `ns.md`.
- Do not write `state.json` directly — always go through `northstar-write` so `STATUS.md` stays in sync.
- Do not skip more than one Part per invocation. To skip several, run `/ns-skip` repeatedly.
