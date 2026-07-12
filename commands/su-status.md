---
description: Print the current Suhail run's status dashboard. Read-only — never advances state.
---

# /su-status — Suhail status dashboard

You are printing the current Suhail run's status. This command takes no arguments. It reads `.suhail/STATUS.md` and emits it verbatim. It is strictly read-only: it never advances state, dispatches a subagent, or writes any file.

## On every invocation

1. **No active run.** Attempt to Read `.suhail/state.json`. If it does not exist, end with one sentence: "No active Suhail run found — run `/su <plan-path>` to start one."
2. **Status not yet rendered.** If `.suhail/state.json` exists but `.suhail/STATUS.md` does not, end with one sentence: "A run exists but `STATUS.md` has not been rendered yet — run `/su` to advance one tick and regenerate it."
3. **Emit.** Read `.suhail/STATUS.md` and emit its contents verbatim to the user. Do not summarize, reformat, or annotate. End the turn.

## Don't

- Do not advance state, dispatch any subagent, or write any file. This command is read-only.
- Do not accept any arguments. This command is zero-argument; ignore `$ARGUMENTS` entirely.
- Do not regenerate `STATUS.md` yourself — that is `suhail-write`'s job, triggered by `/su`. If it is stale or missing, point the user at `/su`.
- Do not echo `state.json` instead of `STATUS.md`. `STATUS.md` is the human-readable view.
