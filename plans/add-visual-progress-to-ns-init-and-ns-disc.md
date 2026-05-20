# Add visual progress to ns-init and ns-discover

Add consistent visual progress narration — role badges, staggered before/after lines, and phase-progress indicators — to the `indexer` agent, `/ns-init`, and `/ns-discover` commands. The style should match the spirit of the orchestrator's existing badge system (`🗺️ Scout`, `⚙️ Executer`, etc.) while being tailored to each command's workflow. As a companion change, consolidate the `plans/` output folder under `.northstar/plans/` so all Northstar runtime artifacts live in one place.

## Narration and badges

### Part 1 — Add badge narration to indexer agent

Add a role badge (`📦 Indexer`) and staggered narration to `agents/indexer.md`. The indexer should emit a start line before it begins scanning, one line per output file as it writes it, and a final done line. Pattern to follow: the orchestrator's stagger rule in `commands/northstar.md` under "Narration discipline" (2–4 lines split before/after the main work, never collapsed into one block).

**Depends on:** (none)

**Verification:**
- Manual: read `agents/indexer.md` and confirm `📦 Indexer` badge lines are present at start, per-file, and done points.
- Programmatic: `grep -c "📦 Indexer" agents/indexer.md` returns ≥ 3.

### Part 2 — Add visual progress to ns-init command

Update `commands/ns-init.md` to use the `📦 Indexer` badge on every narration line (dispatch, per-file success, failure). Add a brief start card emitted before dispatching the indexer subagent, mirroring the orchestrator's run-header card style. Replace the current flat one-liner narration ("Indexer: scanning project intel.") with staggered before-dispatch / after-return lines.

**Depends on:** Part 1

**Verification:**
- Manual: read `commands/ns-init.md` and verify badge on all narration lines and a start-card block in the dispatch step.
- Programmatic: `grep -c "📦 Indexer" commands/ns-init.md` returns ≥ 4.

### Part 3 — Add visual progress to ns-discover command

Update `commands/ns-discover.md` to emit a phase-progress indicator at the start of each of the five phases (e.g. `🗺️ Discoverer — Phase 1: vision capture`). Add a completion card when the plan file is written in Phase 5 that shows the output path and the Part titles discovered. Use a `🗺️ Discoverer` badge consistently on all narration lines.

**Depends on:** (none)

**Verification:**
- Manual: read `commands/ns-discover.md` and verify `🗺️ Discoverer` badge lines and phase-progress indicators for all five phases.
- Programmatic: `grep -c "🗺️ Discoverer" commands/ns-discover.md` returns ≥ 5.

## Folder relocation

### Part 4 — Relocate plans/ output folder to .northstar/plans/

Change every reference to the top-level `plans/` directory to `.northstar/plans/`. Affected files:

- `commands/ns-init.md` — `mkdir` step (step 4) and the `plans/` directory entry in the "What you produce" table.
- `commands/ns-discover.md` — default output path (`plans/<slug>.md` → `.northstar/plans/<slug>.md`) in Phase 5 and the argument-shapes table.
- `README.md` — any mention of `plans/` as an output or install artifact.
- `CLAUDE.md` — the repo layout section listing `plans/`.
- `docs/` — scan for any `plans/` path references and update.
- `.gitignore` — add `.northstar/plans/` if not already covered by the existing `.northstar/` ignore rule (it likely is, but verify).

**Depends on:** (none)

**Verification:**
- Manual: run `/ns-discover` in a test session and confirm the default output path offered is `.northstar/plans/<slug>.md`.
- Programmatic: `grep -rn "plans/" commands/ docs/ README.md CLAUDE.md` returns no hits pointing at the old root-level `plans/` path (only `.northstar/plans/` or unrelated prose).

## Open questions

- The existing `plans/` directory at the repo root contains in-progress dev plan files (`plan_now.md`, `refine-subagent-outputs.md`, this plan). The executer should move or leave these as-is — clarify with user if needed before deleting the old directory.
