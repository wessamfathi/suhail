# suhail-read.ps1 — read-only artifact reader for Suhail.
#
# Usage:
#   suhail-read.ps1 <path/to/parts/part-N>
#   suhail-read.ps1 --help
#
# Exit codes:
#   0  summary JSON emitted to stdout (even if some artifact files are absent)
#   1  part directory missing or unreadable
#
# Output: a single-line JSON object, e.g.:
#   {"part_dir":"...","review":{"verdict":"clean"},"audit":{"verdict":"blockers"},"execution":{"files_changed_count":3},"blocker":{"present":false,"from":null,"severity":null,"options":null}}

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# argument parsing — help flag and positional part directory path
# ---------------------------------------------------------------------------

$PartDir = ""

foreach ($arg in $RemainingArgs) {
    if ($arg -eq "-h" -or $arg -eq "--help") {
        Write-Output "suhail-read.ps1 — read-only artifact reader for Suhail."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output "  suhail-read.ps1 <path/to/parts/part-N>"
        Write-Output "  suhail-read.ps1 --help"
        Write-Output ""
        Write-Output "Exit codes:"
        Write-Output "  0  summary JSON emitted to stdout (even if some artifact files are absent)"
        Write-Output "  1  part directory missing or unreadable"
        Write-Output ""
        Write-Output "Output: a single-line JSON object, e.g.:"
        Write-Output '  {"part_dir":"...","review":{"verdict":"clean"},"audit":{"verdict":"blockers"},"execution":{"files_changed_count":3},"blocker":{"present":false,"from":null,"severity":null,"options":null}}'
        exit 0
    } elseif ($arg.StartsWith("-")) {
        [Console]::Error.WriteLine("error: unknown argument: $arg")
        exit 1
    } elseif ($PartDir -ne "") {
        [Console]::Error.WriteLine("error: unexpected extra argument: $arg")
        exit 1
    } else {
        $PartDir = $arg
    }
}

if ($PartDir -eq "") {
    [Console]::Error.WriteLine("error: usage: suhail-read.ps1 <path/to/parts/part-N>")
    exit 1
}

if (-not (Test-Path $PartDir -PathType Container)) {
    [Console]::Error.WriteLine("error: part directory not found: $PartDir")
    exit 1
}

# ---------------------------------------------------------------------------
# extraction helpers
# ---------------------------------------------------------------------------

function Get-Verdict {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    # First NON-EMPTY line after the heading (a blank line between the
    # heading and the verdict is tolerated); stop at the next heading.
    $lines = @(Get-Content $FilePath)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## Verdict') {
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $val = $lines[$j].Trim()
                if ($val.StartsWith("#")) { return $null }
                if ($val -ne "") { return $val }
            }
            return $null
        }
    }
    return $null
}

function Get-FilesChangedCount {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    $lines = Get-Content $FilePath
    $inSection = $false
    $count = 0
    foreach ($line in $lines) {
        if ($line -match '^## Files changed') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^## ') {
            $inSection = $false
        }
        if ($inSection -and $line -match '^- `') {
            $count++
        }
    }
    return $count
}

function Get-BlockerFields {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        return @{
            present  = $false
            from     = $null
            severity = $null
            options  = $null
        }
    }

    $lines = Get-Content $FilePath
    # Extract lines between the first and second --- delimiters
    $frontmatterLines = @()
    $delimCount = 0
    foreach ($line in $lines) {
        if ($line.Trim() -eq "---") {
            $delimCount++
            if ($delimCount -eq 2) { break }
            continue
        }
        if ($delimCount -eq 1) {
            $frontmatterLines += $line
        }
    }

    $fromVal     = $null
    $severityVal = $null
    $optionsVal  = $null

    foreach ($line in $frontmatterLines) {
        if ($line -match '^from:\s*(.+)$') {
            $fromVal = $Matches[1].Trim()
        } elseif ($line -match '^severity:\s*(.+)$') {
            $severityVal = $Matches[1].Trim()
        } elseif ($line -match '^options:\s*(.+)$') {
            $optionsRaw = $Matches[1].Trim()
            # options is a YAML inline list like ["a","b","c"] — parse as JSON
            try {
                $optionsVal = $optionsRaw | ConvertFrom-Json
            } catch {
                $optionsVal = $null
            }
        }
    }

    return @{
        present  = $true
        from     = $fromVal
        severity = $severityVal
        options  = $optionsVal
    }
}

# ---------------------------------------------------------------------------
# main logic
# ---------------------------------------------------------------------------

$reviewFile    = Join-Path $PartDir "review.md"
$auditFile     = Join-Path $PartDir "audit.md"
$blockerFile   = Join-Path $PartDir "blocker.md"

# Execution artifacts are attempt-numbered on retries (execution-attempt-K.md
# for K > 1). Read the LATEST attempt so retry runs are summarized from the
# artifact that was actually produced, not the stale attempt-1 file.
$executionFile = Join-Path $PartDir "execution.md"
$attemptFiles = Get-ChildItem -Path $PartDir -Filter "execution-attempt-*.md" -ErrorAction SilentlyContinue
if ($null -ne $attemptFiles -and @($attemptFiles).Count -gt 0) {
    $latest = @($attemptFiles) |
        ForEach-Object {
            if ($_.Name -match '^execution-attempt-(\d+)\.md$') {
                [PSCustomObject]@{ N = [int]$Matches[1]; File = $_.FullName }
            }
        } |
        Sort-Object -Property N |
        Select-Object -Last 1
    if ($null -ne $latest) { $executionFile = $latest.File }
}

$reviewVerdict      = Get-Verdict -FilePath $reviewFile
$auditVerdict       = Get-Verdict -FilePath $auditFile
$filesChangedCount  = Get-FilesChangedCount -FilePath $executionFile
$blockerFields      = Get-BlockerFields -FilePath $blockerFile

# Build the output object
$output = [PSCustomObject]@{
    part_dir  = $PartDir
    review    = [PSCustomObject]@{ verdict = $reviewVerdict }
    audit     = [PSCustomObject]@{ verdict = $auditVerdict }
    execution = [PSCustomObject]@{ files_changed_count = $filesChangedCount }
    blocker   = [PSCustomObject]@{
        present  = $blockerFields.present
        from     = $blockerFields.from
        severity = $blockerFields.severity
        options  = $blockerFields.options
    }
}

Write-Output ($output | ConvertTo-Json -Compress -Depth 5)

exit 0
