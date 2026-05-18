# Implement Transformational Optimizations

This plan implements the Phase 3 transformational optimizations from `plans/plan_now.md`, plus the B7 trivial-Part fast path. Together these items deliver order-of-magnitude speedups for non-interactive runs by: collapsing repeated per-tick orchestrator reboots (B12), extracting the state machine into shell (B11), batching all scout work upfront (B2), pipelining verifier and scout across Parts (B6), fast-pathing small Parts (B7), and dropping the verifier to a faster model (A5).

The changes are scoped to `agents/verifier.md`, `commands/northstar.md`, and a new pair of scripts (`scripts/northstar-tick.sh` + `scripts/northstar-tick.ps1`). No IPC contract change; `.northstar/parts/<id>/` file layout is preserved.

## Model and fast-path wins

### Part 1 — Switch verifier to Haiku model

Change the `model:` field in `agents/verifier.md` front-matter from `sonnet` to `claude-haiku-4-5-20251001`. The verifier consumes structured inputs (brief.md, execution.md, diff) and emits structured verdicts; the classification task is well within Haiku's capability.

No other changes in this Part.

**Depends on:** (none)

**Verification:**
- Manual: Install working copy (`.\scripts\install.ps1 -Project <dev-dir>\northstar -Force`), open a fresh Claude Code session, run `/ns fixtures/test_plan.md`. Confirm the verifier dispatch completes and `review.md` + `audit.md` are written correctly.
- Programmatic: Smoke test passes — `.northstar-smoketest.txt` contains `northstar smoke ok`.

### Part 2 — Add trivial-Part classifier at INIT

In `commands/northstar.md`, extend the INIT phase's Part-parsing step to classify each Part as trivial or non-trivial immediately after the parts list is built. Store `"trivial": true` (or `false`) on each entry in `state.json`'s `parts` array.

Trivial classification rules (all must hold):
- Part body < 200 words.
- No `Depends on` clause listing more than one dependency (or none at all).
- No `## Verification` block containing a `Programmatic:` command.
- Title verb is one of: Update, Rename, Move, Add, Remove, Fix, Bump, Change.
- Body names ≤ 2 distinct file paths.

Narrate classification result at INIT: "Part N classified as trivial — fast path will apply." for each trivial Part.

**Depends on:** (none)

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md`; confirm INIT narration does not crash and `state.json` has a `trivial` field on each Part entry.
- Programmatic: Smoke test passes.

### Part 3 — Wire trivial-Part fast path in orchestrator

In `commands/northstar.md`, modify the scouting and verifying phases to branch on `parts[N].trivial`:

- **Scout:** if `trivial == true`, skip the scout Agent dispatch entirely. Instead, write a minimal `brief.md` inline: echo the Part body as the brief, mark `## Steps` as "Apply the Part body directly." Narrate: "Part N is trivial — skipping scout."
- **Verifier:** if `trivial == true`, skip the verifier Agent dispatch. Instead, run the orchestrator-side regex audit heuristic (same pattern table used for A3) against the diff. Write a synthetic `review.md` (verdict: `approved`, summary: "Trivial Part — fast-path review.") and `audit.md` (verdict: `clean`, summary: "Trivial Part — regex audit only."). Narrate: "Part N is trivial — skipping verifier, regex audit passed/flagged."
- If the regex audit finds a hit, fall back to a full verifier dispatch rather than blocking.

**Depends on:** Part 2

**Verification:**
- Manual: Install and run `/ns fixtures/test_plan.md`. If no Parts in that fixture are trivial, temporarily add a one-line trivial Part to the fixture, confirm the fast path fires and produces correct artifacts, then remove it.
- Programmatic: Smoke test passes.

## Parallel and pipelined execution

### Part 4 — Implement batch INIT parallel scout dispatch

In `commands/northstar.md`, replace the single-Part INIT scout dispatch with a batch mode:

