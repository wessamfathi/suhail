# Suhail Self-Test — Blocker Protocol

Tests the blocker-resolution flow. Contains one Part whose description deliberately references a file that does not exist. A correctly-implemented su-scout should detect this and write `blocker.md` instead of inventing. The orchestrator should then surface the blocker to the user with the su-scout's options.

Run with:
```
/su fixtures/blocker_research.md
```

**Expected behavior:**
1. After INIT, Suhail starts Part 1 and dispatches the su-scout.
2. The su-scout discovers that `nonexistent_module/totally_imaginary.ts` does not exist anywhere in the repo.
3. The su-scout writes `.suhail/parts/part-1/blocker.md` with frontmatter:
   ```
   ---
   from: su-scout
   severity: blocker
   options: ["<option A>", "<option B>", "<option C>"]
   ---
   <one-paragraph explanation that the referenced file does not exist>
   ```
4. The orchestrator detects the blocker, sets state to `needs_user`, and ends its turn with an AskUserQuestion presenting the su-scout's options plus "Other (free text)".
5. Answer with any option. The orchestrator should:
   - Append `resolution: <your answer>` to the blocker.md file.
   - Add an entry to `global_decisions` in state.json.
   - Re-dispatch the su-scout (since the blocker was from su-scout) with the resolution context.
6. The second su-scout run should produce a complete `brief.md` (likely noting the resolution and adapting).
7. Pipeline continues from execution through completion.

**This fixture cannot be fully automated** — by design, it requires a human (you) to pick an answer at the AskUserQuestion step.

**Optional second run:** edit the Part below to add more plausible context, then `/su retry` to re-run Part 1 and confirm the blocker doesn't re-trigger.

After verifying, clean up:
```powershell
/su-abort
Remove-Item -Recurse -Force .suhail
Remove-Item -Force .suhail-blocker-test.txt -ErrorAction SilentlyContinue
```

## Blocker Test

### Part 1 — Modify the imaginary module

Update the file `nonexistent_module/totally_imaginary.ts` to export a new function called `imaginaryFunction()`. The function should reuse the helper `nonExistentHelper()` from `also_nonexistent/helpers.ts`. After modifying the file, create `.suhail-blocker-test.txt` containing the single line `blocker test ok`.

**Depends on:** (none)

**Verification:**
- The modifications described above are present.
- Contents of `.suhail-blocker-test.txt` equal `blocker test ok\n`.

(Note: this Part is intentionally impossible as written. The su-scout should detect that neither `nonexistent_module/totally_imaginary.ts` nor `also_nonexistent/helpers.ts` exist and flag a blocker rather than inventing the files.)
