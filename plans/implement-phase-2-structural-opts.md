# Implement Phase 2 structural optimizations

This plan implements the B-series structural optimizations from `plans/plan_now.md`, specifically B1, B2, B5, B6, B9, B13, and B17. The goal is to collapse five role agents into three (scout, executer, verifier), eliminate redundant file reads by inlining intel at INIT, parallelize research+plan dispatch across all Parts upfront, pipeline the next Part's scout during the current verifier phase, and trim all role prompt files aggressively.

Success: a Northstar run against `fixtures/test_plan.md` completes end-to-end, the per-Part dispatch count drops from 5 to 3, and the master plan approval happens once (not once per Part).

Reference analysis doc: `plans/plan_now.md` §§ B1, B2, B5, B6, B9, B13, B17.

## Phase 2a — New role agents

### Part 1 — Create scout agent

Create `agents/scout.md` as a merged researcher + planner role. The scout is a single subagent dispatch that:

- Reads the project intel files (`stack.md`, `layout.md`, `conventions.md`, `modules.md`) as primary grounding — skip re-deriving stack conventions if intel is present (the fix from A2 applies here).
- Performs targeted codebase exploration for the current Part (files to touch, helpers to reuse, gotchas).
- Drafts a concrete step list for the executer.
- Writes ONE artifact: `brief.md` under `.northstar/parts/<id>/`. The brief must contain two clearly separated sections: `## Research` (what is in the codebase) and `## Plan` (what to change, ordered steps). The executer and verifier read this single file.

The split between researcher and planner today exists only for context discipline within an agent; a single agent can produce both artifacts in one pass without quality loss (B17). The scout's `## Plan` section replaces `plan.md`; the `## Research` section replaces `research.md`. No separate `research.md` or `plan.md` files are written.

Agent file conventions to follow: YAML frontmatter with `model: claude-sonnet-4-6`, H2 sections (`## Input`, `## Process`, `## Output`, `## Blocker protocol`, `## Don't`), write-or-block contract on output.

**Depends on:** (none)

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md`, advance through INIT. Confirm that `.northstar/parts/part-1/brief.md` is created with both `## Research` and `## Plan` sections, and no `research.md` or `plan.md` are created. Confirm the run advances to the executer phase.
- Programmatic: `grep -l "## Research" .northstar/parts/*/brief.md && grep -l "## Plan" .northstar/parts/*/brief.md`

### Part 2 — Create verifier agent

Create `agents/verifier.md` as a merged reviewer + security-auditor role. The verifier is a single subagent dispatch that:

