# suhail-git.ps1 — deterministic git plumbing helper for Suhail's per-Part patch isolation.
#
# Every subcommand works through a temporary index file (GIT_INDEX_FILE).
# The user's working tree is never touched, and user-authored index state is
# never clobbered: after a commit, pristine real-index entries for the
# committed paths are synced to the new HEAD so git status stays clean, while
# any entry the user staged themselves is left exactly as it was. Commits are
# created via plumbing (commit-tree + update-ref), so commit hooks
# (pre-commit, commit-msg, post-commit) do NOT run — a documented
# orchestrator-level trade-off.
#
# Usage:
#   suhail-git.ps1 snapshot
#       Print a tree id capturing the current working tree state: tracked
#       changes AND untracked files, respecting .gitignore.
#   suhail-git.ps1 patch <tree_a> <tree_b> <out_file>
#       Write the binary diff between the two trees to <out_file>, excluding
#       .suhail (Suhail's own artifacts never belong in Part patches), and
#       print the changed paths one per line to stdout. An empty diff yields
#       an empty <out_file> and no stdout.
#   suhail-git.ps1 commit <patch_file> <msg_file>
#       Commit EXACTLY the patch on top of HEAD via a temporary index and
#       print the new commit id. Requires an existing HEAD commit.
#   suhail-git.ps1 --help
#
# Exit codes:
#   0  success
#   1  environment error: not inside a git work tree, invalid tree id,
#      unborn HEAD, missing input file, or unwritable out file
#   2  usage error: unknown subcommand or wrong argument count
#   3  patch does not apply cleanly to HEAD
#   4  nothing to commit: empty patch file, or patch produces the HEAD tree

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

