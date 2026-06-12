---
name: lvlup-ns-state-lifecycle
description: Clean up Northstar run state without destroying the intel cache. Use when /ns or /ns-discover refuses to start because of a leftover .northstar/state.json, or when cleaning up after a finished/aborted run.
version: 1.0.0
license: MIT
---

# Northstar state lifecycle

1. **`.northstar/state.json` blocks ALL new runs** — even when the prior run
   completed fully, and even after `/ns-abort` (abort only sets
   `"aborted": true`; it does not delete state).
2. **Don't use the documented `rm -rf .northstar`** unless you want fresh
   intel — it destroys prior-run artifacts AND the `/ns-init` intel cache,
   forcing a full (slow) intel regen.
3. **Surgical cleanup that preserves intel:**
   ```bash
   rm -f .northstar/state.json .northstar/STATUS.md && rm -rf .northstar/parts
   ```
   `.northstar/intel/` survives, so the precursor check still passes.
4. Full `rm -rf .northstar` only when the pipeline version changed and intel
   should be regenerated under the new version.
5. Related: re-check for `.northstar/` existence on EVERY invocation — it may
   have been deleted between turns (see global skill
   lvlup-precondition-recheck-per-turn).
