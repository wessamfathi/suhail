# northstar-tick.ps1 — read-only state inspector for Northstar.
#
# Usage:
#   northstar-tick.ps1 <path/to/state.json>
#   northstar-tick.ps1 --help
#
# Exit codes:
#   0  directive JSON emitted to stdout
#   1  state.json missing, unreadable, or unparseable
#   2  unknown run_phase encountered
#
# Output: a single-line JSON object, e.g.:
#   {"action":"dispatch_scout","part_id":"part-1"}
#   {"action":"await_approval"}
#   {"action":"complete"}
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
        Write-Output "northstar-tick.ps1 — read-only state inspector for Northstar."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output "  northstar-tick.ps1 <path/to/state.json>"
        Write-Output "  northstar-tick.ps1 --help"
        Write-Output ""
        Write-Output "Exit codes:"
        Write-Output "  0  directive JSON emitted to stdout"
        Write-Output "  1  state.json missing, unreadable, or unparseable"
        Write-Output "  2  unknown run_phase encountered"
        Write-Output ""
        Write-Output "Output: a single-line JSON object, e.g.:"
        Write-Output '  {"action":"dispatch_scout","part_id":"part-1"}'
        Write-Output '  {"action":"await_approval"}'
        Write-Output '  {"action":"complete"}'
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
    [Console]::Error.WriteLine("error: usage: northstar-tick.ps1 <path/to/state.json>")
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

function Execution-Exists {
    param([string]$PartId)
    $execDir = Join-Path $stateDir "parts\$PartId"
    if (-not (Test-Path $execDir)) { return $false }
    $matches = Get-ChildItem -Path $execDir -Filter "execution*.md" -ErrorAction SilentlyContinue
    return ($null -ne $matches -and $matches.Count -gt 0)
}

function Review-Exists {
    param([string]$PartId)
    return Test-Path (Join-Path $stateDir "parts\$PartId\review.md")
}

# ---------------------------------------------------------------------------
# state-transition logic
# ---------------------------------------------------------------------------

switch ($runPhase) {

    "init" {
        Write-Output '{"action":"start_batch_scouting"}'
    }

    "batch_scouting" {
        $pendingPart = $null
        foreach ($part in $stateJson.parts) {
            if ($part.status -eq "scouting" -or $part.status -eq "pending") {
                $pendingPart = $part.id
                break
            }
        }

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

    "executing" {
        if ($aborted -eq $true) {
            Write-Output '{"action":"aborted"}'
            exit 0
        }

        if ($null -eq $currentPartId -or $currentPartId -eq "null" -or $currentPartId -eq "") {
            Write-Output '{"action":"noop","reason":"no current_part_id in executing phase"}'
            exit 0
        }

        $currentStep = $null
        foreach ($part in $stateJson.parts) {
            if ($part.id -eq $currentPartId) {
                $currentStep = $part.status
                break
            }
        }

        switch ($currentStep) {
            { $_ -eq "pending" -or $_ -eq "scouting" } {
                if (Brief-Exists $currentPartId) {
                    Write-Output "{`"action`":`"dispatch_executer`",`"part_id`":`"$currentPartId`"}"
                } else {
                    Write-Output "{`"action`":`"dispatch_scout`",`"part_id`":`"$currentPartId`"}"
                }
            }
            "executing" {
                if (Execution-Exists $currentPartId) {
                    Write-Output "{`"action`":`"dispatch_verifier`",`"part_id`":`"$currentPartId`"}"
                } else {
                    Write-Output "{`"action`":`"dispatch_executer`",`"part_id`":`"$currentPartId`"}"
                }
            }
            "verifying" {
                if (Review-Exists $currentPartId) {
                    Write-Output "{`"action`":`"advance_after_review`",`"part_id`":`"$currentPartId`"}"
                } else {
                    Write-Output "{`"action`":`"dispatch_verifier`",`"part_id`":`"$currentPartId`"}"
                }
            }
            { $_ -eq "awaiting_plan_approval" -or $_ -eq "awaiting_part_approval" } {
                Write-Output "{`"action`":`"await_approval`",`"part_id`":`"$currentPartId`"}"
            }
            "needs_user" {
                Write-Output "{`"action`":`"needs_user`",`"part_id`":`"$currentPartId`"}"
            }
            { $_ -eq "completed" -or $_ -eq "skipped" } {
                $nextPart = $null
                foreach ($part in $stateJson.parts) {
                    if ($part.status -eq "pending" -or $part.status -eq "scouting" -or
                        $part.status -eq "executing" -or $part.status -eq "verifying") {
                        $nextPart = $part.id
                        break
                    }
                }
                if ($null -eq $nextPart) {
                    Write-Output '{"action":"complete","reason":"all parts terminal"}'
                } else {
                    Write-Output "{`"action`":`"advance_to_part`",`"part_id`":`"$nextPart`"}"
                }
            }
            default {
                Write-Output "{`"action`":`"noop`",`"reason`":`"unrecognised part status: $currentStep`",`"part_id`":`"$currentPartId`"}"
            }
        }
    }

    "verifying" {
        if ($null -eq $currentPartId -or $currentPartId -eq "null" -or $currentPartId -eq "") {
            Write-Output '{"action":"noop","reason":"no current_part_id in verifying phase"}'
            exit 0
        }
        if (Review-Exists $currentPartId) {
            Write-Output "{`"action`":`"advance_after_review`",`"part_id`":`"$currentPartId`"}"
        } else {
            Write-Output "{`"action`":`"dispatch_verifier`",`"part_id`":`"$currentPartId`"}"
        }
    }

    "needs_user" {
        Write-Output "{`"action`":`"needs_user`",`"part_id`":`"$currentPartId`"}"
    }

    { $_ -eq "completed" -or $_ -eq "complete" } {
        Write-Output '{"action":"complete"}'
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
