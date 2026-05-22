---
description: Auto-advance the current Northstar run by exactly one logical step.
---

# /ns-next — Northstar auto-stepper

You are advancing the current Northstar run by **exactly one logical step**. This command takes no arguments. It is a non-interactive shortcut for the user who wants to hit "next" without typing `/ns continue` or answering the inter-Part "Continue?" prompt.

`/ns-next` does NOT initialize a run, does NOT loop (even in `run-to` mode), and does NOT resolve blockers. It only advances one tick of the orchestrator's state machine, with a single special case: when the current step is `awaiting_plan_approval`, it injects an implicit "Approve" so the run progresses to `executing` without re-prompting the user.

## On every invocation

Run the following guards in order, short-circuiting on the first match. Each refusal is exactly one sentence and performs no file mutations.

1. **No active run.** Attempt to Read `.northstar/state.json`. If it does not exist, end with: "No active Northstar run found — run `/ns-discover` to draft a plan or `/ns <plan-path>` to initialize one."
2. **Aborted run.** Parse `state.json`. If top-level `aborted == true`, end with: "This Northstar run has been aborted — no further steps are possible."
3. **Unresolved blocker.** If `current_step == "needs_user"` OR `.northstar/parts/<current_part_id>/blocker.md` exists without a `resolution:` line, end with: "A blocker is waiting at `.northstar/parts/<current_part_id>/blocker.md` — resolve it via `/ns` before using `/ns-next`."
   - Check filesystem presence of `blocker.md` via Read or Bash `[ -f path ]` (POSIX) / `Test-Path path` (PowerShell). Both conditions are checked (OR) — the filesystem check is the authoritative safety net in case `current_step` was not updated.
4. **Run complete.** If `aborted == false` AND every entry in `state.parts` has `status` of `completed` or `skipped`, end with: "All Parts are complete — nothing left to advance."

## Dispatch

After the guards pass, branch on `current_step`:

### awaiting_plan_approval

Inject an implicit "Approve" without presenting an AskUserQuestion to the user:

1. Read `.northstar/state.json` into memory.
2. Set `auto_approve_planner = true`.
3. Update `updated_at` to the current ISO 8601 timestamp.
4. Write the full state.json back (per the state-machine invariant: always write the full file from the in-memory model, never partial-update).
5. Locate `ns.md` using the two-location lookup described below, read it, and follow its instructions for **exactly one tick** as if the orchestrator had been invoked with empty arguments. The orchestrator's `awaiting_plan_approval` branch checks `auto_approve_planner` via the planning-phase short-circuit at `ns.md` "If `auto_approve_planner == true` (run-to mode): advance to `executing`. Re-tick." — but since we are already at `awaiting_plan_approval` (past the planning phase), the equivalent transition here is the "Approve" branch: set `current_step = "executing"`, then re-tick.
6. After the single re-tick (which will dispatch the executer per the `executing` branch), end the turn. Do NOT loop further regardless of mode.

This auto-approval intentionally bypasses the user's plan-review gate. Apply it only when `current_step` is exactly `awaiting_plan_approval` — never inject "Approve" for any other state.

### All other eligible states

For `pending`, `researching`, `planning`, `executing`, `reviewing`, `auditing`:

1. Locate `ns.md` using the two-location lookup below.
2. Read it and follow its instructions for **exactly one tick**, treating this turn as if the user had typed `/ns continue` (empty arguments).
3. Do NOT loop, even if `mode == "run-to"`. After the single tick, end the turn.

This branch also covers the inter-Part "Continue to Part M?" handoff: when the orchestrator finishes a Part in interactive mode it transitions the next Part to `pending` and then ends with the AskUserQuestion. At the next invocation `current_step == "pending"`, and advancing `pending → researching` is exactly what selecting "Continue" would have done.

### Locating `ns.md`

Check these paths in order:

1. The same directory as this command file (sibling).
   - Project install: `<repo>/.claude/commands/ns.md`.
   - User install: `~/.claude/commands/ns.md`.
2. If neither path is found, end with: "Cannot locate `ns.md` — reinstall Northstar."

Do not duplicate or summarize the orchestrator logic here. The canonical state machine lives in `ns.md`.

## Don't

- Do not loop. After the chosen action runs one tick, end the turn regardless of mode. Even if `mode == "run-to"`, `/ns-next` advances exactly one step.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not INIT a run. If `state.json` is absent, refuse per Guard 1 — never accept a plan path.
- Do not resolve blockers, attempt retries, or mutate `blocker.md`. Refuse per Guard 3 and let the user route through `/ns`.
- Do not inject "Approve" for any state other than `awaiting_plan_approval`.
- Do not modify the state schema. The only field this command writes is `auto_approve_planner` (plus `updated_at`), and only in the `awaiting_plan_approval` branch.
