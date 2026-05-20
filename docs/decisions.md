# Decisions log

A reverse-chronological record of the major design decisions behind Northstar, with rationale. The PR description is the conversation; this file is the conclusion.

Append new entries at the top. Each entry has a date, a one-line headline, what was decided, and why.

---

## 2026-05-20 — Orchestrator IO (state write + artifact read) moved to shell scripts

**Decided:** `northstar-write.{ps1,sh}` handles atomic `state.json` writes and STATUS.md rendering; `northstar-read.{ps1,sh}` handles artifact parsing (reading part-dir markdown files and returning a structured JSON summary). The orchestrator invokes these as external scripts via stdin/stdout, not as agent dispatches.

**Why:** both operations are purely mechanical — JSON field extraction, string substitution, atomic file write, template rendering. No reasoning or judgment is required. Implementing them as agents would waste a full subagent context slot (and incur LLM latency) on a deterministic transform. Scripts execute synchronously and return a clear exit code, letting the orchestrator treat a non-zero exit as a hard blocker without a dispatch-verify cycle. The STATUS.md template previously inline in `commands/ns.md` is now owned by `northstar-write`, which reads `tool_version` from the incoming state JSON at runtime — eliminating a third version-sync point from the release checklist.

**Considered alternatives:** an `ns-writer` subagent was considered in the pre-run analysis (`docs/script-extraction-candidates.md`); rejected because the agent dispatch overhead and async return pattern is heavier than the task warrants, and because adding an agent for a deterministic operation would contradict the principle that agents are reserved for tasks requiring LLM judgment (stack discovery, code generation, review). The blocker that surfaced during the original ns-writer design attempt confirmed the approach was wrong-sized for the problem.

---

## 2026-05-20 — Interview stays in the slash command; scan and author move to agents

**Decided:** the multi-turn interview logic remains in `commands/ns-discover.md` (top-level slash command) because `AskUserQuestion` and cross-turn context require the top-level session. Phase 0 (silent grounding scan) moves to `discover-scout`: read-only, one-shot, uses model `claude-haiku-4-5-20251001`, returns a structured summary as its response rather than writing a file — appropriate because it produces no artifact the user needs to inspect or retry, only context the command needs for the interview. Phase 5 (plan-writing) moves to `discover-planner`: write-only, one-shot, consumes the answers file at `.northstar/discover/<slug>.answers.md` — same files-as-IPC contract as all other Northstar roles, keeping the command's context bounded and the plan-writing step independently retryable.

**Why the interview itself cannot be a subagent:** subagents are one-shot; a multi-turn interview requires holding context across `AskUserQuestion` round-trips, which only the top-level session supports.

---

## 2026-05-15 — Orchestrator never improvises for a failing subagent

**Decided:** the orchestrator runs explicit output verification after every `Agent(...)` dispatch. If an artifact is missing, empty, or lacks the role's expected H2 sentinel sections, the orchestrator writes a blocker.md (`from: orchestrator`) and routes to `needs_user`. It does NOT fabricate the missing content.

**Why:** v0.1.1 had a silent-degradation path: if a subagent returned without producing its artifact, the orchestrator would advance to the next phase, where the next subagent would try to read a missing input and either fail itself or — worse — improvise from the Part description alone. That produces cascade hallucinations: a planner with no research, a reviewer with no diff, an auditor with no code. Each step compounds the drift.

Combined with the new "fail-loud preflight" in each role agent (which refuses to proceed if inputs are missing), the verification gate keeps hallucinations contained to one agent's output. The user is notified the moment something goes wrong rather than discovering a corrupted run three Parts later.

**Mechanism:** sentinel-based content checks (e.g. research.md must contain `## Stack conventions` and `## Files to touch`; review.md must contain `## Verdict` with a valid value). Cheap to run, strong enough signal in practice.

---

## 2026-05-14 — Orchestrator lives in the slash command body, not as a subagent

**Decided:** the orchestrator state machine + dispatch logic lives in `commands/northstar.md` (and is mirrored by reference from `commands/ns.md`). It is NOT a Claude Code subagent.

**Why:** Claude Code does not allow a subagent invoked via the Agent tool to spawn further subagents. The v0.1.0 design placed the orchestrator at `agents/northstar.md` expecting it to dispatch the five role subagents. In practice, `/ns` would invoke the orchestrator as a subagent, which then could not actually call researcher/planner/etc. — sessions fell back to driving the pipeline from the top level, defeating the design.

