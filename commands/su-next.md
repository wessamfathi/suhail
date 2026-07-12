---
description: Auto-advance the current Suhail run by exactly one logical step.
disable-model-invocation: true
---

# /su-next — Suhail auto-stepper

You are advancing the current Suhail run by **exactly one logical step**. This command takes no arguments. It is a non-interactive shortcut for the user who wants to hit "next" without typing `/su continue` or answering the inter-Part "Continue?" prompt.

`/su-next` does NOT initialize a run, does NOT loop (even in `run-to` mode), and does NOT resolve blockers. It only advances one tick of the orchestrator's state machine, with two sanctioned special cases where it injects an implicit approval so the run progresses without re-prompting the user: when the current step is `awaiting_plan_approval` (per-Part), and when `run_phase == "master_plan_approval"` (batch checkpoint).

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.suhail/state.json`. If it does not exist, end with: "No active Suhail run found — run `/su-discover` to draft a plan or `/su <plan-path>` to initialize one."
2. **Aborted run.** Parse `state.json`. If top-level `aborted == true`, end with: "This Suhail run has been aborted — no further steps are possible."
3. **Unresolved blocker.** If `current_step == "needs_user"` OR `.suhail/parts/<current_part_id>/blocker.md` exists without a `resolution:` line, end with: "A blocker is waiting at `.suhail/parts/<current_part_id>/blocker.md` — resolve it via `/su` before using `/su-next`."
   - Check filesystem presence of `blocker.md` via Read or Bash `[ -f path ]` (POSIX) / `Test-Path path` (PowerShell). Both conditions are checked (OR) — the filesystem check is the authoritative safety net in case `current_step` was not updated.
4. **Run complete.** If `aborted == false` AND every entry in `state.parts` has `status` of `completed` or `skipped`, end with: "All Parts are complete — nothing left to advance."

## Dispatch

After the guards pass, first check `run_phase`. If `run_phase == "master_plan_approval"`, take the `master_plan_approval checkpoint` branch below. Otherwise, branch on `current_step`.

### master_plan_approval checkpoint

Inject the batch Approve-all resolution without presenting an AskUserQuestion. This mirrors the **Autorun guard** step and the `Approve all` resolution in `su.md`'s `await_approval` (reason = `all parts scouted` or `master_plan_approval`) handler — it is the `/su-next` equivalent of that same state mutation:

1. Read `.suhail/state.json` into memory.
2. Set `batch_auto_approve = true`.
3. For every Part id listed in `current_batch`, set that Part's `status = "executing"`.
4. Set `current_part_id` to the lowest-integer Part id in `current_batch` (parse the numeric suffix of each `part-N` id and take the minimum N).
5. Set `run_phase = "executing"`.
6. Update `updated_at` to the current ISO 8601 timestamp.
7. Write the full state.json back (per the state-machine invariant: always write the full file from the in-memory model, never partial-update), via `suhail-write` using the same platform-detection logic as the `awaiting_plan_approval` branch below.
8. Locate `su.md` using the lookup below, read it, and follow its instructions for **exactly one tick** as if the orchestrator had been invoked with empty arguments. With `current_part_id` now pointing at a Part whose `status = "executing"`, this tick dispatches the executer for that Part.
9. After the single re-tick, end the turn. Do NOT loop further regardless of mode.

This checkpoint is checked before the `current_step`-based branches below because at a batch checkpoint, `current_step` is a per-Part field that has not been advanced past its prior value and does not distinguish this state — `run_phase` is the authoritative signal here.

### awaiting_plan_approval

Inject an implicit "Approve" without presenting an AskUserQuestion to the user. This is the `/su-next` equivalent of the `Approve` branch in `su.md`'s `await_approval` (reason = `part_plan_approval`) handler:

1. Read `.suhail/state.json` into memory.
2. Set the gated Part's `status = "executing"` (the Part whose status is `awaiting_plan_approval`; if several are gated, the lowest-integer one within `current_batch`). Do NOT set `auto_approve_planner` — that flag would silently auto-approve every remaining gate in the level, defeating "review Parts individually"; `/su-next` approves exactly one Part per invocation.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Write the full state.json back (per the state-machine invariant: always write the full file from the in-memory model, never partial-update).
5. Locate `su.md` using the lookup described below, read it, and follow its instructions for **exactly one tick** as if the orchestrator had been invoked with empty arguments. With the Part now `executing`, this tick dispatches its executer.
6. After the single re-tick, end the turn. Do NOT loop further regardless of mode.

This auto-approval intentionally bypasses the user's plan-review gate. Apply it only when `current_step` is exactly `awaiting_plan_approval`; never inject "Approve" for any state outside the two sanctioned cases (this one, and the `master_plan_approval checkpoint` branch above).

### All other eligible states

For `pending`, `scouting`, `executing`, `executed`, `verifying`:

1. Locate `su.md` using the lookup below.
2. Read it and follow its instructions for **exactly one tick**, treating this turn as if the user had typed `/su continue` (empty arguments).
3. Do NOT loop, even if `mode == "run-to"`. After the single tick, end the turn.

This branch also covers the level-boundary "Continue to level L+1?" handoff: when a level's Parts are all terminal and the user paused at the interactive level checkpoint, the next tick re-enters `su.md`'s `complete` handler. Advancing through it (performing the level transition) is exactly what selecting "Continue" would have done — `/su-next` follows that Continue branch without re-asking. This is a "next" action, not an approval bypass: no plan-review gate is skipped at a level boundary.

### Locating `su.md`

Check these paths in order:

1. Plugin install: `${CLAUDE_PLUGIN_ROOT}/commands/su.md` — resolves only when installed as a Claude Code plugin (token substituted inline before this file is read); otherwise the token is left literal and the path will not exist, so it falls through.
2. The same directory as this command file (sibling).
   - Project install: `<repo>/.claude/commands/su.md`.
   - User install: `~/.claude/commands/su.md`.
3. If no path is found, end with: "Cannot locate `su.md` — reinstall Suhail."

Do not duplicate or summarize the orchestrator logic here. The canonical state machine lives in `su.md`.

## Don't

- Do not loop. After the chosen action runs one tick, end the turn regardless of mode. Even if `mode == "run-to"`, `/su-next` advances exactly one step.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not INIT a run. If `state.json` is absent, refuse per Guard 1 — never accept a plan path.
- Do not resolve blockers, attempt retries, or mutate `blocker.md`. Refuse per Guard 3 and let the user route through `/su`.
- Do not inject an implicit approval outside the two sanctioned cases: `current_step == "awaiting_plan_approval"` (per-Part) and `run_phase == "master_plan_approval"` (batch checkpoint).
- Do not modify the state schema. The `awaiting_plan_approval` branch writes only the gated Part's `status` and `updated_at`. The `master_plan_approval checkpoint` branch writes only `batch_auto_approve`, `run_phase`, the `status` of every Part in `current_batch`, `current_part_id`, and `updated_at`.
