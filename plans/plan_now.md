# Northstar performance optimization plan

This document captures (A) the findings from the initial scan of `commands/northstar.md` and `agents/*.md`, and (B) a set of more ambitious, structural optimizations uncovered on a deeper second pass. It is an analysis document, not a Northstar-format executable plan — though several items below are concrete enough to lift into one.

---

## Part A — Conservative findings (initial scan)

These are low-risk wins that do not change the core architectural contract (file-based IPC, role separation, write-or-block, output verification).

### A1. Reviewer + security-auditor run serially despite being declared independent

`commands/northstar.md:208-239` runs `executing → reviewing → auditing` as two separate phases. Each is a full subagent dispatch: fresh context, re-read of research+plan+diff+execution+changed files, write its own artifact.

`agents/reviewer.md:8` and `agents/security-auditor.md:8` both explicitly state the roles are independent and must not coordinate. They share inputs and produce structurally identical verdicts. Serial execution is the single biggest avoidable cost per Part.

**Fix:** collapse `reviewing` + `auditing` into one phase that dispatches both in parallel (one Agent message with two tool calls). Unify verdicts (worst-of: any `blockers` → re-execute; else advance).

Caveat: `commands/northstar.md:354` says "Don't call subagents in parallel." That rule exists to enforce researcher → planner → executer dependency. Loosen it to "serial except for the independent reviewer/auditor pair."

**Expected win:** ~30–40% of per-Part wall-clock.

### A2. Researcher re-discovers the stack every Part even though intel exists

`agents/researcher.md:42-56`. Step 0 mandates reading intel "to skip re-deriving stack, build/test/lint, conventions." Step 1 then orders "Discover stack conventions" and lists CLAUDE.md, AGENTS.md, `.cursorrules`, README, every manifest (root + nested), tsconfig, eslint, prettier, ruff, editorconfig, rustfmt, test configs.

The model resolves the contradiction by reading everything. Across 10 Parts that's ~40+ redundant file reads on the critical path.

**Fix:** rewrite step 1 as conditional — "If `intel/stack.md` is present and not blocked, skip step 1 entirely. Only inspect sub-package manifests when the Part touches a sub-package intel did not list."

**Expected win:** ~15–20% per researcher dispatch.

### A3. Security-auditor is dispatched even on diffs with no security surface

`agents/security-auditor.md:96-111`. The auditor knows to short-circuit to `clean — no security surface` on UI/comment/doc/test diffs, but getting there still costs a full subagent: fresh context, read research+plan+diff+execution+all changed files, write audit.md.

**Fix:** orchestrator-side heuristic. If every changed path matches a no-surface pattern (`*.md`, `*.css`, `*.scss`, `tests/`, `__tests__/`, `*.test.*`, `*.spec.*`, `*.snap`, asset extensions), synthesize `audit.md` with `Verdict: clean` and `Summary: No security-relevant surface (orchestrator heuristic).` and skip the dispatch.

**Expected win:** ~15–25% on doc/UI-heavy Parts.

### A4. Per-Part interactive approval pause is on the critical path

`commands/northstar.md:176` (`awaiting_plan_approval`) and the part-completion question at `:251` each require a user turn. Wall-clock per Part is dominated by user response time, not model time.

**Fix:** add an "Approve and auto-advance until next blocker" option to both AskUserQuestions. Equivalent to flipping `mode = "run-to"` with the run-to target set to the last Part. Cost: nothing structural; promotes an existing capability into the default question UI.

### A5. Model asymmetry

`agents/executer.md:5` uses `model: opus`. Everyone else is `sonnet`. Opus is correct for executer (writes code). But:

- Reviewer/auditor on **Haiku 4.5** would be substantially faster. They consume structured inputs and emit structured verdicts. The classification task is well within Haiku's range.
- Researcher/planner staying on Sonnet is appropriate — they do open-ended exploration.

Tradeoff: Haiku may produce more false negatives on subtle issues. Worth a measured A/B against fixtures before committing.

### A6. Reviewer is given more context than it needs

