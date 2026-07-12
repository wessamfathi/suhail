# Suhail Self-Test — Multi-Part with Dependencies

Tests dependency parsing and ordered execution. Three Parts, where Part 3 depends on Parts 1 and 2, and Part 2 depends on Part 1.

Run with:
```
/su fixtures/multi_part_deps.md
```

**Expected behavior:**
- After INIT, Suhail starts with Part 1 (the only Part with no unmet deps).
- After Part 1 completes, the user is prompted to continue. Choosing Continue → Part 2.
- After Part 2 completes, prompted again. Continue → Part 3.
- After Part 3, prompted with "All Parts completed."
- Final artifacts in working dir: `.suhail-deps-1.txt`, `.suhail-deps-2.txt`, `.suhail-deps-3.txt`, each containing the marker shown below.
- Suhail's STATUS.md shows all three Parts ✅ completed at the end.

**Alternative run:** try `/su run-to part-3` instead. The pipeline should auto-advance through all three Parts without per-Part pauses, then revert to interactive mode and prompt at the end.

After verifying, clean up:
```powershell
/su-abort
Remove-Item -Recurse -Force .suhail
Remove-Item -Force .suhail-deps-*.txt -ErrorAction SilentlyContinue
```

## Dependency Chain

### Part 1 — First marker

Create `.suhail-deps-1.txt` in the current working directory containing the single line `dep step 1`.

**Depends on:** (none)

**Verification:**
- Contents of `.suhail-deps-1.txt` equal `dep step 1\n`.

### Part 2 — Second marker

Create `.suhail-deps-2.txt` in the current working directory containing the single line `dep step 2`.

**Depends on:** Part 1

**Verification:**
- Contents of `.suhail-deps-2.txt` equal `dep step 2\n`.
- `.suhail-deps-1.txt` from Part 1 still exists.

### Part 3 — Final marker

Create `.suhail-deps-3.txt` in the current working directory containing the single line `dep step 3`.

**Depends on:** Part 1, Part 2

**Verification:**
- Contents of `.suhail-deps-3.txt` equal `dep step 3\n`.
- Both `.suhail-deps-1.txt` and `.suhail-deps-2.txt` still exist.
