---
description: Mark the current Suhail Part skipped and optionally advance to the next.
disable-model-invocation: true
---

# /su-skip — Suhail Part skipper

You are skipping the **current Part** of the active Suhail run. This command takes no arguments. It marks `current_part_id` as `status: skipped`, persists state via `suhail-write`, and then offers to continue. It does NOT run any subagent itself. Advancement goes through the orchestrator (`su.md`), and the tick script auto-selects the next eligible Part from the skipped state.

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.suhail/state.json`. If it does not exist, end with: "No active Suhail run found — nothing to skip."
2. **Aborted run.** Parse `state.json`. If top-level `aborted == true`, end with: "This Suhail run has been aborted — no Part can be skipped."
3. **Nothing to skip.** If `current_part_id` is null/empty, OR the run is already terminal (`run_phase` is `finished`/`completed`, or every entry in `state.parts` has `status` of `completed` or `skipped`), end with: "No active Part to skip — the run has no Part in progress."

## Skip

After the guards pass:

1. Read `.suhail/state.json` into memory (the full object).
2. Pick the target Part: the Part whose `id == current_part_id` — unless that Part is already terminal (`completed`/`skipped`), in which case target the next eligible Part instead (the lowest-integer non-terminal Part whose dependencies are all terminal; this is the Part a "skip" at a level checkpoint means). Set the target's `status: "skipped"` and point `current_part_id` at it. A skipped Part is terminal, so on the next tick the batch routing (`batch_directive`) simply proceeds past it to the next dispatchable Part (or to `complete` when the whole batch is terminal); you do not compute anything beyond the target yourself.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Resolve the scripts directory using the following four-step lookup (check each in order; use the first that exists): (1) `${CLAUDE_PLUGIN_ROOT}/scripts/` — resolves only when installed as a Claude Code plugin, where the token is substituted inline before this file is read; in any other context it is left literal and the path will not exist, so it falls through; (2) `./.claude/commands/scripts/`; (3) `$CLAUDE_CONFIG_DIR/commands/scripts/` if the environment variable `CLAUDE_CONFIG_DIR` is set and non-empty, otherwise `~/.claude/commands/scripts/`; (4) `./scripts/` (dev-repo fallback). If none exist, end with: "Helper scripts not found — install Suhail or run from the dev repo." Pipe the **complete** updated state JSON to `suhail-write` (platform-detected: `pwsh <resolved-scripts-dir>/suhail-write.ps1 .suhail/state.json` on Windows; `bash <resolved-scripts-dir>/suhail-write.sh .suhail/state.json` on POSIX) with the full JSON on stdin. Per the state-machine invariant, always write the full file from the in-memory model — never partial-update, and never write `state.json` directly. On non-zero exit: write `.suhail/parts/<current_part_id>/blocker.md` (`from: orchestrator`) and end the turn.
5. Narrate one sentence: "🧭 Orchestrator — Part N skipped."
6. AskUserQuestion: "Part N skipped. Advance to the next eligible Part now?" with options `Continue` / `Pause`.
   - **Continue** → locate `su.md` (see below), read it, and follow its instructions for **exactly one tick** as if the user had typed `/su continue`. The orchestrator's tick routes past the skipped Part to the next dispatchable one. Do not loop beyond what the orchestrator does for a single `/su continue`.
   - **Pause** → end the turn with one sentence: "Paused — run `/su` or `/su-next` to advance when ready."

## Locating `su.md`

Check these paths in order:

1. Plugin install: `${CLAUDE_PLUGIN_ROOT}/commands/su.md` — resolves only when installed as a Claude Code plugin (token substituted inline before this file is read); otherwise the token is left literal and the path will not exist, so it falls through.
2. The same directory as this command file (sibling): project install `<repo>/.claude/commands/su.md`; user install `~/.claude/commands/su.md`.
3. If neither path is found, end with: "Cannot locate `su.md` — reinstall Suhail."

Do not duplicate or summarize the orchestrator logic here. The canonical state machine lives in `su.md`.

## Don't

- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not compute anything beyond the skip target — mark it skipped and let the tick routing advance the run.
- Do not dispatch a scout, executer, or verifier directly. Advancement goes through `su.md`.
- Do not write `state.json` directly — always go through `suhail-write` so `STATUS.md` stays in sync.
- Do not skip more than one Part per invocation. To skip several, run `/su-skip` repeatedly.