`commands/northstar.md:215-228` hands reviewer the full research.md, full plan.md, full diff, full execution.md, and all changed files at HEAD. `agents/reviewer.md:42` only needs the `Stack conventions`, `Gotchas`, and `Patterns to follow` sections from research and the `## Steps` from plan.

**Fix:** trim reviewer's input bundle to the sections it actually uses. Faster prompt processing per dispatch.

**Expected win:** ~5–10% per reviewer dispatch.

### A7. Slash-command preamble re-parsed every `/ns continue`

`commands/northstar.md` is ~21KB and is injected into the top-level session each invocation. Across many ticks of one run, the orchestrator re-reads the same state machine spec. This is a Claude Code architectural constant, but it argues against making the orchestrator longer. Recent additions (output verification, write-or-block) have already grown it ~30% since v0.1.0.

### A8. Minor: state.json full-rewrite per mutation and SHA check per tick

`commands/northstar.md:97` mandates full file rewrite each tick; `:45-48` recomputes the plan SHA each invocation. Cheap individually but contribute a few hundred ms per tick. Not worth changing in isolation.

---

## Part B — Drastic optimizations (ambitious second pass)

The deeper question: which design decisions, taken for sound reasons, are now the dominant cost? The answer is **per-Part serialization of 5 fresh-context dispatches plus 2 user gates**. Every drastic optimization below relaxes one of those constraints.

### B1. Role collapse: 5 agents → 3 (or 2)

The pipeline today: researcher → planner → executer → reviewer → security-auditor. Five fresh-context dispatches per Part, each paying cold-start cost.

Collapse to:
- **Scout** = researcher + planner. One dispatch produces both `research.md` and `plan.md`. The split exists today only for context discipline within an agent; a single agent can produce two artifacts in one pass with no quality loss.
- **Executer** unchanged.
- **Verifier** = reviewer + security-auditor. Two checklists, two artifacts (review.md + audit.md), one dispatch. The independence rule is preserved at the artifact level — the verifier runs both checklists in one context and writes both files.

**Result:** 5 dispatches → 3 dispatches per Part. ~40% reduction in cold-start overhead. Per-dispatch token cost grows modestly because the merged agent has a larger system prompt, but cold-start dominates.

**Risk:** verifier's two checklists may bleed into each other (reviewer accidentally adopting security framing or vice versa). Mitigation: structure the verifier's output requirement as TWO independent passes inside one context, written separately, with explicit "do not duplicate" guards. This is exactly what reviewer+auditor agent files say today.

**Even more drastic:** when intel is present and the Part has explicit file paths in its body, skip scout entirely → **2 dispatches per Part** (executer + verifier).

### B2. Batch INIT: research and plan all Parts upfront, single approval gate

Today INIT runs the researcher for Part 1 only, after the user clicks "Continue". The user then sees N plan-approval gates (one per Part) and N part-completion gates.

Drastic alternative: at INIT, after parsing Parts, dispatch **all N researchers in parallel** (read-only, independent outputs to separate `part-N/` directories). Once complete, dispatch **all N planners in parallel** (each reads its own research.md, no inter-Part communication). Present one consolidated master plan to the user. ONE approval gate covers the whole plan.

Then execute serially with the merged verifier per Part (or pipelined per B6).

**Result:**
- Wall-clock for research+plan phase: max(individual times) instead of sum.
- User round-trips: 1 (master approval) + N (per-Part completion) instead of 2N. With the "auto-advance until blocker" option from A4, drops to ~1.
- Total user touchpoints per plan: from 2N to ~2.

**Risk:** Parts with `Depends on Part M` may need M's executed state to research properly. Mitigation: split into batches by DAG level. Level-0 Parts (no deps) batch together; level-1 Parts batch after level-0 executions complete.

### B3. DAG-parallel execution via git worktrees

The plan format encodes a dependency DAG. Most plans contain independent Parts that touch different files. They could be executed in parallel.

