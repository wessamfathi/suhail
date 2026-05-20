# Upgrade orchestrator narration UI

The Northstar orchestrator currently narrates in bare single-line sentences with no visual hierarchy. This plan upgrades the narration in `commands/northstar.md` to use agent identity badges, sequential line-by-line narration that exploits Claude's streaming typewriter effect, and Unicode box-drawing cards at structural moments (run start, Part transitions, blockers, end-of-run). The result should feel like a live, well-structured terminal UI without any changes to STATUS.md or subagent prompt files.

Success: run `/ns fixtures/test_plan.md` end-to-end and visually confirm all UI elements appear correctly.

## Narration

### Part 1 — Add agent badges and sequential line-by-line narration

Introduce a fixed emoji+label badge for each agent role and restructure every narration line in `commands/northstar.md` to lead with it. The badge must appear at the very start of the line so Claude's streaming output front-loads the visual hook before the detail trails in.

Badge set (fixed — do not deviate):
- 🧭 Orchestrator
- 🗺️ Scout
- ⚙️ Executer
- 🔎 Reviewer
- 🔒 Auditor

Narration density: medium-to-heavy. Every agent event gets a badge line. Structural orchestrator events (INIT, dispatch, Part complete, abort) also get a badge line.

Where the orchestrator currently emits one sentence for an agent's entire phase, expand to a staggered sequence of 2–4 lines emitted in order — one line per meaningful sub-step — so the output feels live. Examples of stagger sequences to introduce:

Scout phase:
```
🗺️ Scout — starting research for Part N
🗺️ Scout — reading codebase and intel files
🗺️ Scout — writing brief
```

Executer phase:
```
⚙️ Executer — starting Part N
⚙️ Executer — implementing changes
⚙️ Executer — writing execution summary
```

Reviewer + Auditor phase:
```
🔎 Reviewer — checking diff against brief
🔎 Reviewer — verdict: clean ✓
🔒 Auditor — scanning for security risks
🔒 Auditor — verdict: clean ✓
```

The orchestrator's own lines follow the same pattern:
```
🧭 Orchestrator — initializing run
🧭 Orchestrator — Part 2 of 5 complete
🧭 Orchestrator — dispatching Scout for Part 3
```

All existing narration lines must be updated — do not leave bare undecorated sentences anywhere in the orchestrator prompt's narration instructions.

**Depends on:** (none)

**Verification:**
- Manual: run `/ns fixtures/test_plan.md` and confirm every narration line carries a badge and that agent phases emit multiple staggered lines rather than one.

### Part 2 — Add structured Unicode box-drawing cards at key moments

Insert visual frame cards at four structural moments in `commands/northstar.md`. Use Unicode box-drawing characters throughout. All cards use 🧭 Orchestrator badge when emitted by the orchestrator.

**Run header (at INIT, after plan parses successfully):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧭 Northstar  ·  N Parts  ·  G groups
Plan: <plan-path>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Part transition card (after Reviewer+Auditor verdicts, before the continue/skip/abort prompt):**
```
┌─────────────────────────────────────────────┐
│  ✅ Part N of M — <Title>  (complete)       │
│  Reviewer: clean  ·  Auditor: clean         │
├─────────────────────────────────────────────┤
│  ▶ Next: Part N+1 — <Title>                │
│  Group: <group>  ·  Depends on: (none)      │
└─────────────────────────────────────────────┘
```

Adapt the Reviewer/Auditor lines to reflect actual verdicts (clean ✓ / flagged ⚠️ / skipped). Use 🟢 for clean, 🟡 for flagged, ⚪ for skipped.

**Blocker card (when Scout or Executer raises a blocker):**
```
╔══════════════════════════════════════════╗
║  🔴 BLOCKER — Part N — <Title>          ║
╠══════════════════════════════════════════╣
║  What's blocked:  <one line>            ║
║  Needs from you:  <one line>            ║
║  Suggested fix:   <one line>            ║
╚══════════════════════════════════════════╝
```

**End-of-run summary card (after all Parts are done/skipped/aborted):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏁 Run complete  ·  N/M done  ·  K skipped
Reviewer: all clean  ·  Auditor: N flags
Open questions: N  (see STATUS.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Status dot legend used across all cards: 🟢 done · 🔵 active · 🟡 flagged/skipped · 🔴 blocked · ⚪ pending/not run.

**Depends on:** Part 1

**Verification:**
- Manual: run `/ns fixtures/test_plan.md` end-to-end and confirm: run header appears at INIT, a transition card appears after each Part completes, blocker card appears if a blocker is triggered, and end-of-run summary appears at completion.
