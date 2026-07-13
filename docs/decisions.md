# Decisions log

A reverse-chronological record of the major design decisions behind Suhail, with rationale. The PR description is the conversation; this file is the conclusion.

Append new entries at the top. Each entry has a date, a one-line headline, what was decided, and why.

---

## 2026-07-13 — v1.1.0 hardening: patch-isolated Part commits; verdicts fail closed at the reader

**Decided:** per-Part commits are now built from exact patches. Before and after each executer run the orchestrator snapshots the working tree via a temporary-index `git write-tree` (includes untracked files, respects `.gitignore`, never touches the user's real index). The Part's diff is the tree-to-tree patch between the two snapshots (excluding `.suhail/`), and the commit applies that patch to a temporary index on HEAD via plumbing (`commit-tree` + `update-ref`). Consequences: pre-staged or dirty user changes can never be swept into a Suhail commit; a Part that edits a file the user already had uncommitted edits in fails closed to a blocker instead of mixing content; sibling Parts editing the same file commit cleanly in sequence; review diffs are per-Part-exact in every mode, and the old no-commit `diff_baseline` (`git stash create`) mechanism is gone.

Alongside it, six smaller hardenings: (1) verdict parsing fails closed at the reader layer — `suhail-read` returns a null verdict for any `## Verdict` value outside the `clean` / `concerns` / `blockers` enum (case-insensitive accept, lowercase emit), and the orchestrator treats null as a blocker, never as clean, so no downstream consumer has to re-validate; (2) the trivial fast path excludes risk markers — Parts containing `⚠`, an `External dependencies` block, or `TBD` are never classified trivial, and the external-deps checkpoint scans the original Part body as a backstop; (3) `no-commit` is accepted at INIT only — continuations preserve `state.auto_commit`, and a mid-run `no-commit` gets a one-sentence notice, never a silent reset; (4) `batch_first` in both tick scripts selects by numeric Part id rather than array order, INIT rejects duplicate Part ids, and the parts array is built numerically sorted; (5) `/su-init` project detection accepts `.git` as a plain file (linked git worktree) as well as a directory; (6) the docs treat the namespaced plugin command forms (`/suhail:su`, `/suhail:su-init`, …) as canonical, since namespacing is mandatory Claude Code plugin behavior, not version-dependent.

**Why (commit isolation):** the pathspec commit (`git add <files>` + `git commit`) inherited whatever content the working tree held for those paths — a user's uncommitted edits in a Part-touched file were silently folded into the Part's commit, and pre-staged changes could ride along via the shared index. Building the commit from the exact before/after patch makes the commit's content exactly what the Part changed, in every mode, independent of the state of the user's index or working tree.

**Considered alternatives:** pathspec-commit-plus-guards (keep `git commit -- <paths>`, add index/tree cleanliness checks) — rejected: guards shrink the mixing window but cannot separate user content from Part content inside the same file, so the core failure mode survives. Skip-and-flag (detect a dirty overlap, skip the commit, surface a notice) — rejected: it silently abandons the one-atomic-commit-per-Part guarantee exactly when history is most valuable. The patch design preserves the guarantee in all cases and fails closed on user-dirty overlap.

**Trade-off:** commits created via plumbing bypass git commit hooks (pre-commit, commit-msg). Documented in the README's Safety section; accepted because hook-enforced policy still applies at push/CI time, and both alternatives traded correctness for hook compatibility.

---

## 2026-07-12 — Public-release hardening; jq is the one allowed runtime dependency

**Decided:** before the first public release, the state machine was made fail-closed (unknown Part statuses and phases are errors, never silent completion), the audit surface was widened from executer-self-reported file lists to actual `git status` state, the trivial fast path lost its ability to skip the security audit, and a committed test harness (`tests/`) now pins the tick/read/write contracts for both script families. Alongside this, `jq` is recorded as the single allowed exception to the "markdown and shell only" dependency rule: the POSIX helper scripts hard-require it and refuse to run without it.

**Why:** JSON manipulation in pure POSIX shell is where correctness goes to die; jq is ubiquitous, stable, and single-purpose. The alternative — hand-rolled shell JSON parsing — was rejected as a far larger correctness risk than one well-known dependency. The requirement is documented in the README and CONTRIBUTING rather than hidden in script error messages.

For completeness of the dependency log: the test harness's frontmatter check uses python3 + PyYAML as a **dev-only** tool — the check self-skips with a notice when they're absent locally, CI provides them, and nothing at runtime touches Python. This is not a second runtime exception.

---

## 2026-07-12 — Renamed Northstar → Suhail (v1.0.0)

**Decided:** the project is rebranded to Suhail — the Arabic name for Canopus, the guiding star of Arab navigators. Commands `/ns*` → `/su*`, agents `ns-*` → `su-*`, scripts `northstar-*` → `suhail-*`, state dir `.northstar/` → `.suhail/`, plugin `northstar@northstar` → `suhail@suhail`. Treated as a breaking change (state-dir move) per the IPC rule, hence 1.0.0.

**Why:** "Northstar" collides with several adjacent projects in the AI-agent and dev-tool space (a major game-mod framework, another Claude Code plugin, an AI planning product). Suhail is collision-free in the developer-tool space and keeps the guiding-star identity.

---

## 2026-07-02 — Plugin-only distribution (supersedes 2026-05-14 install-script decision)

**Decided:** Suhail distributes solely as a Claude Code plugin. The repo doubles as its own marketplace (`.claude-plugin/marketplace.json` + `plugin.json`). Install is `/plugin marketplace add wessamfathi/suhail` then `/plugin install suhail@suhail`. The `scripts/install.{sh,ps1}` copy-installers were removed.

**Why:** the plugin model is native, versioned, self-updating, and requires no file-copy logic to maintain across POSIX/PowerShell. It bundles `commands/`, `agents/`, and `scripts/` as-is and exposes them via `${CLAUDE_PLUGIN_ROOT}`, which the script-path lookup checks first. The two installers were duplicated maintenance surface (two shells, `--project`/`--force`/`--gitignore` flags, stale-file cleanup) that the plugin system now handles.

**What this supersedes:** the 2026-05-14 "User-level install by default, project-level optional" decision — there are no install scripts to have a default scope. The `.gitignore` auto-edit convenience is also gone; users add `.suhail/` to their target repo's `.gitignore` manually (README documents this).

**Trade-off:** drops support for Claude Code versions without plugin support. Acceptable — plugin support is broadly available, and the manual project/user-copy lookup steps remain in `commands/su.md` for anyone who copies the files by hand.

---

## 2026-05-21 — Orchestrator auto-commits each Part atomically (on by default)

**Decided:** after a Part is verified clean and marked `completed`, the orchestrator creates exactly one git commit containing only that Part's `files_changed`. On by default (`auto_commit: true`); opt out per run with the `no-commit` argument. Applies in all modes. The orchestrator never pushes, deploys, amends, or force-pushes, and a failed commit raises an orchestrator blocker instead of retrying/amending. The **su-executer** still never commits — committing is solely the orchestrator's job, at the verified-clean boundary.

**Why:** an unattended (autorun) run previously left all Parts as one undifferentiated working-tree diff, making review, partial push, and selective rollback hard. One commit per verified Part maps the git history onto the plan's structure: each commit is reviewable in isolation, pushable independently, and revertable without disturbing other Parts. Tying the commit to the verified-clean transition (not to execution) means only Parts that passed review/audit enter history.

**Considered alternatives:** committing after execution (rejected — would record Parts that later fail verification); a single squashed commit at run end (rejected — loses the per-Part atomicity that makes review and rollback easy); keeping commits fully manual (rejected — a core design requirement was that commits land as the work completes). This reverses the earlier "never commit" stance in the orchestrator's commit policy; the v1 "never phone home / no telemetry" commitment is unaffected.

---

## 2026-05-20 — Orchestrator IO (state write + artifact read) moved to shell scripts

**Decided:** `suhail-write.{ps1,sh}` handles atomic `state.json` writes and STATUS.md rendering; `suhail-read.{ps1,sh}` handles artifact parsing (reading part-dir markdown files and returning a structured JSON summary). The orchestrator invokes these as external scripts via stdin/stdout, not as agent dispatches.

**Why:** both operations are purely mechanical — JSON field extraction, string substitution, atomic file write, template rendering. No reasoning or judgment is required. Implementing them as agents would waste a full subagent context slot (and incur LLM latency) on a deterministic transform. Scripts execute synchronously and return a clear exit code, letting the orchestrator treat a non-zero exit as a hard blocker without a dispatch-verify cycle. The STATUS.md template previously inline in `commands/su.md` is now owned by `suhail-write`, which reads `tool_version` from the incoming state JSON at runtime — eliminating a third version-sync point from the release checklist.

**Considered alternatives:** an `su-writer` subagent was considered during the pre-run analysis; rejected because the agent dispatch overhead and async return pattern is heavier than the task warrants, and because adding an agent for a deterministic operation would contradict the principle that agents are reserved for tasks requiring LLM judgment (stack discovery, code generation, review). The blocker that surfaced during the original su-writer design attempt confirmed the approach was wrong-sized for the problem.

---

## 2026-05-20 — Interview stays in the slash command; scan and author move to agents

**Decided:** the multi-turn interview logic remains in `commands/su-discover.md` (top-level slash command) because `AskUserQuestion` and cross-turn context require the top-level session. Phase 0 (silent grounding scan) moves to `su-discover-scout`: read-only, one-shot, uses model `claude-haiku-4-5-20251001`, returns a structured summary as its response rather than writing a file — appropriate because it produces no artifact the user needs to inspect or retry, only context the command needs for the interview. Phase 5 (plan-writing) moves to `su-discover-planner`: write-only, one-shot, consumes the answers file at `.suhail/discover/<slug>.answers.md` — same files-as-IPC contract as all other Suhail roles, keeping the command's context bounded and the plan-writing step independently retryable.

**Why the interview itself cannot be a subagent:** subagents are one-shot; a multi-turn interview requires holding context across `AskUserQuestion` round-trips, which only the top-level session supports.

---

## 2026-05-15 — Orchestrator never improvises for a failing subagent

**Decided:** the orchestrator runs explicit output verification after every `Agent(...)` dispatch. If an artifact is missing, empty, or lacks the role's expected H2 sentinel sections, the orchestrator writes a blocker.md (`from: orchestrator`) and routes to `needs_user`. It does NOT fabricate the missing content.

**Why:** v0.1.1 had a silent-degradation path: if a subagent returned without producing its artifact, the orchestrator would advance to the next phase, where the next subagent would try to read a missing input and either fail itself or — worse — improvise from the Part description alone. That produces cascade hallucinations: a planner with no research, a reviewer with no diff, an auditor with no code. Each step compounds the drift.

Combined with the new "fail-loud preflight" in each role agent (which refuses to proceed if inputs are missing), the verification gate keeps hallucinations contained to one agent's output. The user is notified the moment something goes wrong rather than discovering a corrupted run three Parts later.

**Mechanism:** sentinel-based content checks (e.g. brief.md must contain `## Research` and `## Plan`; review.md must contain `## Verdict` with a valid value). Cheap to run, strong enough signal in practice.

---

## 2026-05-14 — Orchestrator lives in the slash command body, not as a subagent

**Decided:** the orchestrator state machine + dispatch logic lives in `commands/suhail.md` (and is mirrored by reference from `commands/su.md`). It is NOT a Claude Code subagent.

**Why:** Claude Code does not allow a subagent invoked via the Agent tool to spawn further subagents. The v0.1.0 design placed the orchestrator at `agents/suhail.md` expecting it to dispatch the five role subagents. In practice, `/su` would invoke the orchestrator as a subagent, which then could not actually call researcher/planner/etc. — sessions fell back to driving the pipeline from the top level, defeating the design.

By putting the orchestrator into the slash command body, invoking `/su` injects the orchestrator prompt into the **top-level** session. The top-level session has the Agent tool and dispatches the five role subagents one level deep. Pipeline tree: top-level → role subagent. Legal.

**Cost:** the orchestrator prompt (~600 lines, ~15K tokens) is in the top-level context per invocation. Acceptable — see `architecture.md` § Context window impact.

**Considered alternatives:**
- Duplicate the orchestrator body across `su.md` and `suhail.md`. Rejected — maintenance burden.
- Have `su.md` symlink to `suhail.md`. Rejected — symlinks are awkward on Windows installs.
- Keep the v0.1.0 fallback (top-level session implicitly playing orchestrator). Rejected — the fallback was implicit and undocumented; making it explicit is better.

**Chosen:** `commands/su.md` reads `commands/suhail.md` at runtime and follows it. Single source of truth in `suhail.md`. *(Update as of v0.7.2: `commands/suhail.md` was removed and `commands/su.md` became the single source of truth.)*

---

## 2026-05-14 — Domain knowledge flows through one channel only

**Decided:** the su-verifier's audit pass is intentionally generic — a language-agnostic checklist (auth, authorization, injection, secrets, validation, deep links). Project-specific risks reach it only through the su-scout's `Domain risks worth flagging to auditor` section in `brief.md`.

**Why:** otherwise every new domain requires forking the audit prompt. With a single hint channel, the same audit pass works for an Expo/Supabase app, a Rust CLI, a Python data pipeline — the su-scout discovers what's at stake and tells the auditor.

**Constraint this places on contributors:** never add domain-specific rules to the audit pass in `agents/su-verifier.md`. If you find a recurring risk that's project-specific, surface it as a recommendation in `docs/extending.md` for the su-scout's risk-detection heuristics; do not bake it into the verifier.

---

## 2026-05-14 — Files-as-IPC, not return values

**Decided:** every role subagent reads its inputs from disk and writes its output to disk. The orchestrator passes paths in prompts and never echoes artifact bodies into the top-level conversation.

**Why:** subagents produce hundreds of lines per Part. If the orchestrator received their full output as return values and echoed any of it, the top-level context would balloon within a handful of Parts.

The trade-off is small: each subagent does a few extra disk reads/writes. In exchange:

- Orchestrator context bounded regardless of plan size or artifact size.
- Every reasoning step is inspectable on disk — users can read `brief.md` mid-run, audit it post-hoc, or rerun a stage from its artifacts.
- Subagents are stateless across invocations.
- `retry` is trivial (rename old artifacts to `.orig.md`, re-run).

**Don't change this without a major version bump and migration plan.**

---

## 2026-05-14 — Reviewer and security-auditor are independent

**Decided:** both run on every Part. They do not see each other's output. They have independent retry triggers.

**Why:** they catch different things. Reviewer catches correctness, regressions, convention drift. Auditor catches auth, authorization, injection, secrets. Many findings are both — both will catch them, the executer addresses them sequentially; no harm.

If they shared findings, the second one would defer to the first and miss things. Independence is the cheap way to get two reads with different priors.

**Ordering rationale:** auditor runs only after reviewer is clean (no `blocker` findings). This serializes feedback so the executer addresses correctness before security. Correctness blockers tend to invalidate security analysis anyway.

---

## 2026-05-14 — One Part per tick, hard pause at Part boundaries (amended by the v0.13 batched execution: checkpoints are per approval gate and per dependency level — see docs/architecture.md)

**Decided:** each `/su` invocation in interactive mode advances state by exactly one Part. After each Part completes, the orchestrator ends its turn with an AskUserQuestion ("Continue to Part M?"). No silent advancement.

**Why:** per-Part user approval is a hard requirement of the design. Every Part is a checkpoint. This is the system's most important property in interactive mode — it's the reason a user can trust Suhail with a 50-Part plan.

**Escape hatch:** `run-to <part-id>` bypasses per-Part pauses (and plan approval) until the target is reached. Designed for unattended runs. A 20-Part safety cap forces an interactive checkpoint even mid-target so unattended runs cannot go arbitrarily long.

---

## 2026-05-14 — Stack-agnostic role subagents

**Decided:** none of the role subagents (su-scout, su-executer, su-verifier) contain language-specific or framework-specific knowledge. The su-scout discovers stack conventions at runtime by reading CLAUDE.md / AGENTS.md / README / manifests and surfaces them in `brief.md`.

**Why:** the alternative is per-language Suhail variants, which immediately fragment. The runtime-discovery design lets one Suhail install handle TypeScript, Python, Rust, Go, anything — as long as the target project documents itself, the pipeline adapts.

**Constraint this places on contributors:** never add conditional logic based on detected language to a role subagent's prompt. If a role needs language-specific behavior, it should derive it from `brief.md`'s stack-conventions section.

---

## 2026-05-14 — User-level install by default, project-level optional (superseded — see 2026-07-02 plugin-only distribution)

**Decided:** `install.sh` and `install.ps1` default to `~/.claude/`. `--project <path>` installs into `<path>/.claude/` instead.

**Why:** user-level means one install works across every repo on the machine. Most users want Suhail everywhere. Project-level is for two cases: (1) developing Suhail itself (install into the Suhail repo so your working copy overrides any user-level install), (2) pinning a specific version to a specific repo.

**`.gitignore` auto-edit is opt-in.** The installer never modifies a target repo's `.gitignore` unless explicitly told to (`--gitignore` / `-Gitignore`). Surprise file modifications are bad form.

---

## 2026-05-14 — Executer never commits, never deploys

**Decided:** the executer subagent has `Read, Edit, Write, Glob, Grep, Bash` but the prompt forbids `git commit`, `git push`, and deploy commands. Both are flagged in `execution.md` as "Manual follow-ups required."

**Why:** commits and deploys are user-authorized side-effects. The orchestrator surfaces a "Commit first" option at the Part-completion AskUserQuestion — only an explicit user choice authorizes a commit, and even then the commit message and staged set are derived deterministically from execution.md and the plan title.

This also means a run can be aborted at any time without contaminating the user's git history. The artifacts on disk are the trail; the commit (if any) is the user's call.

---

## 2026-05-14 — Plan format uses em-dash separator

**Decided:** Part headings must be `### Part N — Title` with an em-dash (`—`, U+2014). ASCII hyphen is not accepted.

**Why:** without a distinguishing character, plain H3 headings would collide with the Part detector. The em-dash is rare enough in casual H3 headings to act as a sentinel.

**Trade-off:** users on US keyboards without an em-dash shortcut may find this annoying. The README documents the typographic constraint; markdown editors typically auto-convert `--` to `—` anyway.

---

## 2026-05-14 — MIT license, no telemetry, ever

**Decided:** MIT license. No telemetry. v1 commitment.

**Why:** Suhail is a thin coordinator running locally in Claude Code. Telemetry adds privacy concerns, network dependencies, and trust friction for a tool that's supposed to be inspectable. The whole point of the artifacts-on-disk design is "you can see everything Suhail is doing"; adding a phone-home would contradict that.

---
