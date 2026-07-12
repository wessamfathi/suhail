# Suhail Skip-Flow Fixture

Tests the `/su-skip` command. A contributor runs `/su`, lets Part 1 complete normally, then invokes `/su-skip` when the orchestrator pauses between Parts to skip Part 2. The run should complete with Part 1 marked `completed` and Part 2 marked `skipped` in `STATUS.md`, and only Part 1's marker file present on disk.

Run with:

```
/su fixtures/skip_flow.md
```

**Expected behavior:**
1. INIT parses two Parts and initialises `STATUS.md`.
2. Part 1 executes: scout, executer, and verifier run in order; `.suhail-skip-1.txt` is created.
3. Orchestrator pauses and prompts to continue. **This is the manual step.** Type `/su-skip` instead of confirming Continue. The orchestrator marks Part 2 `skipped` and advances to completion.
4. Part 2 is marked `skipped` in `.suhail/STATUS.md`; the executer is never invoked for Part 2.
5. `.suhail/STATUS.md` shows Part 1 `completed` and Part 2 `skipped`.
6. `.suhail-skip-2.txt` is NOT created (Part 2 never ran).

Note: This fixture requires a manual step. See step 3 above.

After verifying, clean up:

```powershell
/su-abort
Remove-Item -Recurse -Force .suhail
Remove-Item -Force .suhail-skip-*.txt -ErrorAction SilentlyContinue
# Note: .suhail-skip-*.txt is not covered by .gitignore -- delete these files before any git operations.
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