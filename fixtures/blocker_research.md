# Northstar Self-Test — Blocker Protocol

Tests the blocker-resolution flow. Contains one Part whose description deliberately references a file that does not exist. A correctly-implemented researcher should detect this and write `blocker.md` instead of inventing — and the orchestrator should surface the blocker to the user with the researcher's options.

Run with:
```
/ns fixtures/blocker_research.md
```

**Expected behavior:**
1. After INIT, Northstar starts Part 1 and dispatches the researcher.
2. The researcher discovers that `nonexistent_module/totally_imaginary.ts` does not exist anywhere in the repo.
3. The researcher writes `.northstar/parts/part-1/blocker.md` with frontmatter:
   ```
   ---
   from: researcher
   severity: blocker
   options: ["<option A>", "<option B>", "<option C>"]
   ---
   <one-paragraph explanation that the referenced file does not exist>
   ```
4. The orchestrator detects the blocker, sets state to `needs_user`, and ends its turn with an AskUserQuestion presenting the researcher's options plus "Other (free text)".
5. Answer with any option. The orchestrator should:
   - Append `resolution: <your answer>` to the blocker.md file.
   - Add an entry to `global_decisions` in state.json.
   - Re-dispatch the researcher (since the blocker was from researcher) with the resolution context.
6. The second researcher run should produce a complete `research.md` (likely noting the resolution and adapting).
7. Pipeline continues from planning through completion.

**This fixture cannot be fully automated** — by design, it requires a human (you) to pick an answer at the AskUserQuestion step.

**Optional second run:** edit the Part below to add more plausible context, then `/ns retry` to re-run Part 1 and confirm the blocker doesn't re-trigger.

After verifying, clean up:
```powershell
/ns-abort
Remove-Item -Recurse -Force .northstar
Remove-Item -Force .northstar-blocker-test.txt -ErrorAction SilentlyContinue
```

## Blocker Test

### Part 1 — Modify the imaginary module

Update the file `nonexistent_module/totally_imaginary.ts` to export a new function called `imaginaryFunction()`. The function should reuse the helper `nonExistentHelper()` from `also_nonexistent/helpers.ts`. After modifying the file, create `.northstar-blocker-test.txt` containing the single line `blocker test ok`.

**Depends on:** (none)

**Verification:**
- The modifications described above are present.
- Contents of `.northstar-blocker-test.txt` equal `blocker test ok\n`.

(Note: this Part is intentionally impossible as written. The researcher should detect that neither `nonexistent_module/totally_imaginary.ts` nor `also_nonexistent/helpers.ts` exist and flag a blocker rather than inventing the files.)
