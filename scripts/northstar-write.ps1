# northstar-write.ps1 — atomic state writer and STATUS.md renderer for Northstar.
#
# Usage:
#   northstar-write.ps1 <path/to/state.json>    # JSON payload on stdin
#   northstar-write.ps1 --help
#
# Exit codes:
#   0  state.json and STATUS.md written successfully
#   1  bad JSON on stdin, missing arg, or parse failure
#   2  write failure (disk error, permission denied)
#
# Output:
#   Writes state.json atomically (via tmp + Move-Item) to the specified path.
#   Writes STATUS.md as a sibling of state.json in the same directory.
#
# Note: if the script crashes between writing state.json and writing STATUS.md,
# the two files may be out of sync. STATUS.md is a view only; state.json is the
# source of truth.

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
        Write-Output "northstar-write.ps1 — atomic state writer and STATUS.md renderer for Northstar."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output "  northstar-write.ps1 <path/to/state.json>"
        Write-Output "  northstar-write.ps1 --help"
        Write-Output ""
        Write-Output "Exit codes:"
        Write-Output "  0  state.json and STATUS.md written successfully"
        Write-Output "  1  bad JSON on stdin, missing arg, or parse failure"
        Write-Output "  2  write failure (disk error, permission denied)"
        Write-Output ""
        Write-Output "Output:"
        Write-Output "  Writes state.json atomically to the specified path."
        Write-Output "  Writes STATUS.md as a sibling of state.json."
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
    [Console]::Error.WriteLine("error: usage: northstar-write.ps1 <path/to/state.json>")
    exit 1
}

# ---------------------------------------------------------------------------
# read and validate stdin payload
# ---------------------------------------------------------------------------

$inputContent = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($inputContent)) {
    [Console]::Error.WriteLine("error: no JSON payload on stdin")
    exit 1
}

$payload = $null
try {
    $payload = $inputContent | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("error: stdin payload is not valid JSON: $_")
    exit 1
}

# ---------------------------------------------------------------------------
# derive directory
# ---------------------------------------------------------------------------

# Resolve parent directory; StatePath may not exist yet so use string ops
$stateDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($StatePath))

# ---------------------------------------------------------------------------
# atomic write of state.json
# ---------------------------------------------------------------------------

$tmpPath = "$StatePath.tmp"

try {
    [System.IO.File]::WriteAllText($tmpPath, $inputContent, [System.Text.Encoding]::UTF8)
    Move-Item -Path $tmpPath -Destination $StatePath -Force
} catch {
    [Console]::Error.WriteLine("error: failed to write state file: $_")
    exit 2
}

# ---------------------------------------------------------------------------
# helper: Get-StatusEmoji
# ---------------------------------------------------------------------------

function Get-StatusEmoji {
    param([string]$Status)
    switch ($Status) {
        "completed"  { return [char]::ConvertFromUtf32(0x2705) }    # ✅
        "executing"  { return [char]::ConvertFromUtf32(0x1F504) }   # 🔄
        "scouting"   { return [char]::ConvertFromUtf32(0x1F504) }   # 🔄
        "verifying"  { return [char]::ConvertFromUtf32(0x1F504) }   # 🔄
        "pending"    { return [char]::ConvertFromUtf32(0x23F8) }    # ⏸
        "skipped"    { return [char]::ConvertFromUtf32(0x23ED) }    # ⏭
        "needs_user" { return [char]::ConvertFromUtf32(0x1F6D1) }   # 🛑
        "aborted"    { return [char]::ConvertFromUtf32(0x274C) }    # ❌
        "finished"   { return [char]::ConvertFromUtf32(0x1F3C1) }   # 🏁
        default      { return [char]::ConvertFromUtf32(0x23F8) }    # ⏸
    }
}

# ---------------------------------------------------------------------------
# extract fields from payload
# ---------------------------------------------------------------------------

$toolVersion   = if ($null -ne $payload.tool_version)   { $payload.tool_version }   else { "unknown" }
$planPath      = if ($null -ne $payload.plan_path)       { $payload.plan_path }       else { "" }
# Extract updated_at as raw string to avoid ConvertFrom-Json DateTime coercion
$updatedAt = ""
if ($inputContent -match '"updated_at"\s*:\s*"([^"]*)"') {
    $updatedAt = $Matches[1]
} elseif ($null -ne $payload.updated_at) {
    $updatedAt = "$($payload.updated_at)"
}
$nsMode        = if ($null -ne $payload.mode)            { $payload.mode }            else { "interactive" }
$runPhase      = if ($null -ne $payload.run_phase)       { $payload.run_phase }       else { "unknown" }
$currentPartId = if ($null -ne $payload.current_part_id) { $payload.current_part_id } else { $null }
$maxRetries    = if ($null -ne $payload.max_retries)     { $payload.max_retries }     else { 3 }
$currentBatch  = if ($null -ne $payload.current_batch)   { $payload.current_batch }   else { @() }
$parts         = if ($null -ne $payload.parts)           { $payload.parts }           else { @() }

$planFilename = [System.IO.Path]::GetFileName($planPath)

# ---------------------------------------------------------------------------
# CURRENT_LINE construction
# ---------------------------------------------------------------------------

function Get-BatchInfo {
    param($Batch, $Parts)
    $ids = @($Batch) -join ", "
    $level = 0
    if ($Batch -and @($Batch).Count -gt 0) {
        $firstId = @($Batch)[0]
        foreach ($part in $Parts) {
            if ($part.id -eq $firstId) {
                if ($null -ne $part.level) { $level = $part.level }
                break
            }
        }
    }
    return @{ ids = $ids; level = $level }
}

$currentLine = ""