Architecture:
- Compute the DAG at INIT.
- For each independent group, create a `git worktree` per Part.
- Run executer + verifier per Part in its own worktree, concurrently.
- Merge into main branch at level boundaries.
- Conflict detection: pre-flight which files each Part will touch (from research.md's `## Files to touch`). If two parallel candidates share files, they fall back to serial.

**Result:** for plans with K-wide independent levels, wall-clock drops to ~1/K of serial. Combined with B1 and B2 the speedup compounds dramatically.

**Risk:** major architectural shift. State machine becomes multi-Part. Merge conflicts at level boundaries need handling. Orchestrator's "one short sentence per event" narration discipline gets harder to preserve.

**Mitigation:** opt-in flag (`--parallel`). Default stays serial.

### B4. Static-scan auditor with LLM escalation

Most security-auditor dispatches return `clean` (most diffs touch no security surface). Each is a full LLM dispatch costing seconds.

Replace with:
- A `northstar-audit-scan.sh` or inline Bash regex pass that searches the diff for: `eval(`, `child_process`, raw SQL concat, `dangerouslySetInnerHTML`, hardcoded secrets, `process.env` introductions, deep-link routing, file-path concat from input, etc.
- If ZERO hits → write a synthetic `audit.md` with `Verdict: clean`. No LLM dispatch.
- If ANY hits → dispatch the LLM auditor with the hits pre-extracted as a focused checklist.

**Result:** the LLM auditor runs only on diffs that have actual surface. For most Parts: zero auditor dispatch. For risky Parts: shorter dispatch because the scan has already localized the work.

**Risk:** false negatives — the static scan misses a class of issue the LLM would catch. Mitigation: the regex set should be a living document, tuned by experience. Also: keep "full LLM audit" as an opt-in flag for high-stakes Parts (the planner could mark a Part `audit: strict` if it touches auth/payments/etc.).

### B5. Speculative pre-research during user pauses

When the user is reviewing a plan or part-completion question, the orchestrator session is idle waiting on `AskUserQuestion`. Wall-clock spent there is invisible to perf metrics but is the actual bottleneck in interactive mode.

Use that time. Before raising the question, dispatch the next Part's researcher with `run_in_background: true`. By the time the user answers "Continue", research.md for Part N+1 is already on disk. The state machine reads it and goes straight to planning.

**Refinement:** speculate further. If `run-to` or auto-advance is active, also speculate the planner. If the user picks Skip / Abort, the speculative artifacts are renamed `*.speculative.md` and cleaned up.

**Risk:** wasted work if the user diverges. Negligible cost — the work happened during idle time. Mitigation: gate speculation on probability ("if 80% of past user answers were Continue, speculate") or just always speculate on Approve paths.

**Result:** for interactive runs, researcher (and optionally planner) latency becomes ~zero from the user's perspective.

### B6. Pipelined Parts: start next Part's research while reviewing current

Between Parts in auto-advance mode, the executer for Part N finishes and reviewer+auditor start. The next Part's research could start in parallel with reviewer+auditor for Part N. They have no shared in-flight state — research is read-only against the codebase, reviewer/auditor read only the diff.

**Combined with B1's verifier collapse:** Part N's verifier runs in parallel with Part N+1's scout. Wall-clock per Part drops to max(verifier, scout) instead of (executer + verifier + scout).

**Risk:** if reviewer flags a blocker and re-dispatches the executer, the next Part's research may be invalidated (files changed downstream). Mitigation: on re-execute, the speculative artifacts for Part N+1 are dropped. Cost is just the duplicate research, not a correctness hazard.

### B7. Trivial-Part fast path

Many real-world Parts are small: "Update the version string in README", "Rename file X to Y", "Add a CHANGELOG entry". The full 5-agent pipeline is overkill.

Heuristic: at INIT, classify Parts as **trivial** if:
- Part body < 200 words.
- No `Depends on`.
- No `## Verification` block with programmatic command.
- Verbs in title are Update/Rename/Move/Add/Remove (not Migrate/Refactor/Wire-up).
- Body names ≤2 specific file paths.

For trivial Parts: skip researcher (intel + Part body → planner directly). Skip auditor (regex scan only). Use Haiku for reviewer.

**Result:** trivial Parts go from 5 dispatches to 1–2 dispatches. Significant win on plans dominated by small Parts.

**Risk:** misclassification produces under-verified changes. Mitigation: orchestrator emits a one-line note when classifying ("Part 3 is on the trivial fast path — skipping researcher"). User can override during the master plan approval (per B2).

### B8. Aggressive prompt caching audit

Claude Code's Agent dispatch may or may not enable prompt caching for subagent system prompts. The role agent files (6–10KB each) are CONSTANT across all dispatches of one role. The orchestrator's slash-command body (~21KB) is constant across all `/ns continue` ticks.

This is a one-line investigation: does the Claude Code SDK enable `cache_control: { type: "ephemeral" }` on role system prompts? If not, that is potentially 30–50% TTFT reduction across the entire pipeline with zero behavior change.

**Action:** check Claude Code SDK source / docs. If not enabled, file a feature request or add a settings.json override if exposed.

### B9. Trim role prompt files aggressively

| File | Current lines | Estimated needed lines |
|---|---|---|
| `commands/northstar.md` | 357 | ~220 |
| `agents/researcher.md` | 152 | ~80 |
| `agents/planner.md` | 114 | ~65 |
| `agents/executer.md` | 113 | ~70 |
| `agents/reviewer.md` | 94 | ~55 |
| `agents/security-auditor.md` | 113 | ~65 |
| `agents/indexer.md` | 185 | ~110 |

Each agent has a "Don't" section that mostly restates the write-or-block contract. The Output sections include illustrative bodies that grow the prompt. The Severity guidance sections are well-formed but the model already knows blocker/concern/nit distinctions from one example.

Smaller prompt = faster TTFT + less attention dilution + more room for relevant work in the context window.

**Risk:** removing "Don't" rules invites the model to make those mistakes. Mitigation: keep the rules that have prevented real failures (e.g. "do not print body in chat instead of writing", which is load-bearing) and drop the meta-commentary.

### B10. Bundled multi-Part dispatches

Today: researcher is dispatched once per Part. Each dispatch pays cold-start cost.

Alternative: dispatch one researcher with multiple Part descriptions and ask it to produce N research.md files in one go. The orchestrator collects them after one dispatch returns.

This is the "batch researcher" pattern. It trades larger context (N Parts inline) for fewer cold-starts.

**Sweet spot:** 2–4 Parts per dispatch. Beyond that the model's attention degrades.

**Combined with B1 (scout collapse):** scout receives N Parts and produces N pairs of (research.md, plan.md). One dispatch covers many Parts of work.

**Risk:** quality degradation on per-Part precision. Mitigation: cap at 3 Parts per batch; fall back to single-Part for any Part that needs deep exploration.

### B11. State machine in shell, not in markdown prose

`commands/northstar.md` describes a state machine in natural language. The LLM re-derives the state-transition logic each tick. This costs tokens and is fragile.

Drastic alternative: extract the mechanical pieces into a shell script `scripts/northstar-tick.sh`:
- Reads state.json.
- Decides next phase.
- Emits a dispatch directive (path, prompt) that the orchestrator passes to the Agent tool verbatim.
- Or emits an "ask user" directive with options.

The LLM in `northstar.md` becomes a thin wrapper that runs the script, dispatches what it says to dispatch, and asks what it says to ask. The orchestrator's preamble drops from 21KB to ~5KB.

**Result:** dramatic per-tick token reduction. Less LLM-induced state-machine bugs.

**Risk:** conflicts with the "markdown + shell only" stance? Shell is allowed; this would be ~200 lines of POSIX shell + a PowerShell equivalent. Within scope per CLAUDE.md's "no new dep" rule (shell isn't a new dep).

