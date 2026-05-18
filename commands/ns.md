---
description: Alias for /northstar. Same arguments and behavior.
argument-hint: <plan-path> | autorun <plan-path> | (empty) | status | skip | retry | run-to <part-id> | abort
---

# /ns

This is the short-form alias for `/northstar`. The two commands behave identically.

**Read the file `northstar.md` in the same directory as this command file and follow its instructions exactly, with these arguments:**

`$ARGUMENTS`

Locate `northstar.md` by checking these paths in order:
1. The same directory as this command file (sibling).
   - Project install: `<repo>/.claude/commands/northstar.md`.
   - User install: `~/.claude/commands/northstar.md`.
2. If neither path is found, end with an error message instructing the user to reinstall Northstar.

After reading, execute the orchestrator logic in `northstar.md` as if it were the body of this command. Do not duplicate or summarize the content here — the canonical instructions live in `northstar.md` so the two commands stay in sync.