switch ($runPhase) {
    "batch_scouting" {
        $info = Get-BatchInfo -Batch $currentBatch -Parts $parts
        $currentLine = "scouting batch [$($info.ids)] (level $($info.level))"
    }
    "master_plan_approval" {
        $info = Get-BatchInfo -Batch $currentBatch -Parts $parts
        $currentLine = "awaiting master plan approval for [$($info.ids)] (level $($info.level))"
    }
    "batch_verifying" {
        $info = Get-BatchInfo -Batch $currentBatch -Parts $parts
        $currentLine = "verifying batch [$($info.ids)] (level $($info.level))"
    }
    "finished" {
        $currentLine = "run complete (all Parts done)"
    }
    default {
        if ($null -ne $currentPartId -and $currentPartId -ne "" -and $currentPartId -ne "null") {
            $partStatus   = "(unknown)"
            $partAttempts = 0
            foreach ($part in $parts) {
                if ($part.id -eq $currentPartId) {
                    if ($null -ne $part.status)   { $partStatus   = $part.status }
                    if ($null -ne $part.attempts) { $partAttempts = $part.attempts }
                    break
                }
            }
            $currentLine = "Part $currentPartId ($partStatus, attempt $partAttempts/$maxRetries)"
        } else {
            $currentLine = "(none)"
        }
    }
}

# ---------------------------------------------------------------------------
# build STATUS.md content (LF line endings enforced via explicit "`n")
# ---------------------------------------------------------------------------

$nl = "`n"
$mdash = [char]::ConvertFromUtf32(0x2014)  # —
$middot = [char]::ConvertFromUtf32(0x00B7) # ·

$sb = [System.Text.StringBuilder]::new()

# Header block
[void]$sb.Append("# Northstar $mdash $planFilename$nl")
[void]$sb.Append("$nl")
[void]$sb.Append("Northstar v$toolVersion $middot Last tick: $updatedAt $middot Mode: $nsMode $middot Current: $currentLine$nl")
[void]$sb.Append("$nl")

# Progress table
[void]$sb.Append("## Progress$nl")
[void]$sb.Append("$nl")
[void]$sb.Append("| # | Level | Group | Part | Status |$nl")
[void]$sb.Append("|---|-------|-------|------|--------|$nl")

$rowNum = 0
foreach ($part in $parts) {
    $rowNum++
    $partId     = if ($null -ne $part.id)     { $part.id }     else { "" }
    $partLevel  = if ($null -ne $part.level)  { $part.level }  else { 0 }
    $partGroup  = if ($null -ne $part.group)  { $part.group }  else { "" }
    $partTitle  = if ($null -ne $part.title)  { $part.title }  else { "" }
    $partStatus = if ($null -ne $part.status) { $part.status } else { "pending" }
    $partEmoji  = Get-StatusEmoji -Status $partStatus
    [void]$sb.Append("| $rowNum | $partLevel | $partGroup | $partTitle | $partEmoji $partStatus |$nl")
}
[void]$sb.Append("$nl")

# Current focus
[void]$sb.Append("## Current focus$nl")
[void]$sb.Append("$currentLine$nl")
[void]$sb.Append("$nl")

# Recent decisions
[void]$sb.Append("## Recent decisions$nl")
$globalDecisions = if ($null -ne $payload.global_decisions) { $payload.global_decisions } else { @() }
if ($null -ne $globalDecisions -and @($globalDecisions).Count -gt 0) {
    foreach ($dec in $globalDecisions) {
        if ($dec -is [string]) {
            [void]$sb.Append("- $dec$nl")
        } else {
            $decDate = if ($null -ne $dec.date) { $dec.date } else { "" }
            $decText = if ($null -ne $dec.text) { $dec.text } else { "" }
            if ($decDate -ne "") {
                [void]$sb.Append("- $decDate $mdash $decText$nl")
            } else {
                [void]$sb.Append("- $decText$nl")
            }
        }
    }
} else {
    [void]$sb.Append("None.$nl")
}
[void]$sb.Append("$nl")

# Outstanding questions
[void]$sb.Append("## Outstanding questions$nl")
$blockers = if ($null -ne $payload.blockers) { $payload.blockers } else { @() }
if ($null -ne $blockers -and @($blockers).Count -gt 0) {
    foreach ($blk in $blockers) {
        $blkPartId = if ($null -ne $blk.part_id) { $blk.part_id } else { "" }
        $blkMsg    = if ($null -ne $blk.message)  { $blk.message }  else { "" }
        [void]$sb.Append("- ${blkPartId}: $blkMsg$nl")
    }
} else {
    [void]$sb.Append("None.$nl")
}
[void]$sb.Append("$nl")

# Artifacts
[void]$sb.Append("## Artifacts$nl")
if ($null -ne $parts -and @($parts).Count -gt 0) {
    foreach ($part in $parts) {
        $partId  = if ($null -ne $part.id) { $part.id } else { "" }
        $partNum = $partId -replace "^part-", ""
        $bt = '`'
        [void]$sb.Append("- Part $partNum -> $bt.northstar/parts/$partId/$bt" + $nl)
    }
} else {
    [void]$sb.Append("None.$nl")
}

$statusContent = $sb.ToString()

# ---------------------------------------------------------------------------
# write STATUS.md with explicit LF line endings (no BOM)
# ---------------------------------------------------------------------------

$statusPath = [System.IO.Path]::Combine($stateDir, "STATUS.md")

try {
    # UTF8 without BOM; content already uses LF throughout
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($statusPath, $statusContent, $utf8NoBom)
} catch {
    [Console]::Error.WriteLine("error: failed to write STATUS.md: $_")
    exit 2
}

exit 0