- Reads `brief.md` (the scout's output), the git diff for the current Part, and `execution.md`.
- Runs the reviewer checklist as Pass 1: plan conformance, regressions, repo conventions. Writes verdict to `review.md`.
- Runs the security-auditor checklist as Pass 2: auth, authorization, data access, secrets, injection, input validation. Writes verdict to `audit.md`.
- Independence is preserved at the artifact and pass level — the two checklists run sequentially inside one context with explicit "do not cross-contaminate" guards in the prompt. Pass 1 output is written to disk before Pass 2 begins.

Both `review.md` and `audit.md` must be written (write-or-block contract applies to both). Verdict format is identical to today's individual agents: `Verdict: clean | concerns | blockers`, `Summary:`, `Issues:` list.

Agent file conventions: same as Part 1 (YAML frontmatter, H2 sections, write-or-block).

**Depends on:** (none)

**Verification:**
- Manual: After Part 1 is wired in (Part 3), run `/ns fixtures/test_plan.md` end-to-end. Confirm both `review.md` and `audit.md` appear under `.northstar/parts/part-1/` with correct verdict structure.
- Programmatic: `grep "Verdict:" .northstar/parts/part-1/review.md && grep "Verdict:" .northstar/parts/part-1/audit.md`

## Phase 2b — Orchestrator wiring

### Part 3 — Wire scout and verifier into the orchestrator state machine

Update `commands/northstar.md` to replace the four-role dispatch sequence with scout + verifier:

- Replace the `researching` + `planning` phases with a single `scouting` phase that dispatches `agents/scout.md`. The dispatch prompt passes: the Part's body, the Part id, the path to the parts directory. It reads `brief.md` on return.
- Replace the `reviewing` + `auditing` phases with a single `verifying` phase that dispatches `agents/verifier.md`. The dispatch prompt passes: `brief.md` path, git diff, `execution.md` path.
- Update plan-approval logic: the orchestrator now reads `brief.md`'s `## Plan` section (not a separate `plan.md`) to present the plan to the user for approval.
- Update output verification (the post-dispatch checks at `commands/northstar.md:108-128`): check for `brief.md` after scout, check for both `review.md` and `audit.md` after verifier.
- Update STATUS.md template to reflect the new phases (scouting, executing, verifying instead of researching, planning, executing, reviewing, auditing).
- Update the "Don't call subagents in parallel" rule to: "Serial except for the independent reviewer/auditor checklists inside the verifier — the verifier itself is one dispatch."
- The `tool_version` in the heading should be bumped to the next minor version.

**Depends on:** Part 1, Part 2

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md` from INIT through at least one complete Part cycle. Confirm the status phases shown are `scouting → executing → verifying`, `brief.md` is produced, and both `review.md` + `audit.md` are written.
- Programmatic: `grep "scouting\|verifying" .northstar/state.json` (should appear as valid phase names after a run).

### Part 4 — Inline project intel into subagent dispatch prompts (B13)

Update `commands/northstar.md` so the orchestrator reads the four intel files once at INIT (after parsing the plan, before the first user question) and caches their contents in memory for the session.

For every subagent dispatch (scout and verifier), prepend a `## Project intel (from /ns-init)` block to the dispatch prompt containing the cached contents of `stack.md`, `layout.md`, `conventions.md`, and `modules.md`. The subagent agent files (`agents/scout.md`, `agents/verifier.md`, `agents/executer.md`) should be updated to: (a) check whether the inline intel block is present in the prompt, and (b) if present, skip the Read calls for intel files entirely.

For large intel files (unlikely given these are ~1–2KB summaries), keep path-passing as fallback. Small artifacts (Part body, intel) are inlined; large artifacts (brief.md up to 400 lines) remain path-passed.

The intel read happens once per `/ns` invocation, not per Part, not per tick.

**Depends on:** Part 3

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md`. Observe that the scout dispatch does not Read any `.northstar/intel/` files (the inline block substitutes). Confirm the run still completes correctly.
- Programmatic: Search the transcript/tool calls for Read calls to `.northstar/intel/` during scout dispatch — there should be none.

### Part 5 — Batch INIT with parallel scout dispatch (B2)

Restructure the INIT phase in `commands/northstar.md`:

1. After parsing all Parts from the plan file, compute the DAG dependency levels (level 0 = no deps, level 1 = deps only on level-0 Parts, etc.).
2. Dispatch **all level-0 scouts in parallel** (one Agent message with multiple tool calls — this is an explicit exception to the serial subagent rule, gated on read-only scouts). Wait for all to return and verify their `brief.md` outputs.
3. Present a **consolidated master plan** to the user: one AskUserQuestion showing all Parts' `## Plan` sections in sequence. This replaces the per-Part plan-approval gate.
4. ONE approval covers the whole plan. User options: "Approve all and start executing", "Approve and review Parts individually" (falls back to current behavior), "Abort".
5. After level-0 Parts execute and complete, dispatch level-1 scouts in parallel before those Parts execute, and so on.

State machine changes needed: new `batch_scouting` phase at INIT; `master_plan_approval` state; per-level batch dispatch logic.

**Depends on:** Part 1, Part 3

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md`. Confirm that all Part scouts complete before the first user approval question, that the approval question shows all Parts' plans, and that execution begins after one user confirmation.
- Programmatic: Check that multiple `brief.md` files exist in `.northstar/parts/` before the first approval question is answered.

### Part 6 — Speculative pre-research and pipeline (B5 + B6)

Add two background-dispatch optimizations to `commands/northstar.md`:

**B5 — Speculative scout during user pauses:** Before raising the master plan approval question (Part 5's gate) or any part-completion question, dispatch the next eligible Part's scout with `run_in_background: true`. By the time the user answers, `brief.md` is already on disk for the next Part. If the user picks Skip or Abort, rename speculative artifacts to `*.speculative.md` and skip reading them.

**B6 — Pipelined verifier + next scout:** In auto-advance mode (when the user selected "Approve all and start executing" from Part 5), after the executer finishes Part N, start the verifier for Part N and the scout for Part N+1 simultaneously (parallel dispatch). Wall-clock per Part drops to `max(verifier, scout)` instead of `verifier + scout`. If the verifier flags a blocker and triggers re-execution, drop the speculative Part N+1 scout artifacts.

Both B5 and B6 must gate on whether a next eligible Part exists (no speculative dispatch on the last Part or when all remaining Parts have unsatisfied deps).

**Depends on:** Part 3, Part 5

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md` with auto-advance. Confirm that `brief.md` for Part 2 exists before Part 1's verifier finishes (B6 pipelining), and that Part 2's scout was dispatched in the background during the Part 1 completion question if any (B5).
- Programmatic: Timestamps on `brief.md` files — Part 2's `brief.md` mtime should be before Part 1's `review.md` mtime.

## Phase 2c — Cleanup

### Part 7 — Delete superseded agent files

Delete the four agent files replaced by scout and verifier:
- `agents/researcher.md`
- `agents/planner.md`
- `agents/reviewer.md`
- `agents/security-auditor.md`

Search the codebase for any references to these filenames (in `commands/northstar.md`, `docs/`, `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`) and update them to reference `agents/scout.md` and `agents/verifier.md` instead.

Update `docs/architecture.md` and `docs/extending.md` to reflect the new 3-agent pipeline. Update `README.md` slash-command reference if it names the agent files.

**Depends on:** Part 1, Part 2, Part 3

**Verification:**
- Manual: Confirm the four files are gone. Run `grep -r "researcher\|planner\|reviewer\|security-auditor" agents/ commands/ docs/ README.md` — expect no hits (or only historical CHANGELOG references).
- Programmatic: `ls agents/` — should show only `executer.md`, `indexer.md`, `scout.md`, `verifier.md`.

### Part 8 — Trim all role prompt files (B9)

Aggressively cut all agent and orchestrator files toward the target line counts from `plans/plan_now.md §B9`:

| File | Current lines | Target |
|---|---|---|
| `commands/northstar.md` | ~357 (will have grown from Parts 3–6) | ~220 |
| `agents/scout.md` | new (merged researcher+planner ~152+114=266) | ~120 |
| `agents/verifier.md` | new (merged reviewer+auditor ~94+113=207) | ~100 |
| `agents/executer.md` | 113 | ~70 |
| `agents/indexer.md` | 185 | ~110 |

Trimming principles (from B9 analysis):
- Remove "Don't" rules that merely restate the write-or-block contract already enforced by the orchestrator's output verification.
- Keep "Don't" rules that have prevented real failures (e.g. "do not print body in chat instead of writing to disk").
- Remove illustrative output bodies in Output sections — keep the structure, drop the example content.
- Collapse Severity guidance to one concrete example per level; drop meta-commentary.
- Remove redundant cross-references ("see also researcher.md" — the referenced file is now gone).

**Depends on:** Part 1, Part 2, Part 3, Part 7

**Verification:**
- Manual: Run `wc -l agents/scout.md agents/verifier.md agents/executer.md agents/indexer.md commands/northstar.md` and confirm line counts are within 10% of targets. Run `/ns fixtures/test_plan.md` end-to-end to confirm trimming did not remove load-bearing instructions.
- Programmatic: End-to-end fixture run produces all expected artifacts without blocker verdicts.

## Critical files reference

- `commands/northstar.md` — orchestrator state machine (Parts 3, 4, 5, 6, 8)
- `agents/researcher.md` — to be superseded by scout (Part 1)
- `agents/planner.md` — to be superseded by scout (Part 1)
- `agents/reviewer.md` — to be superseded by verifier (Part 2)
- `agents/security-auditor.md` — to be superseded by verifier (Part 2)
- `agents/executer.md` — updated to consume inline intel block (Part 4)
- `agents/indexer.md` — trimmed (Part 8)
- `docs/architecture.md`, `docs/extending.md` — updated to reflect 3-agent pipeline (Part 7)
- `fixtures/test_plan.md` — primary smoke test vehicle throughout

## Open questions

1. **B2 + DAG levels:** The batch INIT logic batches scouts by DAG level. If a plan has no level-0 Parts (a cycle, or a plan with universal deps), the batch dispatch falls back to single-Part serial. The researcher should confirm no fixture plan triggers this edge case.
2. **Version bump:** Parts 3 and 8 both touch `commands/northstar.md`. The version should be bumped once after Part 8 (the final state). Confirm with user whether to bump at Part 3 (first wiring) or Part 8 (final trim). Default: bump at Part 3 (first working state), then update again at Part 8 if needed.
3. **`agents/ns-next.md` or similar:** Check whether any other command files (e.g. `commands/ns-next.md`) dispatch researcher/planner/reviewer/auditor by name — if so, Part 7 must also update those files.
