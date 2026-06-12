---
name: lvlup-ns-selfmod-contract-drift
description: Handle sentinel/contract drift when a Northstar run edits the pipeline's own agent prompt files (agents/*.md, commands/northstar.md). Use for any /ns plan that modifies agent contracts mid-run — sentinel checks will fail in both directions.
version: 1.0.0
license: MIT
---

# Self-modifying run contract drift

A run whose Parts edit `agents/*.md` or `commands/northstar.md` changes the
contracts the run itself is checked against. Drift happens in BOTH directions:

1. **Agents pre-apply the proposed schema before it lands.** A researcher
   wrote the *renamed* section header it was researching instead of the
   still-required sentinel → orchestrator sentinel check failed → blocker.
   Resolution that worked: "Accept anyway" + orchestrator retitles the section
   in the artifact with an HTML comment noting the retitle (body unchanged).
   Check cascading preflights first — a downstream agent (planner) had the
   same sentinel and would have independently refused.
2. **Agents fail to self-apply rules already landed.** A later planner omitted
   the `## TL;DR` block an earlier Part had added to its own prompt file.
   Don't burn a retry: proceed and let the reviewer record it as a
   non-blocking concern — the schema change itself was the Part's target.
3. **Sentinel renames must land atomically across all checkers** in one Part:
   the agent prompt file + every orchestrator/peer-agent location that greps
   for the sentinel (e.g. `agents/researcher.md` + `commands/northstar.md` +
   `agents/planner.md`).
