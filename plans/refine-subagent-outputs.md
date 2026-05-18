# Refine subagent outputs

Audit and tighten the **output contracts** of every role subagent in the Northstar pipeline so the orchestrator can surface findings to the user concisely and unambiguously. Every agent currently writes a prose markdown artifact with a fixed section schema; the orchestrator cannot narrate a one-line summary without re-reading the body, several "empty" signals are ambiguous, and a few user-facing items (external dependencies, manual follow-ups) live inside artifacts where the user never sees them. This plan revises each of the six role agents — researcher, planner, executer, reviewer, security-auditor, indexer — and the orchestrator narration that surfaces their outputs, then bumps the patch version.

The work is sliced one agent per Part. Part 1 lands the shared **TL;DR header schema** that the remaining agent Parts mirror; Parts 2–6 each refine one agent's output contract (and, where applicable, the orchestrator narration that surfaces it); Part 7 bumps the version and updates docs. Sizing is balanced — each Part touches one agent file plus, at most, one section of `commands/northstar.md`.

## Agents

### Part 1 — Refine researcher output

Revise `agents/researcher.md` to (a) add a structured TL;DR header at the top of `research.md` containing counts the orchestrator can echo to the user in one sentence (files-to-touch count, helpers count, gotchas count, domain-risks count, open-questions count); (b) introduce an explicit rule distinguishing questions the planner can decide (stay in `## Open questions for planner`) from questions only the user can decide (must become `blocker.md` instead) — this closes a hole where user-facing ambiguity got buried in a planner-only section; (c) replace the `## Stack conventions` section with a `## Stack deltas from intel` section that captures only what differs from `.northstar/intel/stack.md` and `.northstar/intel/conventions.md`, eliminating per-Part duplication of baseline intel; (d) require an explicit `(none observed)` line on any empty section so empty ≠ forgotten.

This Part also defines the **TL;DR header schema** that Parts 2–6 will mirror. Schema shape, location (top of file, immediately under the H1), and field-naming convention should be designed once here and referenced from each downstream agent's Output section.

**Depends on:** (none)

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md` end-to-end and confirm `research.md` opens with the new TL;DR block, any empty section says `(none observed)`, and `## Stack deltas from intel` exists in place of `## Stack conventions`.
- Programmatic: (none — Northstar is a prompt pipeline with no unit tests; smoke tests are the contract per CLAUDE.md.)

### Part 2 — Refine planner output

Revise `agents/planner.md` to (a) add the TL;DR header schema defined in Part 1 with planner-relevant counts (step count, external-deps count, has-risks flag); (b) make the planner echo the Part-level `**Verification:**` block from the plan file verbatim into `plan.md`'s `## Verification` section and *append* concrete commands underneath, replacing the current independent re-write that risks drifting from the user's stated criteria; (c) fix the malformed sentence on what is currently line 101 ("surface it as an 'Open question for planner' was unanswered"). Additionally, update `commands/northstar.md` so the orchestrator reads `plan.md`'s `## External dependencies` section on plan ingest (after the planner returns, before dispatching the executer) and announces any ⚠-marked items to the user with a one-sentence narration plus an AskUserQuestion to confirm before proceeding ("Plan has 1 manual action required: <X>. Continue?"). This makes external dependencies a visible checkpoint instead of a buried surprise the executer hits mid-run.

**Depends on:** Part 1

**Verification:**
- Manual: Run a fixture whose Part requires an external action (or amend `fixtures/test_plan.md` to include one) and confirm the orchestrator stops after planner, reads the external-deps section aloud, and waits for confirmation. Also confirm `plan.md`'s Verification section echoes the Part's verbatim block.
- Programmatic: (none.)

### Part 3 — Refine executer output

Revise `agents/executer.md` to (a) add the TL;DR header schema from Part 1 with executer-relevant counts (files-changed count, total ±lines, tests-pass rollup, manual-follow-ups count, deviations count); (b) require uniform pass/fail glyphs (`✅` pass / `❌` fail / `⏭` skipped) on every line of `## Test results`, matching the glyph set already used in STATUS.md; (c) require `+N/-M` line-count annotations on every entry in `## Files changed` (e.g. `` `path` — short summary (+12/-3) ``). Additionally, update `commands/northstar.md` so the orchestrator reads `execution.md`'s `## Manual follow-ups required` on Part completion and announces each item to the user in narration before advancing — today these live inside the file and the user has to open it to see them.

**Depends on:** Part 1

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md`; confirm `execution.md` shows the TL;DR header, glyphs on test result lines, diff stats per file, and that the orchestrator narrates manual follow-ups on Part completion.
- Programmatic: (none.)

### Part 4 — Refine reviewer output

Revise `agents/reviewer.md` to (a) add the TL;DR header schema from Part 1 with reviewer-relevant fields (verdict, blocker count, concern count, nit count) so the orchestrator can route off it directly and narrate "Review: 0 blockers, 2 concerns, 4 nits" without reading the body; (b) canonicalize the empty-findings expression to a single `(none observed)` line, matching the rule introduced for the researcher in Part 1, and remove the two-way ambiguity in the current prompt ("write `none`, or omit bullets and write a one-line no findings"); (c) tighten the "10+ nits → collapse" guidance to a hard cap of 5 nits per review — beyond that, one collapsed finding referencing "see follow-up notes."

**Depends on:** Part 1

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md` (or a fixture with intentionally minor diffs) and confirm `review.md` opens with the TL;DR header; that empty findings say `(none observed)`; that a contrived case with many nits collapses at 5+.
- Programmatic: (none.)