1. At INIT, compute the DAG dependency levels (level 0 = no deps, level 1 = depends only on level-0 Parts, etc.).
2. Dispatch scouts for all level-0 Parts in one assistant turn (multiple `Agent(...)` calls in parallel). Write each Part's `brief.md` to its own `.northstar/parts/part-N/` directory as today.
3. After all level-0 briefs are written and verified, present a single consolidated master-plan approval to the user. The approval message lists all Parts with their one-line brief summaries.
4. On approval, proceed to execution starting from the first eligible Part as today.
5. Level-1+ Parts: scout them in the batch dispatch immediately after their dependencies complete (not one-by-one at execution time). This can be done speculatively during execution of level-0 Parts if `state.speculative` is not already occupied.

Add a new state field `"batch_scouted_levels": []` to track which DAG levels have had their scouts dispatched.

Preserve backward compatibility: if the plan has only one Part, behaviour is identical to today.

**Depends on:** (none)

**Verification:**
- Manual: Run a multi-Part fixture (e.g. `fixtures/test_plan.md` if it has ≥ 2 Parts, or create a two-Part fixture). Confirm a single approval gate appears instead of per-Part approval prompts.
- Programmatic: Smoke test passes; `state.json` contains `batch_scouted_levels`.

### Part 5 — Add pipelined verifier and scout execution

In `commands/northstar.md`, during the `verifying` phase for Part N in auto-advance mode (`batch_auto_approve == true` OR `mode == "run-to"`):

1. Identify the next eligible Part M (first Part whose dependencies are all completed/skipped and whose `brief.md` does not yet exist).
2. If M exists: issue the scout Agent dispatch for Part M **in the same assistant turn** as the verifier Agent dispatch for Part N (two parallel Agent calls).
3. Update `state.speculative` as today (`{ "part_id": "part-M", "origin": "B6" }`).
4. On verifier return: adopt or discard the speculative brief per the existing Adopt/Discard rules.

This builds on the existing speculative dispatch infrastructure (B5/B6 already partially present in the orchestrator); the change is to ensure the scout for Part M is always co-dispatched with the verifier for Part N rather than only in specific branches.

**Depends on:** Part 4

**Verification:**
- Manual: Run a 3-Part sequential fixture in auto-advance mode. Observe narration shows verifier and scout running in parallel for Parts 1→2 and 2→3 transitions.
- Programmatic: Smoke test passes.

## Shell state machine

### Part 6 — Write northstar-tick.sh (POSIX)

Create `scripts/northstar-tick.sh`. This script reads `state.json` (path passed as `$1`) and emits a single-line JSON directive to stdout. It does not mutate any file; it only reads state and prints what the orchestrator should do next.

Output format (one JSON object per run):

```json
{ "action": "dispatch_scout", "part_id": "part-2", "brief_path": ".northstar/parts/part-2/brief.md" }
{ "action": "dispatch_executer", "part_id": "part-2", "brief_path": "..." }
{ "action": "dispatch_verifier", "part_id": "part-2", "execution_path": "..." }
{ "action": "ask_user", "question": "Part 2 complete. Continue?", "options": ["Continue", "Pause", "Abort"] }
{ "action": "complete", "message": "All Parts done." }
{ "action": "blocked", "reason": "...", "part_id": "part-2" }
```

The script encodes the state-transition table: given `current_phase`, `current_part_id`, artifact presence, and `batch_auto_approve`, it returns the next action. No LLM involved.

Cover all phases: `init`, `scouting`, `executing`, `verifying`, `awaiting_part_approval`, `complete`, `needs_user`.

Include a `--help` flag and exit-code contract: 0 = directive emitted, 1 = state.json missing or unparseable, 2 = unknown phase.

**Depends on:** (none)

**Verification:**
- Manual: Run `bash scripts/northstar-tick.sh .northstar/state.json` against a real state file from a prior fixture run. Confirm the output is valid JSON matching the expected action for the current phase.
- Programmatic: `bash scripts/northstar-tick.sh --help` exits 0; `bash scripts/northstar-tick.sh /nonexistent` exits 1.

### Part 7 — Write northstar-tick.ps1 (PowerShell)

