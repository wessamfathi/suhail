# suhail-tick.ps1 — read-only state inspector for Suhail.
#
# Usage:
#   suhail-tick.ps1 <path/to/state.json>
#   suhail-tick.ps1 --help
#
# Exit codes:
#   0  directive JSON emitted to stdout
#   1  state.json missing, unreadable, unparseable, or lacking a parts array
#   2  unknown run_phase encountered
#   3  unroutable Part status in the current batch (fail-closed guard —
#      an unknown status must never be reported as batch completion)
#
# Output: a single-line JSON object, e.g.:
#   {"action":"dispatch_scout","part_id":"part-1"}
#   {"action":"await_approval","reason":"part_plan_approval","part_id":"part-1"}
#   {"action":"complete"}
#   {"action":"finished"}
#   {"action":"noop","reason":"<text>"}

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# argument parsing — help flag and positional state path
# ---------------------------------------------------------------------------

$StatePath = ""

foreach ($arg in $RemainingArgs) {
    if ($arg -eq "-h" -or $arg -eq "--help") {
        Write-Output "suhail-tick.ps1 — read-only state inspector for Suhail."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output "  suhail-tick.ps1 <path/to/state.json>"
        Write-Output "  suhail-tick.ps1 --help"
        Write-Output ""
        Write-Output "Exit codes:"
        Write-Output "  0  directive JSON emitted to stdout"
        Write-Output "  1  state.json missing, unreadable, unparseable, or lacking a parts array"
        Write-Output "  2  unknown run_phase encountered"
        Write-Output "  3  unroutable Part status in the current batch (fail-closed guard)"
        Write-Output ""
        Write-Output "Output: a single-line JSON object, e.g.:"
        Write-Output '  {"action":"dispatch_scout","part_id":"part-1"}'
        Write-Output '  {"action":"await_approval","reason":"part_plan_approval","part_id":"part-1"}'
        Write-Output '  {"action":"complete"}'
        Write-Output '  {"action":"finished"}'
        Write-Output '  {"action":"noop","reason":"<text>"}'
        exit 0
    } elseif ($arg.StartsWith("-")) {
        [Console]::Error.WriteLine("error: unknown argument: $arg")
        exit 1
    } elseif ($StatePath -ne "") {
        [Console]::Error.WriteLine("error: unexpected extra argument: $arg")
        exit 1
    } else {
        $StatePath = $arg
    }
}

if ($StatePath -eq "") {
    [Console]::Error.WriteLine("error: usage: suhail-tick.ps1 <path/to/state.json>")
    exit 1
}

if (-not (Test-Path $StatePath)) {
    [Console]::Error.WriteLine("error: state file not found: $StatePath")
    exit 1
}

# ---------------------------------------------------------------------------
# parse state.json
# ---------------------------------------------------------------------------

$stateJson = $null
try {
    $raw = Get-Content -Raw $StatePath
    $stateJson = $raw | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("error: state file is not valid JSON: $StatePath")
    exit 1
}

if ($null -eq $stateJson.parts -or $stateJson.parts -isnot [System.Array]) {
    [Console]::Error.WriteLine("error: state file has no parts array: $StatePath")
    exit 1
}

$runPhase       = if ($null -ne $stateJson.run_phase)        { $stateJson.run_phase }        else { "unknown" }
$currentPartId  = if ($null -ne $stateJson.current_part_id)  { $stateJson.current_part_id }  else { $null }
$batchAutoApprove = if ($null -ne $stateJson.batch_auto_approve) { $stateJson.batch_auto_approve } else { $false }
$aborted        = if ($null -ne $stateJson.aborted)          { $stateJson.aborted }          else { $false }

$stateDir = Split-Path -Parent (Resolve-Path $StatePath)

# ---------------------------------------------------------------------------
# artifact path helpers
# ---------------------------------------------------------------------------

function Brief-Exists {
    param([string]$PartId)
    return Test-Path (Join-Path $stateDir "parts\$PartId\brief.md")
}

# ---------------------------------------------------------------------------
# batch helpers (execute/verify cycle for the current level's parts)
# ---------------------------------------------------------------------------

# Batch-First — lowest-numbered part in current_batch whose status is one of
# the given statuses. Empty current_batch falls back to all parts (defensive).
function Batch-First {
    param([string[]]$Statuses)
    $batch = @()
    if ($null -ne $stateJson.current_batch) { $batch = @($stateJson.current_batch) }
    foreach ($part in $stateJson.parts) {
        if ($Statuses -contains $part.status) {
            if ($batch.Count -eq 0 -or $batch -contains $part.id) {
                return $part.id
            }
        }
    }
    return $null
}

