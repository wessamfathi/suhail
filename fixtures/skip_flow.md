# Suhail Skip-Flow Fixture

Tests the `/su-skip` command. A contributor runs `/su`, lets Part 1 complete normally, then invokes `/su-skip` when the orchestrator pauses between Parts to skip Part 2. The run should complete with Part 1 marked `completed` and Part 2 marked `skipped` in `STATUS.md`, and only Part 1's marker file present on disk.

Run with:

```
/su fixtures/skip_flow.md
```

**Expected behavior:**
1. INIT parses two Parts (Part 2 depends on Part 1, so each is its own dependency level) and initialises `STATUS.md`.
2. Part 1's level runs: scout, master-plan approval, executer, verifier; `.suhail-skip-1.txt` is created, Part 1 gets its commit and transition card.
3. The orchestrator pauses at the level checkpoint ("Level 0 complete. Continue to level 1 (Part 2)?"). **This is the manual step.** Type `/su-skip` instead of choosing Continue. Because Part 1 is already terminal, `/su-skip` targets the next eligible Part — Part 2 — and marks it `skipped`.
4. Part 2 is marked `skipped` in `.suhail/STATUS.md`; the executer is never invoked for Part 2.
5. `.suhail/STATUS.md` shows Part 1 `completed` and Part 2 `skipped`; the run completes.
6. `.suhail-skip-2.txt` is NOT created (Part 2 never ran).

Note: This fixture requires a manual step. See step 3 above.

After verifying, clean up (`.suhail-*.txt` markers are gitignored, so nothing can be committed accidentally):

```powershell
/su-abort
Remove-Item -Recurse -Force .suhail
Remove-Item -Force .suhail-skip-*.txt -ErrorAction SilentlyContinue
# (POSIX: rm -rf .suhail && rm -f .suhail-skip-*.txt)
```

## Skip Flow

### Part 1 — Write first skip marker

Create `.suhail-skip-1.txt` in the current working directory containing the single line `skip flow step 1`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

**Depends on:** (none)

**Verification:**
- Contents of `.suhail-skip-1.txt` equal `skip flow step 1\n`.

### Part 2 — Write second skip marker

Create `.suhail-skip-2.txt` in the current working directory containing the single line `skip flow step 2`. If the file already exists, overwrite it. The file should contain exactly that line followed by a single trailing newline.

This Part is expected to be skipped by the contributor using `/su-skip` -- it should NOT execute and `.suhail-skip-2.txt` should NOT be created on disk.

**Depends on:** Part 1

**Verification:**
- If this Part ran (not skipped): contents of `.suhail-skip-2.txt` equal `skip flow step 2\n`.
- If skipped (expected outcome): `.suhail-skip-2.txt` does not exist and `STATUS.md` shows this Part as `skipped`.