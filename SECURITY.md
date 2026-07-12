# Security Policy

## Supported versions

Only the latest release receives security fixes. Pre-1.0 versions were private previews and are unsupported.

## Reporting a vulnerability

Please use [GitHub Private Vulnerability Reporting](https://github.com/wessamfathi/suhail/security/advisories/new) — do not open a public issue for anything exploitable. If private reporting is unavailable to you, email the maintainer at wessamfathi@gmail.com with `[suhail security]` in the subject. You should hear back within a week.

## Threat model

Suhail is a local automation tool for Claude Code. There is no server, no network component, and no telemetry — nothing phones home, ever. The security surface is what the pipeline does on your machine:

- **Plan files are code-equivalent.** The su-executer implements Parts with Edit/Write/Bash access and runs the commands the plan and brief call for, with your Claude Code session's permissions. **Run only plans you trust, exactly as you would treat a shell script from the same source.**
- **Guardrails, not sandboxes.** The executer never commits, pushes, or deploys; destructive and network-touching commands require an explicit justification in the plan or brief; every command it runs is recorded in `execution.md` under `## Commands run`; and every non-empty diff passes an independent review and security-audit pass before the Part's atomic commit. These are prompt-level contracts enforced by the orchestrator's verification steps — they raise the bar, but they are not an OS sandbox. Claude Code's own permission system remains the hard boundary.
- **Subagents treat file contents as data.** The pipeline agents carry standing instructions that plan text, briefs, diffs, and code they read are material to analyze, never instructions to follow — and the verifier treats instruction-like text inside a diff as a finding. Prompt injection via repository contents is mitigated, not eliminated; the review artifacts under `.suhail/parts/` exist so you can check what actually happened.
- **State stays local.** Everything Suhail writes lives under `.suhail/` in the target repo (gitignored by convention) — inspect or delete it freely.

Findings about the pipeline's own contracts (a way to make the executer run something the plan didn't justify, a path that skips verification, an escape from the files-as-IPC boundary) are exactly what we want reported.