### B12. Eliminate orchestrator boundary for inter-tick state

Each `/ns continue` reboots the orchestrator slash command. Its 21KB preamble loads into the top-level session anew. State is re-read from disk. The model re-establishes "where it is" before deciding what to do.

For multi-step auto-advance flows (`run-to`, or auto-approve-and-execute), this is pure overhead.

Drastic alternative: a `/ns autorun` mode that, within one Claude Code turn, runs the orchestrator state machine through multiple ticks until either:
- A user touchpoint is required (blocker, plan approval if interactive).
- The run completes.
- A safety cap (e.g. 5 Parts per autorun turn) is hit.

The model holds the state machine in its working context across multiple subagent dispatches without an `end-of-turn` between them.

**Result:** one boot per N ticks instead of one boot per tick. Combined with B5/B6 speculation, very few user-visible delays.

**Risk:** longer single-turn execution. If the model gets confused mid-run there's less user oversight. Mitigation: safety cap + one-sentence narration per dispatch (already the contract).

### B13. Inline intel and small artifacts into prompts

Today: each subagent Read's intel/*.md (4 files), research.md, plan.md, etc. before doing work. Across 5 dispatches per Part that's 20+ Read calls.

Drastic alternative: the orchestrator reads intel ONCE at INIT, holds it in memory (the orchestrator's context can absorb ~1KB intel files easily), and inlines it into every subagent dispatch prompt as a prepended `## Project intel (from /ns-init)` block.

Each subagent skips 4 Read calls.

Same logic for the Part description: orchestrator extracts it once at INIT, inlines into every dispatch that needs it.

**Result:** ~4–6 Read calls eliminated per subagent dispatch. Network/disk savings small, but it reduces the agent's task-launch latency.

**Tradeoff:** larger dispatch prompts. For small artifacts (intel ~1–2KB, Part body ~500 bytes), net win. For research.md (up to 400 lines), keep path-pass.

### B14. Reversed execution gate: execute first, surface plan after

Today: planner → user approval → executer.

Drastic alternative: planner → start executer immediately while showing the plan to the user. The Part-completion question now bundles: "Here's what the plan said, here's what executer did, accept or revert?"

If the user disagrees with the plan, the revert is a `git checkout` of the changed files (the executer never commits — files are still safe to discard).

**Result:** the user's plan-review time happens in parallel with the executer's work. Wall-clock for interactive Parts drops dramatically — execution is "free" during the existing approval pause.

**Risk:** wasted work if user rejects the plan. But the executer's work is bounded (one Part) and the revert is cheap. Net positive for plans where users mostly accept.

### B15. Defer typecheck/lint/tests to reviewer or post-flight

`agents/executer.md:48`: "After all steps, run the project's typecheck, lint, and unit-test commands." These can take minutes per Part on large codebases. They block the entire pipeline.

Drastic options:
1. **Defer to reviewer:** reviewer is the verification stage. Let it run typecheck/lint/tests if it deems necessary, with a budget. Executer skips them.
2. **Defer to post-flight:** at end of plan, run the full suite once. Per-Part runs are skipped. Trades per-Part safety for end-of-plan safety.
3. **Only typecheck per-Part; defer lint and tests:** typecheck is fast; lint and tests are slow.

**Result:** executer wall-clock drops substantially on slow-test projects.

**Risk:** regressions ride farther through the pipeline before being caught. Mitigation: this should be a user-configurable mode in state.json (`verify_in_executer: full | typecheck-only | none`).

### B16. Drop output verification on warmed-up roles

`commands/northstar.md:108-128` mandates post-dispatch verification (file exists, non-empty, sentinels present) after every subagent return. The write-or-block contract on every agent now duplicates this in the agent's own discipline.

Drastic option: trust agents that have successfully delivered N times in the current session; only verify on first dispatch and after a known-failing pattern (e.g. retry).

**Risk:** silent regressions in agent behavior over a long session. Mitigation: random spot-checks. Cost saved is small (one Read + one Grep per dispatch). Probably **not worth the risk**.

### B17. Move plan.md inline; eliminate research.md as a separate artifact

Currently: researcher writes research.md, planner reads it, writes plan.md, executer reads both. Two file-IPC hops.

Alternative: scout (per B1) writes ONE artifact `brief.md` containing both research and plan sections. Executer reads one file. Verifier reads one file.

**Tradeoff:** loses the clean separation of "what's in the codebase" (research) vs "what to change" (plan). But the executer doesn't care about that boundary — it acts on the plan and consults research as backup.

**Risk:** loss of the clean "research is canonical context, plan is action" distinction. Net trivial — the executer already treats them as one input bundle.

### B18. Replace the indexer's LLM with deterministic parsing

`agents/indexer.md` runs an LLM dispatch (Sonnet) to read manifests and write four intel files. This is a one-time cost per project (or per `/ns-init refresh`), so not on the per-Part critical path. But it's slow on first-run.

Alternative: a `scripts/northstar-index.sh` that:
- Globs for known manifest names.
- Extracts `scripts.test`, `scripts.lint`, etc. via `jq` or sed.
- Reads CLAUDE.md / AGENTS.md verbatim into `conventions.md`.
- Writes the four intel files mechanically.

**Result:** `/ns-init` runs in seconds instead of minutes.

**Risk:** loses the LLM's ability to distill rules. Could be hybrid: deterministic scan for stack + commands + layout; one short LLM pass for conventions distillation.

---

## Synthesis: a recommended phased rollout

### Phase 0 — Quickly verify (low risk, instant feedback)
- **B8: Prompt caching audit.** Check whether Claude Code already caches subagent system prompts. If not, it may be a config flip. This is a 30-minute investigation, potentially the largest single win.

### Phase 1 — Surgical wins (1–2 days work, low risk)
- **A1: Parallelize reviewer + auditor.** Single state-machine edit.
- **A2: Conditional researcher step 1.** Single agent-file edit.
- **A3: Skip auditor on no-surface diffs.** Single state-machine edit + heuristic table.
- **A4: Auto-advance UI option.** Two AskUserQuestion edits.
- **A6: Trim reviewer input bundle.** Single state-machine edit.

Cumulative: roughly halves per-Part wall-clock with no architectural risk.

### Phase 2 — Structural wins (1 week work, medium risk)
- **B1: Role collapse (scout + verifier).** Two new agent files; orchestrator state machine simplified. Requires fixture re-verification.
- **B5: Speculative pre-research during user pauses.** Background dispatch via `run_in_background: true`. New orchestrator logic.
- **B7: Trivial-Part fast path.** New classifier at INIT; conditional dispatch logic.
- **B9: Trim role prompts.** Mechanical edits across all six agent files.
- **B13: Inline intel into prompts.** Orchestrator caches intel; subagent agent files updated to consume inline first, file as fallback.

Cumulative with Phase 1: ~3–5× speedup on typical plans.

### Phase 3 — Transformational (multi-week work, higher risk)
- **B2: Batch INIT (all research+plan upfront, single approval).** New mode flag. Requires re-thinking the master plan UI.
- **B6: Pipelined Parts.** State-machine restructure.
- **B11: State machine in shell.** Extract mechanical state ops to script.
- **B12: `/ns autorun` mode.** Long-running orchestrator turn.
- **A5: Haiku for reviewer + auditor.** A/B against fixtures first.

Cumulative: order-of-magnitude speedup for non-interactive, well-batched runs.

### Phase 4 — Speculative (only if Phases 1–3 don't get there)
- **B3: DAG-parallel execution via worktrees.** Major architectural shift.
- **B4: Static-scan auditor with LLM escalation.** Requires curated regex set.
- **B14: Reversed execution gate.** Behavior change that needs user buy-in.
- **B15: Defer typecheck/lint/tests.** User-configurable.
- **B18: Deterministic indexer.** Major rewrite of `/ns-init` flow.

---

## What to NOT touch

These were considered and rejected:
- **B16: Drop output verification.** Saves nothing meaningful; loses a robust safety net.
- **A8: state.json / SHA / STATUS.md per-tick.** Combined overhead too small.
- **Removing the orchestrator slash command itself.** That's Claude Code architecture; not Northstar's call.

## Open questions for the user

1. Is **B8 (prompt caching audit)** something you want investigated first as a 30-min spike? It may make several other optimizations moot.
2. Are you willing to relax `commands/northstar.md:354` ("Don't call subagents in parallel") for reviewer+auditor specifically? This is the gating constraint for A1, B1, B6.
3. How tolerant are you of behavior changes that **require new user flows** (B2 master-plan UI, B14 reversed gate)? Some optimizations are pure perf; others change what the user sees.
4. Should `/ns-init` get its own perf treatment (B18), or is it a one-time cost you can ignore?