# Batch-Directive — shared routing for the executing and batch_verifying
# phases. Executers run serially; verification is dispatched once the whole
# batch has executed; the batch completes once every part is terminal.
function Batch-Directive {
    if ($aborted -eq $true) {
        Write-Output '{"action":"aborted"}'
        return
    }

    $p = Batch-First @("needs_user")
    if ($null -ne $p) {
        Write-Output "{`"action`":`"needs_user`",`"part_id`":`"$p`"}"
        return
    }

    # Any part still needing execution (or a brief) — dispatch it, serially.
    $p = Batch-First @("executing", "pending", "scouting")
    if ($null -ne $p) {
        if (Brief-Exists $p) {
            Write-Output "{`"action`":`"dispatch_executer`",`"part_id`":`"$p`"}"
        } else {
            Write-Output "{`"action`":`"dispatch_scout`",`"part_id`":`"$p`"}"
        }
        return
    }

    # Approved-but-ungated Parts: surface the per-Part plan-approval gate.
    # (Distinct reason from the batch master_plan_approval gate so the
    # orchestrator can route it — see su.md's await_approval handlers.)
    $p = Batch-First @("awaiting_plan_approval")
    if ($null -ne $p) {
        Write-Output "{`"action`":`"await_approval`",`"reason`":`"part_plan_approval`",`"part_id`":`"$p`"}"
        return
    }

    # All executed, none pending verification-dispatch yet — verify the batch.
    $p = Batch-First @("executed")
    if ($null -ne $p) {
        Write-Output '{"action":"start_batch_verifying"}'
        return
    }

    # Verifiers dispatched but results not yet processed by the orchestrator.
    $p = Batch-First @("verifying")
    if ($null -ne $p) {
        Write-Output '{"action":"noop","reason":"verifiers in flight for batch"}'
        return
    }

    # Fail closed: only positively-terminal Parts may complete the batch.
    # Any status the queries above did not route must be an error — a typo or
    # future status addition must never masquerade as batch completion.
    $batch = @()
    if ($null -ne $stateJson.current_batch) { $batch = @($stateJson.current_batch) }
    foreach ($part in $stateJson.parts) {
        if ($batch.Count -eq 0 -or $batch -contains $part.id) {
            if ($part.status -ne "completed" -and $part.status -ne "skipped") {
                [Console]::Error.WriteLine("error: $($part.id) has unroutable status $($part.status)")
                exit 3
            }
        }
    }

    # Every batch part is completed or skipped — advance the level.
    Write-Output '{"action":"complete"}'
}

# ---------------------------------------------------------------------------
# state-transition logic
# ---------------------------------------------------------------------------

switch ($runPhase) {

    "init" {
        Write-Output '{"action":"start_batch_scouting"}'
    }

    "batch_scouting" {
        # First part in the CURRENT BATCH still needing a scout/brief. Parts
        # at future levels are pending too — they must not be scouted early.
        $pendingPart = Batch-First @("scouting", "pending")

        if ($null -eq $pendingPart) {
            Write-Output '{"action":"await_approval","reason":"all parts scouted"}'
        } elseif (Brief-Exists $pendingPart) {
            Write-Output "{`"action`":`"advance_scouting`",`"part_id`":`"$pendingPart`"}"
        } else {
            Write-Output "{`"action`":`"dispatch_scout`",`"part_id`":`"$pendingPart`"}"
        }
    }

    { $_ -eq "master_plan_approval" -or $_ -eq "awaiting_plan_approval" } {
        Write-Output '{"action":"await_approval","reason":"master_plan_approval"}'
    }

    { $_ -eq "executing" -or $_ -eq "batch_verifying" } {
        # Batched execute/verify cycle over the current level's parts.
        Batch-Directive
    }

    "needs_user" {
        Write-Output "{`"action`":`"needs_user`",`"part_id`":`"$currentPartId`"}"
    }

    { $_ -eq "completed" -or $_ -eq "complete" } {
        Write-Output '{"action":"complete"}'
    }

    "finished" {
        # Terminal: the run already completed cleanly. The orchestrator says
        # so in one sentence and ends the turn — no blocker, no re-dispatch.
        Write-Output '{"action":"finished"}'
    }

    "aborted" {
        Write-Output '{"action":"aborted"}'
    }

    default {
        [Console]::Error.WriteLine("error: unknown run_phase: $runPhase")
        exit 2
    }
}

exit 0