### Part 5 — Refine security-auditor output

Revise `agents/security-auditor.md` to (a) add the TL;DR header schema from Part 1 with auditor-relevant fields (verdict, blocker / concern / nit counts) — same shape as the reviewer per Part 4 for consistency; (b) add a new `## Checklist coverage` section in which each of the 8 generic checklist items (auth boundaries, authorization policies, injection, secret handling, input validation, rate limiting, deep links/IPC, dependencies, logging) is marked one of `N/A | checked-clean | flagged`. This converts the current implicit "applied selectively" rule into an auditable signal — the orchestrator can narrate "Audit covered 6 of 9 categories (3 N/A)" — and makes "auditor forgot" detectable; (c) canonicalize the empty-findings expression to `(none observed)`, matching the reviewer change in Part 4.

**Depends on:** Part 1

**Verification:**
- Manual: Run `/ns fixtures/test_plan.md` and confirm `audit.md` has the TL;DR header, a `## Checklist coverage` section with each generic-checklist item assigned a status, and `(none observed)` on empty findings.
- Programmatic: (none.)

### Part 6 — Refine indexer output

Revise `agents/indexer.md` to (a) add a `## Sources scanned` section to each of the four intel files (`stack.md`, `layout.md`, `conventions.md`, `modules.md`) listing the manifests, convention docs, and config files the indexer actually read — so the researcher can later compare file mtimes against the indexer's last-run timestamp to detect stale intel; (b) canonicalize empty expressions inside intel files (e.g. `Cross-module links worth knowing - bulleted ... or empty`) to a single `(none observed)` phrasing, matching the downstream convention introduced in Part 1. The four-file contract (no fifth file) remains intact; the required H2 headings remain intact (new sections are additive, not replacements).

**Depends on:** Part 1

**Verification:**
- Manual: Run `/ns-init` against the current repo, confirm each of the four intel files has a `## Sources scanned` section listing concrete paths, and that any empty section reads `(none observed)`.
- Programmatic: (none.)

## Release

### Part 7 — Bump version and update docs

Bump Northstar to **v0.3.1** in all three locations per CLAUDE.md's version-sync rule: (1) `commands/northstar.md` heading (`# /northstar (alias: /ns) — Northstar v0.3.1`), `tool_version` field inside the state schema block, and the STATUS.md template header; (2) `README.md` footer ("Northstar v0.3.1. Telemetry: none."); (3) `CHANGELOG.md` — new section `## [0.3.1] — <YYYY-MM-DD>` summarizing the agent-output refinements (TL;DR headers across all six role agents, canonicalized empty-findings phrasing, planner external-deps orchestrator surfacing, executer manual-follow-ups orchestrator surfacing, reviewer hard nit cap, auditor checklist-coverage signal, indexer sources-scanned manifest). No tag — the user will tag and push after final verification.

**Depends on Parts 1, 2, 3, 4, 5, and 6**

**Verification:**
- Manual: `grep -n "0\.3\.1" commands/northstar.md README.md CHANGELOG.md` returns the expected hits in all three; CHANGELOG entry reads cleanly and references each Part's change.
- Programmatic: (none.)

## Critical files reference

- `agents/researcher.md` — researcher prompt; Part 1 target.
- `agents/planner.md` — planner prompt; Part 2 target.
- `agents/executer.md` — executer prompt; Part 3 target.
- `agents/reviewer.md` — reviewer prompt; Part 4 target.
- `agents/security-auditor.md` — security-auditor prompt; Part 5 target.
- `agents/indexer.md` — indexer prompt; Part 6 target.
- `commands/northstar.md` — orchestrator; touched by Part 2 (external-deps surfacing), Part 3 (manual-follow-ups surfacing), Part 7 (version bump).
- `README.md` — touched by Part 7 (version footer).
- `CHANGELOG.md` — touched by Part 7 (release notes).
- `.northstar/intel/stack.md`, `layout.md`, `conventions.md`, `modules.md` — read by Part 1 (intel-deltas refactor) and produced by Part 6 (sources-scanned section). Already cached for this repo.
- `fixtures/test_plan.md` and other fixtures — smoke-test substrate for every Part's verification.

## Open questions

- **Exact TL;DR header format.** Part 1 defines it but the choice between (a) YAML frontmatter (machine-parseable, breaks the "agents produce pure markdown" feel) and (b) a `## Summary` block with `key: value` lines (markdown-native, requires a tiny parser in the orchestrator) is unresolved. The Northstar pipeline researcher running Part 1 should decide based on how the orchestrator (`commands/northstar.md`) parses other agent outputs today. Default if unresolved: markdown-native `## Summary` block with `key: value` bullet lines.
- **Where the new "canonical empty signal" rule is documented.** It applies to researcher, reviewer, auditor, indexer — but should it also be reflected in `docs/plan-format.md` or `docs/architecture.md`? Defer to the Part 1 planner.
- **Version bump scope.** User chose patch (v0.3.1); these are agent output-contract changes which are visible to downstream tooling that parses the artifacts. If any external integration relies on the existing artifact shape, this could justify a minor bump (v0.4.0). No such integrations are known. Revisit at release time.
