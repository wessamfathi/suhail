# Parallelize verifier across in-flight Parts

Currently, when Northstar executes a batch of same-level Parts, it processes them one at a time: execute Part N → verify Part N → execute Part N+1 → verify Part N+1. This is unnecessarily serial at the verification stage. Because verifiers are read-only (they consume pre-captured `.patch` files and write per-Part `review.md`/`audit.md`) they can safely run in parallel once all executers in the batch have finished.

This plan adds a **batch-verify phase**: after all Parts in `current_batch` have been executed serially, Northstar dispatches all their verifiers in one parallel call — mirroring how `start_batch_scouting` already parallelises scouts. Executers remain strictly serial (file-conflict risk unchanged). A new fixture (or fixture extension) exercises the parallel path explicitly.

## Core changes

### Part 1 — Extend state schema and define batch-verify phase

Update `commands/northstar.md`:

- Add `"batch_verifying"` to the `run_phase` value list in the State schema section. Add a new optional field `"parts_pending_verification": []` — a list of Part IDs that have finished executing but whose verifiers have not yet been dispatched in this batch cycle. This field is set to `[]` at INIT and cleared when the batch-verify dispatch completes.
- Add an intermediate per-Part status `"executed"` between `"executing"` and `"verifying"` in the `run_phase` values comment line (`pending → scouting → awaiting_plan_approval → executing → executed → verifying → needs_user → completed | skipped`). This lets the orchestrator distinguish "executer finished, verifier not yet dispatched" from "verifier in flight".
- Update the `Don't` rule that currently reads "Don't call subagents in parallel except: (1) `batch_scouting` per-level scouts, (2) B6 pipelined verifier+scout in auto-advance mode. Executers are strictly serial." — extend exception (1) to also permit parallel verifier dispatches during `batch_verifying`.
- Update the STATUS.md generation section: add `batch_verifying` to the `<CURRENT_LINE>` mapping (pattern: `verifying batch [part-a, ...] (level L)`).

**Depends on:** (none)

**Verification:**
- Manual: read `commands/northstar.md` and confirm `batch_verifying` appears in run_phase values, `parts_pending_verification` in state schema, `executed` in the per-Part status chain, and the `Don't` rule and STATUS template are updated.
- Programmatic: `grep -c "batch_verifying\|parts_pending_verification\|executed" commands/northstar.md` — expect at least 4 hits.

### Part 2 — Implement batch verifier dispatch and verdict aggregation

Update `commands/northstar.md` — three handler changes:

**`dispatch_executer` (change):** After output verification and updating `parts[N].files_changed`, instead of setting status to `verifying` and re-ticking, set status to `"executed"` and append `part-N` to `state.parts_pending_verification`. Write `state.json`. Re-tick. The tick script should then either dispatch the next executer in the batch (if any remain with status `executing`-eligible) or, when every Part in `current_batch` has status `executed`, emit action `start_batch_verifying`.

**`start_batch_verifying` (new handler):** Mirror the shape of `start_batch_scouting`.

1. For each Part in `parts_pending_verification` (integer-sorted): run the diff capture step currently at the top of `dispatch_verifier` — `git add -N`, compute patch, write `diff-attempt-K.patch`. (Trivial fast path: apply inline regex audit as today; if clean, write inline `review.md`/`audit.md`, mark `completed`, exclude from parallel dispatch.)
2. Emit all verifier `Agent(...)` calls in one assistant turn for the non-trivial Parts. Set each Part's status to `"verifying"`. Set `run_phase = "batch_verifying"`. Clear `parts_pending_verification = []`. Write `state.json`. Narrate: "Verifying level L — dispatching M verifiers in parallel: Part a, Part b, …"
3. After all return: apply output verification per Part (check `review.md`, `audit.md`, sentinels). On any failure → write `blocker.md` for that Part, set its status `needs_user`. Do NOT block siblings whose verification succeeded.
4. For each Part: parse `## Verdict` worst-of; if `blockers` and `attempts < max_retries` → reset to `executing`, increment `attempts`; if `blockers` and exhausted → `needs_user`. Otherwise → `completed`.
5. Write `state.json`. Re-tick (the tick script will then handle level transition or run completion as today).

**`dispatch_verifier` (simplify):** The diff-capture step moves into `start_batch_verifying`. The remaining handler is now only reached for single-Part levels or retry dispatches (where batch_verifying is not in play). Keep it intact for those cases.

**Depends on:** Part 1

**Verification:**
- Manual: run `/ns fixtures/test_plan.md` (or the new fixture from Part 3). Confirm that once both level-1 Parts finish executing, STATUS.md shows `verifying batch [part-2, part-3] (level 1)` before either verifier returns, and both `review.md` and `audit.md` are written for each Part.
- Programmatic: `grep -c "start_batch_verifying\|parts_pending_verification\|batch_verifying" commands/northstar.md` — expect at least 6 hits.

### Part 3 — Add parallel-verifier fixture and bump version

**Fixture:** Create `fixtures/parallel-verifier-plan.md` — a plan with at least two same-level Parts (level 1, both depending on a shared level-0 Part). The fixture's header comment should document the expected behavior: both level-1 Parts execute serially, then both verifiers fire in parallel, both complete, run finishes. Keep the Parts trivially simple (append lines to test files, similar to `fixtures/test_plan.md`) so the fixture exercises orchestrator logic rather than real code changes.

**Version bump (v0.7.0 → v0.8.0):** Update the three canonical locations:
1. `commands/northstar.md` — H1 heading and `tool_version` field in state schema block and STATUS.md template header.
2. `README.md` — footer line.
3. `CHANGELOG.md` — new `## [0.8.0] — <today's date>` section describing the parallel verifier feature.

**Depends on:** Part 2

**Verification:**
- Manual: `/ns fixtures/parallel-verifier-plan.md` → walk through until both level-1 verifiers return → confirm STATUS.md shows both completed.
- Programmatic: `grep -rn "v0.8.0" commands/northstar.md README.md CHANGELOG.md` — expect a hit in each file.

## Open questions

- **Retry interaction:** if one Part in a batch-verify cycle hits `blockers` and is reset to `executing`, should it re-enter the *next* batch-verify cycle with remaining siblings, or be verified immediately after its retry execution? The plan defers this to the executer: on retry the Part goes back through `dispatch_executer` alone, which re-ticks to `dispatch_verifier` (single-Part path) rather than waiting for a new batch.
- **B6 speculative during batch_verifying:** the current B6 speculative-scout logic fires inside `dispatch_verifier`. It should be moved/replicated into `start_batch_verifying` so speculative scouting of the next level still happens in parallel with batch verification.