function Fail1 {
    param([string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    exit 1
}

function Write-Usage {
    [Console]::Error.WriteLine("usage: suhail-git.ps1 snapshot")
    [Console]::Error.WriteLine("       suhail-git.ps1 patch <tree_a> <tree_b> <out_file>")
    [Console]::Error.WriteLine("       suhail-git.ps1 commit <patch_file> <msg_file>")
    exit 2
}

function Show-Help {
    Write-Output "suhail-git.ps1 — deterministic git plumbing helper for Suhail's per-Part patch isolation."
    Write-Output ""
    Write-Output "Every subcommand works through a temporary index file (GIT_INDEX_FILE)."
    Write-Output "The user's working tree is never touched, and user-authored index state is"
    Write-Output "never clobbered: after a commit, pristine real-index entries for the"
    Write-Output "committed paths are synced to the new HEAD so git status stays clean."
    Write-Output "Commits are created via plumbing, so commit hooks do NOT run."
    Write-Output ""
    Write-Output "Usage:"
    Write-Output "  suhail-git.ps1 snapshot"
    Write-Output "      Print a tree id capturing the current working tree state: tracked"
    Write-Output "      changes AND untracked files, respecting .gitignore."
    Write-Output "  suhail-git.ps1 patch <tree_a> <tree_b> <out_file>"
    Write-Output "      Write the binary diff between the two trees to <out_file>, excluding"
    Write-Output "      .suhail, and print the changed paths one per line to stdout."
    Write-Output "  suhail-git.ps1 commit <patch_file> <msg_file>"
    Write-Output "      Commit EXACTLY the patch on top of HEAD via a temporary index and"
    Write-Output "      print the new commit id. Requires an existing HEAD commit."
    Write-Output ""
    Write-Output "Exit codes:"
    Write-Output "  0  success"
    Write-Output "  1  environment error: not inside a git work tree, invalid tree id,"
    Write-Output "     unborn HEAD, missing input file, or unwritable out file"
    Write-Output "  2  usage error: unknown subcommand or wrong argument count"
    Write-Output "  3  patch does not apply cleanly to HEAD"
    Write-Output "  4  nothing to commit: empty patch file, or patch produces the HEAD tree"
}

$script:TmpIndex = $null

function New-TempIndex {
    $script:TmpIndex = [System.IO.Path]::GetTempFileName()
    $env:GIT_INDEX_FILE = $script:TmpIndex
}

function Remove-TempIndex {
    Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
    if ($script:TmpIndex) {
        Remove-Item -LiteralPath $script:TmpIndex -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$($script:TmpIndex).lock" -Force -ErrorAction SilentlyContinue
    }
    $script:TmpIndex = $null
}

function Assert-WorkTree {
    # EAP flips to Continue around the redirected call: under "Stop", Windows
    # PowerShell 5.1 can turn a redirected native stderr line into a
    # terminating NativeCommandError.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = git rev-parse --is-inside-work-tree 2>$null
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($LASTEXITCODE -ne 0 -or "$out".Trim() -ne "true") {
        Fail1 "not inside a git work tree"
    }
}

function Test-GitRevision {
    # -q --verify prints nothing on failure, so no stderr redirect is needed.
    param([string]$Revision)
    $null = git rev-parse -q --verify $Revision
    return ($LASTEXITCODE -eq 0)
}

function Get-BlobId {
    # Resolve a revision (e.g. ":0:path" or "<tree>:path") to a blob id, or ""
    # when it does not resolve. Stderr is suppressed with the EAP flipped to
    # Continue — see Assert-WorkTree for why that matters on PS 5.1.
    param([string]$Revision)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = git rev-parse -q --verify $Revision 2>$null
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($LASTEXITCODE -ne 0) { return "" }
    return "$out".Trim()
}

# ---------------------------------------------------------------------------
# snapshot — tree id of the current working tree (tracked + untracked)
# ---------------------------------------------------------------------------

function Invoke-Snapshot {
    Assert-WorkTree
    New-TempIndex
    try {
        if (Test-GitRevision "HEAD^{commit}") {
            git read-tree HEAD
            if ($LASTEXITCODE -ne 0) { Fail1 "read-tree HEAD failed" }
        } else {
            git read-tree --empty
            if ($LASTEXITCODE -ne 0) { Fail1 "read-tree --empty failed" }
        }
        git add -A
        if ($LASTEXITCODE -ne 0) { Fail1 "add -A failed" }
        $tree = "$(git write-tree)".Trim()
        if ($LASTEXITCODE -ne 0 -or $tree -eq "") { Fail1 "write-tree failed" }
        Write-Output $tree
    } finally {
        Remove-TempIndex
    }
}

# ---------------------------------------------------------------------------
# patch — exact diff between two snapshot trees, .suhail excluded
# ---------------------------------------------------------------------------

function Invoke-Patch {
    param(
        [string]$TreeA,
        [string]$TreeB,
        [string]$OutFile
    )
    Assert-WorkTree
    if (-not (Test-GitRevision "$TreeA^{tree}")) { Fail1 "invalid tree id: $TreeA" }
    if (-not (Test-GitRevision "$TreeB^{tree}")) { Fail1 "invalid tree id: $TreeB" }

    # Absolutize so --output lands exactly where the caller said, regardless
    # of how git resolves relative paths internally. Pre-create/truncate it so
    # an empty diff still leaves an empty file and unwritable paths fail as
    # exit 1. --output keeps binary patch bytes out of the PowerShell
    # pipeline, which would re-encode (and corrupt) them.
    if (-not [System.IO.Path]::IsPathRooted($OutFile)) {
        $OutFile = Join-Path (Get-Location).ProviderPath $OutFile
    }
    try {
        $null = New-Item -ItemType File -Force -Path $OutFile
    } catch {
        Fail1 "cannot write out file: $OutFile"
    }

    git diff --binary --full-index "--output=$OutFile" $TreeA $TreeB -- . ':(exclude).suhail'
    if ($LASTEXITCODE -ne 0) { Fail1 "diff failed" }
    git diff --name-only $TreeA $TreeB -- . ':(exclude).suhail'
    if ($LASTEXITCODE -ne 0) { Fail1 "diff --name-only failed" }
}

# ---------------------------------------------------------------------------
# commit — land exactly one patch on HEAD via a temporary index
# ---------------------------------------------------------------------------

function Invoke-Commit {
    param(
        [string]$PatchFile,
        [string]$MsgFile
    )
    Assert-WorkTree
    if (-not (Test-Path $PatchFile -PathType Leaf)) { Fail1 "patch file not found: $PatchFile" }
    if (-not (Test-Path $MsgFile -PathType Leaf)) { Fail1 "message file not found: $MsgFile" }
    if (-not (Test-GitRevision "HEAD^{commit}")) {
        Fail1 "HEAD does not exist (unborn branch) — create an initial commit first"
    }

    if ((Get-Item -LiteralPath $PatchFile).Length -eq 0) {
        [Console]::Error.WriteLine("error: nothing to commit: patch file is empty")
        exit 4
    }

    New-TempIndex
    try {
        git read-tree HEAD
        if ($LASTEXITCODE -ne 0) { Fail1 "read-tree HEAD failed" }

        # --check validates against HEAD content (the temp index), not the
        # user's working tree; git's own diagnostics pass through on stderr.
        git apply --cached --check $PatchFile
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("error: patch does not apply to HEAD")
            exit 3
        }
        git apply --cached $PatchFile
        if ($LASTEXITCODE -ne 0) { Fail1 "apply --cached failed after a clean check" }

        $tree = "$(git write-tree)".Trim()
        if ($LASTEXITCODE -ne 0 -or $tree -eq "") { Fail1 "write-tree failed" }
        $headTree = "$(git rev-parse 'HEAD^{tree}')".Trim()
        if ($LASTEXITCODE -ne 0) { Fail1 "rev-parse HEAD^{tree} failed" }
        if ($tree -eq $headTree) {
            [Console]::Error.WriteLine("error: nothing to commit: patch produces the HEAD tree")
            exit 4
        }

        # commit-tree is plumbing and ignores commit.gpgsign — honor it
        # explicitly so Suhail Part commits sign (and verify on forges) like
        # porcelain commits. EAP flip: --get exits non-zero when unset.
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $gpgSign = "$(git config --get --type=bool commit.gpgsign 2>$null)".Trim()
        } finally {
            $ErrorActionPreference = $prev
        }
        $signArgs = @()
        if ($gpgSign -eq "true") { $signArgs = @("-S") }
        $newCommit = "$(git commit-tree @signArgs $tree -p HEAD -F $MsgFile)".Trim()
        if ($LASTEXITCODE -ne 0 -or $newCommit -eq "") { Fail1 "commit-tree failed" }
        git update-ref HEAD $newCommit
        if ($LASTEXITCODE -ne 0) { Fail1 "update-ref failed" }

        # Reconcile the REAL index. Without this, every committed path whose
        # real index entry still holds the pre-commit blob would show in git
        # status as a staged reversion of the Part's change — and a subsequent
        # bare `git commit` by the user would actually commit that reversion.
        # Only pristine entries are synced (index blob equal to the old-HEAD
        # blob, or absent on both sides); anything the user staged themselves
        # is left alone. Remove-TempIndex clears GIT_INDEX_FILE first so these
        # operations hit the real index.
        Remove-TempIndex
        $committedPaths = @(git -c core.quotepath=false diff --name-only $headTree $tree)
        if ($LASTEXITCODE -ne 0) { Fail1 "diff for index reconcile failed" }
        foreach ($p in $committedPaths) {
            $path = "$p" -replace "`r$", ""
            if ($path -eq "") { continue }
            $idxBlob = Get-BlobId ":0:$path"
            $h0Blob = Get-BlobId "${headTree}:$path"
            if ($idxBlob -eq $h0Blob) {
                # Mixed reset syncs the index entry to the new HEAD without
                # touching the working tree; it also creates entries for new
                # files and drops them for deletions.
                git reset -q -- ":(top,literal)$path"
                if ($LASTEXITCODE -ne 0) { Fail1 "index reconcile failed for: $path" }
            }
        }

        Write-Output $newCommit
    } finally {
        Remove-TempIndex
    }
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

if ($null -eq $RemainingArgs -or $RemainingArgs.Count -eq 0) { Write-Usage }

$Sub = $RemainingArgs[0]
$Rest = @($RemainingArgs | Select-Object -Skip 1)

if ($Sub -eq "-h" -or $Sub -eq "--help") {
    Show-Help
    exit 0
}

switch -CaseSensitive ($Sub) {
    "snapshot" {
        if ($Rest.Count -ne 0) { Write-Usage }
        Invoke-Snapshot
    }
    "patch" {
        if ($Rest.Count -ne 3) { Write-Usage }
        Invoke-Patch -TreeA $Rest[0] -TreeB $Rest[1] -OutFile $Rest[2]
    }
    "commit" {
        if ($Rest.Count -ne 2) { Write-Usage }
        Invoke-Commit -PatchFile $Rest[0] -MsgFile $Rest[1]
    }
    default { Write-Usage }
}

exit 0
