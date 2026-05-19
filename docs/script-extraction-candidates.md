# Script Extraction Candidates

This document catalogs inline logic across Northstar's agent and command files that could, in principle, be extracted into standalone shell scripts under `scripts/`. For each candidate, it records the source location, what the logic does, why it qualifies as a candidate, and why it may be better left inline.

The reference model for what "extracted" looks like is `scripts/northstar-tick.sh` and `scripts/northstar-tick.ps1` — the only pure-shell extractions done so far. Both are pure input → output, require no LLM context, and are called at a fixed call-site in the orchestrator. New extractions should meet that bar before being pursued.

---

## Candidate A — Credential-pattern regex scan

**Source:** `commands/northstar.md` lines 236–244 (trivial fast-path in `dispatch_verifier`); the same four patterns are referenced again in the `start_batch_verifying` block (lines 221–222 of the same file).

**What it does:** Scans the diff patch for four regex patterns that flag probable credential leakage: hardcoded password/secret/token assignments, PEM private-key headers, AWS credential keys, and common service-token prefixes. The orchestrator uses a match count to decide whether to bypass the full verifier for trivial Parts.

**Why it is a candidate:** The pattern table is pure data. It is referenced in two handlers (`dispatch_verifier` and `start_batch_verifying`), so it is already duplicated. A `scripts/credential-scan.sh|ps1` accepting a patch path and emitting a match count would be testable in isolation.

**Why it may be better left inline:** The orchestrator applies this check as a string-match step inside an LLM prompt — it does not invoke a subprocess. Extracting it would require adding an IPC boundary (subprocess call + output parsing) to what is currently a single table lookup. The two duplications are close in the file and easy to maintain together.

**Recommendation:** Leave inline. The extraction overhead exceeds the maintenance saving at the current duplication level.

---

## Candidate B — SHA-256 plan-file hash check

**Source:** `commands/northstar.md` line 37 — inline in the plan-drift check on every invocation.

**What it does:** Computes the SHA-256 of the plan file to detect drift since the last run. Uses two platform variants: PowerShell `Get-FileHash <path> -Algorithm SHA256` and POSIX `sha256sum <path>`.

**Why it is a candidate:** It is pure shell, single-purpose, and already carries two platform variants — the same shape as `northstar-tick.sh|ps1`.

**Why it may be better left inline:** The logic is a single command per platform. Extracting it into `scripts/hash-plan.sh|ps1` would add more scaffolding (argument handling, output format contract) than the logic itself contains. The call-site is a single location, so there is no duplication pressure.

**Recommendation:** Leave inline.

---

## Candidate C — Directory creation / precondition setup

**Source:** `commands/ns-init.md` lines 52–54 — `mkdir -p .northstar/intel .northstar/plans` (POSIX) and `New-Item -ItemType Directory -Path .northstar/intel,.northstar/plans -Force | Out-Null` (PowerShell). A similar parent-directory creation step appears implicitly in `commands/ns-discover.md` when writing the plan output file to a subdirectory of `.northstar/plans/`.

**What it does:** Ensures the required `.northstar/` sub-tree exists before any intel files are written.

**Why it is a candidate:** Directory scaffolding is idempotent, pure shell, and could become a `scripts/ensure-dirs.sh|ps1` that future commands call consistently.

**Why it may be better left inline:** The invocation is trivially short — one command per platform. It appears in at most two places and does not share a reusable parameter surface. Extracting it would add a file and a call-site protocol for no meaningful de-duplication gain.

**Recommendation:** Leave inline.

---

## Candidate D — `blocker.md` existence + resolution check

**Source:** `commands/ns-next.md` lines 17–18 — the two-condition blocker guard: `blocker.md` exists AND the file lacks a `resolution:` line. The same logical check is performed inside `commands/northstar.md`'s `needs_user` handler (line 308 area).

**What it does:** Determines whether a Part has an unresolved blocker. Used as a hard guard in `/ns-next` to prevent auto-advancing past an open question, and in the orchestrator's own loop to detect whether a blocker has been resolved between invocations.

**Why it is a candidate:** The two conditions (`file exists` AND `no resolution: line`) are repeated in spirit in two command files. A `scripts/check-blocker.sh|ps1 <part-dir>` exiting 0 (no unresolved blocker) or 1 (unresolved) would be trivially testable.

**Why it may be better left inline:** In `commands/northstar.md` the check is a Read + string search that the LLM performs natively — no subprocess. In `commands/ns-next.md` it is a Read + conditional already described in prose. Adding a subprocess round-trip to replace a two-step string match saves no lines and adds an execution dependency.

**Recommendation:** Leave inline.

---

## Candidate E — `northstar.md` two-location lookup

**Source:** `commands/ns.md` lines 14–18; `commands/ns-next.md` lines 50–55.

**What it does:** Locates the canonical `northstar.md` orchestrator file by checking the project-install path (`<repo>/.claude/commands/northstar.md`) and then the user-install path (`~/.claude/commands/northstar.md`) in order.

**Why it is a candidate:** The two-path lookup is verbatim identical in both files. A `scripts/locate-northstar.sh|ps1` emitting the resolved path would centralize the search and prevent the two files diverging if the install paths change.

**Why it may be better left inline:** Both usages are in Markdown prompt files that the LLM reads at runtime. The lookup is not a subprocess call — it is prose that the LLM interprets. Extracting it to a shell script would require the LLM to invoke the script and parse its output, converting a simple path-check into a subprocess round-trip with quoting and error-handling overhead. The two copy sites are the only command files that act as orchestrator aliases, so divergence risk is low.

**Recommendation:** Leave inline. If a third alias command is ever added, extract then.

---

## Candidate F — `git diff` capture + `git add -N`

