# Northstar installer (PowerShell).
#
# Usage:
#   .\scripts\install.ps1                        # user-level install to ~\.claude\
#   .\scripts\install.ps1 -Project C:\path       # install into C:\path\.claude\ instead
#   .\scripts\install.ps1 -Project ... -Gitignore  # also append .northstar/ to <Project>\.gitignore
#   .\scripts\install.ps1 -Force                 # overwrite existing files (default refuses and prints diff)

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Project = "",
    [switch]$Force,
    [switch]$Gitignore,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
@"
Northstar installer (PowerShell).

Usage:
  .\scripts\install.ps1                            user-level install to ~\.claude\
  .\scripts\install.ps1 -Project C:\path           install into C:\path\.claude\ instead
  .\scripts\install.ps1 -Project C:\path -Gitignore  also append .northstar/ to <Project>\.gitignore
  .\scripts\install.ps1 -Force                     overwrite existing files (default refuses and prints diff)
"@ | Write-Output
    exit 0
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$srcAgents = Join-Path $repoRoot "agents"
$srcCommands = Join-Path $repoRoot "commands"

if ($Project -ne "") {
    if (-not (Test-Path $Project)) {
        Write-Error "Project path does not exist: $Project"
        exit 2
    }
    $destBase = Join-Path $Project ".claude"
    $scope = "project ($Project)"
} else {
    $destBase = Join-Path $HOME ".claude"
    $scope = "user (~\.claude)"
    if ($Gitignore) {
        Write-Warning "-Gitignore is only meaningful with -Project; ignoring."
        $Gitignore = $false
    }
}

$destAgents = Join-Path $destBase "agents"
$destCommands = Join-Path $destBase "commands"
$destCommandsScripts = Join-Path $destCommands "scripts"

Write-Output "Northstar installer"
Write-Output "  scope: $scope"
Write-Output "  destination: $destBase"
Write-Output ""

New-Item -ItemType Directory -Force -Path $destAgents | Out-Null
New-Item -ItemType Directory -Force -Path $destCommands | Out-Null
New-Item -ItemType Directory -Force -Path $destCommandsScripts | Out-Null

$status = 0

# Cleanup: in v0.1.0 the orchestrator was shipped as agents/northstar.md.
# As of v0.1.1 the orchestrator lives in the slash command body (Claude Code
# subagents cannot spawn nested subagents). Remove the stale file if present.
$staleOrchestrator = Join-Path $destAgents "northstar.md"
if (Test-Path $staleOrchestrator) {
    Remove-Item -Path $staleOrchestrator -Force
    Write-Output "removed stale (pre-0.1.1) orchestrator subagent: $staleOrchestrator"
}

function Install-File {
    param([string]$Src, [string]$Dest)
    if ((Test-Path $Dest) -and (-not $Force)) {
        $srcHash = (Get-FileHash $Src -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $Dest -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            Write-Output "refusing to overwrite (use -Force): $Dest"
            $diff = Compare-Object (Get-Content $Dest) (Get-Content $Src)
            if ($diff) {
                $diff | ForEach-Object { Write-Output "    $($_.SideIndicator) $($_.InputObject)" }
            }
            return $false
        } else {
            Write-Output "unchanged: $Dest"
            return $true
        }
    }
    Copy-Item -Path $Src -Destination $Dest -Force
    Write-Output "installed: $Dest"
    return $true
}

Get-ChildItem -Path $srcAgents -Filter *.md | ForEach-Object {
    $dest = Join-Path $destAgents $_.Name
    if (-not (Install-File -Src $_.FullName -Dest $dest)) {
        $status = 1
    }
}

Get-ChildItem -Path $srcCommands -Filter *.md | ForEach-Object {
    $dest = Join-Path $destCommands $_.Name
    if (-not (Install-File -Src $_.FullName -Dest $dest)) {
        $status = 1
    }
}

$srcScripts = Join-Path $repoRoot "scripts"
@("northstar-tick.ps1", "northstar-tick.sh", "northstar-read.ps1", "northstar-read.sh", "northstar-write.ps1", "northstar-write.sh", "northstar-clean.ps1", "northstar-clean.sh") | ForEach-Object {
    $src = Join-Path $srcScripts $_
    if (Test-Path $src) {
        $dest = Join-Path $destCommandsScripts $_
        if (-not (Install-File -Src $src -Dest $dest)) {
            $status = 1
        }
    }
}

if ($Gitignore) {
    $gitignorePath = Join-Path $Project ".gitignore"
    $needle = ".northstar/"
    $existing = @()
    if (Test-Path $gitignorePath) {
        $existing = Get-Content $gitignorePath
    }
    if ($existing -contains $needle) {
        Write-Output "gitignore: .northstar/ already present in $gitignorePath"
    } else {
        # Ensure the file ends with a newline so .northstar/ isn't concatenated onto the last line.
        $raw = if (Test-Path $gitignorePath) { Get-Content -Path $gitignorePath -Raw } else { "" }
        $prefix = if ($raw.Length -gt 0 -and $raw[-1] -ne "`n") { "`n" } else { "" }
        Add-Content -Path $gitignorePath -Value "$prefix$needle"
        Write-Output "gitignore: appended .northstar/ to $gitignorePath"
    }
}

Write-Output ""
if ($status -eq 0) {
    Write-Output "Northstar installed. Try: /ns fixtures/test_plan.md"
} else {
    Write-Output "Some files were skipped (already exist with different contents)."
    Write-Output "Re-run with -Force to overwrite."
}
exit $status