Create `scripts/northstar-tick.ps1`. Identical interface and output contract to `northstar-tick.sh` (Part 6) but implemented in PowerShell 7+. Uses `Get-Content | ConvertFrom-Json` to read state, `ConvertTo-Json -Compress` to emit the directive.

Parameter: `-StatePath <path>` (positional $args[0] also accepted for parity with the POSIX script).

Exit codes and output format are identical to Part 6.

**Depends on:** Part 6

**Verification:**
- Manual: `pwsh scripts/northstar-tick.ps1 .northstar/state.json` against a real state file produces the same directive as the POSIX version.
- Programmatic: `pwsh scripts/northstar-tick.ps1 --help` exits 0.

### Part 8 — Wire orchestrator to use tick scripts

Refactor `commands/northstar.md` to delegate state-transition decisions to the tick scripts:

1. Each orchestrator tick: run `bash scripts/northstar-tick.sh .northstar/state.json` (POSIX) or `pwsh scripts/northstar-tick.ps1 .northstar/state.json` (Windows) via Bash tool.
2. Parse the returned JSON directive.
3. Act on the directive: dispatch the named Agent, ask the named question, or emit the completion/blocked message.
4. Write the updated `state.json` (phase transitions, status updates) after acting, as today.

The orchestrator's state-machine prose shrinks to: "run tick script → act on directive → update state → narrate." Remove the inline phase-transition logic that is now encoded in the scripts.

Target: `commands/northstar.md` drops from its current size to ≤ 150 lines of orchestrator prose (excluding the Project intel block and format spec comments).

**Depends on:** Part 6, Part 7

**Verification:**
- Manual: Install and run `/ns fixtures/test_plan.md` end-to-end. All artifacts produced; smoke test passes. Confirm `commands/northstar.md` is visibly shorter.
- Programmatic: Smoke test passes; `wc -l commands/northstar.md` (or PowerShell equivalent) reports ≤ 150 lines of non-comment prose.

## Autorun mode

### Part 9 — Add /ns autorun mode

Add an `autorun` invocation path to `commands/northstar.md` (and the thin `commands/ns.md` pointer). When the user runs `/ns autorun <plan-path>`:

1. INIT proceeds as normal (parse Parts, batch scout per Part 4, single approval).
2. After approval, the orchestrator executes multiple ticks within the **same assistant turn** without ending the turn between Parts. It calls the tick script, dispatches the indicated Agent, updates state, and immediately calls the tick script again — looping until:
   - A `ask_user` directive is returned (blocker or manual-approval point), or
   - An `action: complete` directive is returned, or
   - A safety cap of 10 Parts is hit (narrate: "Autorun safety cap reached — use `/ns continue` to proceed.").
3. The per-Part completion `AskUserQuestion` is suppressed in autorun mode; the orchestrator auto-advances on `approved` verdicts.
4. Add `"mode": "autorun"` to `state.json` so `/ns continue` knows to stay in autorun after a blocker is resolved.

Narration discipline is unchanged: one sentence per dispatch event.

**Depends on:** Part 8

**Verification:**
- Manual: Run `/ns autorun fixtures/test_plan.md`. Confirm the fixture completes without any per-Part user prompts, producing correct artifacts and `.northstar-smoketest.txt`.
- Programmatic: Smoke test passes in autorun mode.

## Open questions

- **B6 overlap with existing speculative dispatch:** The orchestrator already contains partial B5/B6 speculative scout logic (lines referencing `state.speculative` and `B6 pipelined dispatch`). Part 5 should audit what is already implemented and extend or replace as needed rather than duplicating. The scout for Part 5 should read `commands/northstar.md` carefully before drafting steps.
- **B11 tick script scope:** The tick scripts encode the state-transition table. If the orchestrator state schema evolves in a future release, both scripts must be updated in sync. Consider adding a schema version field to the tick script output for forward compatibility.
- **B12 autorun and context length:** Multi-Part autorun in one turn accumulates context across all dispatches. On large plans the context may fill before the safety cap is hit. A future improvement could checkpoint state and surface a "context near limit — pausing autorun" message.
