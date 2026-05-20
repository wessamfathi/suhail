# northstar-clean.ps1 — remove Northstar run artefacts from the current directory.
#
# Usage:
#   northstar-clean.ps1
#   northstar-clean.ps1 --help
#
# Exit codes:
#   0  cleanup complete (idempotent — no error if nothing to remove)
#   1  unknown flag passed
#
# Output:
#   Removes .northstar/ directory and any .northstar-*.txt marker files
#   found in the current working directory. Safe to run multiple times.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# argument parsing — help flag only (no positional args)
# ---------------------------------------------------------------------------

foreach ($arg in $RemainingArgs) {
    if ($arg -eq "-h" -or $arg -eq "--help") {
        Write-Output "northstar-clean.ps1 — remove Northstar run artefacts from the current directory."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output "  northstar-clean.ps1"
        Write-Output "  northstar-clean.ps1 --help"
        Write-Output ""
        Write-Output "Exit codes:"
        Write-Output "  0  cleanup complete (idempotent — no error if nothing to remove)"
        Write-Output "  1  unknown flag passed"
        Write-Output ""
        Write-Output "Output:"
        Write-Output "  Removes .northstar/ directory and any .northstar-*.txt marker files"
        Write-Output "  found in the current working directory. Safe to run multiple times."
        exit 0
    } elseif ($arg.StartsWith("-")) {
        [Console]::Error.WriteLine("error: unknown argument: $arg")
        exit 1
    } else {
        [Console]::Error.WriteLine("error: unexpected argument: $arg")
        exit 1
    }
}

# ---------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------

Remove-Item -Recurse -Force .northstar -ErrorAction SilentlyContinue
Get-ChildItem -Path . -Filter ".northstar-*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

exit 0