**Source:** `commands/northstar.md` lines 220–221 (`start_batch_verifying`) and lines 235–236 (`dispatch_verifier`).

**What it does:** Surfaces untracked new files via `git add -N <new-files>` so they appear in the diff, then captures `git diff <files>` into a per-Part patch file at `.northstar/parts/part-N/diff-attempt-K.patch`. The `--stat` variant is also computed for the verifier's context.

**Why it is a candidate:** The two-step sequence is duplicated across the two handlers that dispatch verifiers. A `scripts/capture-diff.sh|ps1 <part-id> <attempt> <files…>` would encapsulate it and eliminate the duplication. The existing `northstar-tick.sh|ps1` files demonstrate the pattern.

**Why it may be better left inline:** The logic requires passing a variable-length, potentially space-containing file list as arguments, making quoting non-trivial. The two call-sites are in adjacent handlers for related flows (batch vs. single-Part); the duplication is visible and easy to maintain together. Until a third call-site emerges, the extraction cost (quoting contract, error handling, cross-platform test) exceeds the benefit.

**Recommendation:** Conditional. If a third diff-capture call-site is added (e.g., for a future `re-verify` command), extract at that point.

---

## Candidate G — Artifact sentinel check

**Source:** `commands/northstar.md` lines 126–133 — output verification table checked after every subagent dispatch (scout, executer, verifier).

**What it does:** Verifies that each subagent artifact file exists and contains the required sentinel string (e.g., `## Plan` in `brief.md`, `## TL;DR` in `execution.md`, `## Verdict` in `review.md`/`audit.md`). Repeated after each of the three dispatches.

**Why it is a candidate:** The check pattern — file-exists + grep-for-sentinel — is uniform across all artifacts. A `scripts/check-artifact.sh|ps1 <path> <sentinel>` exiting 0 (sentinel found) or 1 (absent/missing) could replace three identical prose blocks.

**Why it may be better left inline:** The orchestrator currently uses the Agent-native Grep and Read tools for this check — no subprocess. Replacing those with a shell script would add a subprocess round-trip that is strictly slower and more fragile than the native tool calls. The benefit only materialises if the orchestrator is ever run outside an LLM context (e.g., a CI script validating artifacts directly).

**Recommendation:** Leave inline. Document as a future extraction target if a non-LLM validation harness is built.

---

## Candidate H — STATUS.md regeneration

**Source:** `commands/northstar.md` lines 330–362 — the STATUS.md template and field-population rules.

**What it does:** Regenerates `.northstar/STATUS.md` on every state mutation, populating a Markdown table of Parts, a current-focus paragraph, recent decisions, outstanding blockers, and artifact paths from the in-memory state object.

**Why it is a candidate:** Templated output is a natural fit for a shell script if the state were serialized to JSON first. `northstar-tick.sh|ps1` already reads and outputs JSON.

**Why it may be better left inline:** The field-population logic requires interpolating complex state (Part table rows, decision log, nested artifact maps) that is held in the LLM's context, not as a standalone JSON file the orchestrator writes before calling the script. Extracting it would require a full JSON-to-Markdown renderer in shell, which is non-trivial and would make the STATUS format harder to customize. The current approach — LLM interprets the template — is simpler and more flexible.

**Recommendation:** Leave inline. If `state.json` is ever made the sole state truth (removing in-context state), revisit.

---

## Candidate I — Indexer preflight manifest check

**Source:** `agents/indexer.md` lines 23–26 — a Glob-based check for at least one root manifest (`package.json`, `pyproject.toml`, `go.mod`, etc.) to confirm the indexer is running inside a recognizable project.

**What it does:** Confirms a project root exists before proceeding to write intel files. The check runs inside the LLM agent, not in a shell session.

**Why it is a candidate:** If the indexer were ever replaced or supplemented by a pure-shell pre-flight script, this manifest scan would be a natural extraction — identical in spirit to the project-detection check in `commands/ns-init.md` lines 42–43.

**Why it may be better left inline:** The check currently runs inside an LLM subagent using the Glob tool. It is not a shell command and cannot be extracted without changing how the indexer works. The same conceptual check is also performed in `commands/ns-init.md` (line 42) as a Bash/PowerShell command; the two are not the same code path.

**Recommendation:** Leave inline in the agent. The `ns-init.md` shell-level variant is the appropriate extraction target if centralization is desired.

---

## Summary

| ID | Location | Logic | Duplication | Extractable today? |
|----|----------|-------|-------------|-------------------|
| A | `northstar.md:236–244` | Credential-pattern regex scan | 2 sites | No — LLM inline, IPC overhead |
| B | `northstar.md:37` | SHA-256 plan-file hash | 1 site | No — too short, single call-site |
| C | `ns-init.md:52–54` | Directory creation | 2 sites (loose) | No — trivially short |
| D | `ns-next.md:17–18`, `northstar.md:308` | Blocker existence + resolution check | 2 sites | No — LLM Read/string-match, no subprocess |
| E | `ns.md:14–18`, `ns-next.md:50–55` | `northstar.md` two-location lookup | 2 sites | No — LLM prose, not shell |
| F | `northstar.md:220–221`, `northstar.md:235–236` | `git diff` capture + `git add -N` | 2 sites | Conditional — extract on third call-site |
| G | `northstar.md:126–133` | Artifact sentinel check | 3 sites | No — uses native LLM tools |
| H | `northstar.md:330–362` | STATUS.md regeneration | 1 site | No — requires full JSON-to-Markdown renderer |
| I | `agents/indexer.md:23–26` | Indexer preflight manifest check | 1 site (agent) | No — runs inside LLM agent |

No candidates are ready for extraction today. Candidate F (`git diff` capture) is the strongest near-term candidate and should be revisited if a third call-site appears.