By putting the orchestrator into the slash command body, invoking `/ns` injects the orchestrator prompt into the **top-level** session. The top-level session has the Agent tool and dispatches the five role subagents one level deep. Pipeline tree: top-level → role subagent. Legal.

**Cost:** the orchestrator prompt (~600 lines, ~15K tokens) is in the top-level context per invocation. Acceptable — see `architecture.md` § Context window impact.

**Considered alternatives:**
- Duplicate the orchestrator body across `ns.md` and `northstar.md`. Rejected — maintenance burden.
- Have `ns.md` symlink to `northstar.md`. Rejected — symlinks are awkward on Windows installs.
- Keep the v0.1.0 fallback (top-level session implicitly playing orchestrator). Rejected — the fallback was implicit and undocumented; making it explicit is better.

**Chosen:** `commands/ns.md` reads `commands/northstar.md` at runtime and follows it. Single source of truth in `northstar.md`.

---

## 2026-05-14 — Domain knowledge flows through one channel only

**Decided:** the security-auditor's prompt is intentionally generic — a language-agnostic checklist (auth, authorization, injection, secrets, validation, deep links). Project-specific risks reach it only through the researcher's `Domain risks worth flagging to auditor` section in `research.md`.

**Why:** otherwise every new domain requires forking the auditor prompt. With a single hint channel, the same auditor works for an Expo/Supabase app, a Rust CLI, a Python data pipeline — the researcher discovers what's at stake and tells the auditor.

**Constraint this places on contributors:** never add domain-specific rules to `agents/security-auditor.md`. If you find a recurring risk that's project-specific, surface it as a recommendation in `docs/extending.md` for the researcher's risk-detection heuristics; do not bake it into the auditor.

---

## 2026-05-14 — Files-as-IPC, not return values

**Decided:** every role subagent reads its inputs from disk and writes its output to disk. The orchestrator passes paths in prompts and never echoes artifact bodies into the top-level conversation.

**Why:** subagents produce hundreds of lines per Part. If the orchestrator received their full output as return values and echoed any of it, the top-level context would balloon within a handful of Parts.

The trade-off is small: each subagent does a few extra disk reads/writes. In exchange:

- Orchestrator context bounded regardless of plan size or artifact size.
- Every reasoning step is inspectable on disk — users can read `research.md` mid-run, audit it post-hoc, or rerun a stage from its artifacts.
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

## 2026-05-14 — One Part per tick, hard pause at Part boundaries

**Decided:** each `/ns` invocation in interactive mode advances state by exactly one Part. After each Part completes, the orchestrator ends its turn with an AskUserQuestion ("Continue to Part M?"). No silent advancement.

**Why:** the user (and stakeholders) explicitly required per-Part user approval. Every Part is a checkpoint. This is the system's most important property in interactive mode — it's the reason a user can trust Northstar with a 50-Part plan.

**Escape hatch:** `run-to <part-id>` bypasses per-Part pauses (and planner approval) until the target is reached. Designed for unattended runs. A 20-Part safety cap forces an interactive checkpoint even mid-target so unattended runs cannot go arbitrarily long.

---

## 2026-05-14 — Stack-agnostic role subagents

**Decided:** none of the role subagents (researcher, planner, executer, reviewer, security-auditor) contain language-specific or framework-specific knowledge. The researcher discovers stack conventions at runtime by reading CLAUDE.md / AGENTS.md / README / manifests and surfaces them in `research.md`.

**Why:** the alternative is per-language Northstar variants, which immediately fragment. The runtime-discovery design lets one Northstar install handle TypeScript, Python, Rust, Go, anything — as long as the target project documents itself, the pipeline adapts.

**Constraint this places on contributors:** never add conditional logic based on detected language to a role subagent's prompt. If a role needs language-specific behavior, it should derive it from `research.md`'s stack-conventions section.

---

## 2026-05-14 — User-level install by default, project-level optional

**Decided:** `install.sh` and `install.ps1` default to `~/.claude/`. `--project <path>` installs into `<path>/.claude/` instead.

**Why:** user-level means one install works across every repo on the machine. Most users want Northstar everywhere. Project-level is for two cases: (1) developing Northstar itself (install into the Northstar repo so your working copy overrides any user-level install), (2) pinning a specific version to a specific repo.

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

**Why:** Northstar is a thin coordinator running locally in Claude Code. Telemetry adds privacy concerns, network dependencies, and trust friction for a tool that's supposed to be inspectable. The whole point of the artifacts-on-disk design is "you can see everything Northstar is doing"; adding a phone-home would contradict that.
