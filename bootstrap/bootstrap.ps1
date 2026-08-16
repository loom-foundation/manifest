# bootstrap.ps1: Loom Foundation workspace bootstrap for Windows (PowerShell).
#
# Run this yourself: it installs system packages and modifies your PATH.
#
# Usage (from the manifest directory or the workspace top directory):
#   bootstrap\bootstrap.ps1
#
# This script is idempotent: every step checks for an existing installation
# before acting. It fails loudly if winget is absent.
#
# Requires: Windows 10 1709 or later, or Windows 11 (winget ships by default).
# Run in a non-elevated PowerShell terminal; winget does not require admin.

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Info  { param($m) Write-Host "[loom bootstrap] $m" -ForegroundColor Cyan }
function Ok    { param($m) Write-Host "[ok] $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "[warn] $m" -ForegroundColor Yellow }
function Die   { param($m) Write-Host "[error] $m" -ForegroundColor Red; exit 1 }

function Command-Exists {
    param($Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    # winget records a newly installed tool's directory in the persisted Machine
    # and User PATH values, but this process still holds the copy it inherited
    # when it started. Rebuild $env:Path from both scopes so the tool resolves in
    # this same session rather than only after the terminal is restarted.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-Tool {
    # Presence is decided on the command alone: if the tool does not resolve,
    # install it. Probing 'winget list' as well would look tidier but would
    # change behaviour that is validated on Windows, so the decision path is
    # deliberately left as simple as it is.
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label
    )
    if (Command-Exists $Command) {
        Ok "$Label already installed"
        return
    }
    Info "Installing $Label..."
    winget install --id $Id -e --accept-source-agreements --accept-package-agreements
    Update-SessionPath
    Ok "$Label installed"
}

function New-RelativeFileSymlink {
    # Windows PowerShell 5.1's `New-Item -ItemType SymbolicLink` does not request
    # the unprivileged-create flag, so it demands elevation even when Developer
    # Mode is on (gated in Step 1). cmd's `mklink` honours Developer Mode, so use
    # that instead.
    #
    # Targets are stored RELATIVE so the workspace survives being moved or
    # renamed. Windows resolves a relative symlink target against the directory
    # holding the link, but `cmd /c mklink` resolves the arguments it is given
    # against the CURRENT directory. Those two agree only while the current
    # directory is the workspace root, so this function switches there before
    # creating the link and switches back afterwards.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$LinkName,
        [Parameter(Mandatory)][string]$RelativeTarget
    )
    Push-Location $Root
    try {
        # Get-Item -Force sees the link entry itself, including a dangling one
        # whose target has gone missing; Test-Path follows the link and would
        # report such a link as absent, leaving mklink to fail on a name clash.
        $existing = Get-Item -LiteralPath $LinkName -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing) { Remove-Item -LiteralPath $LinkName -Force }
        # mklink writes to stderr on failure. Relax the preference so a stderr
        # line does not become a terminating error, then inspect the exit code
        # ourselves rather than trusting the absence of an exception.
        $out = & { $ErrorActionPreference = 'Continue'; cmd /c mklink $LinkName $RelativeTarget 2>&1 }
        if ($LASTEXITCODE -ne 0) {
            Die "Failed to create symlink '$LinkName' pointing at '$RelativeTarget': $out"
        }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# Locate the workspace top directory (the parent of the manifest directory)
# ---------------------------------------------------------------------------

# Resolve paths from this script's own location, so the bootstrap works no
# matter which directory it is invoked from.
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestDir   = Split-Path -Parent $ScriptDir
$WorkspaceDir  = Split-Path -Parent $ManifestDir
$ManifestName  = Split-Path -Leaf $ManifestDir

Info "Workspace root : $WorkspaceDir"
Info "Manifest dir   : $ManifestDir"

# ---------------------------------------------------------------------------
# 1. Verify prerequisites: winget and Developer Mode
# ---------------------------------------------------------------------------

Info 'Step 1: Verifying prerequisites (winget, Developer Mode)...'

if (-not (Command-Exists winget)) {
    Die "winget not found. Install the App Installer from the Microsoft Store: https://aka.ms/getwinget"
}
Ok "winget detected: $(winget --version)"

# Developer Mode must be ON so a non-elevated PowerShell can create the symbolic
# links placed at the workspace root in Step 7. Gate here, before any work is
# done, so the failure arrives in seconds rather than after a full install.
$DevModeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$DevMode = (Get-ItemProperty -Path $DevModeKey -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($DevMode -ne 1) {
    Die @'
Developer Mode is not enabled.

This bootstrap creates symbolic links at the workspace root, which a
non-administrator PowerShell can only do when Developer Mode is enabled.
Enable it, then re-run this script:

  1. Open the Settings app (Windows Key + I).
  2. Go to System > For developers.
  3. Toggle Developer Mode to On.
  4. Accept the disclaimer, and restart your computer if prompted.

Official docs: https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development
'@
}
Ok 'Developer Mode enabled'

# ---------------------------------------------------------------------------
# 2. Install core tools: git, uv, Node.js, gh
# ---------------------------------------------------------------------------

Info 'Step 2: Installing core tools (git, uv, node, gh)...'

Install-Tool -Command 'git'  -Id 'Git.Git'           -Label 'git'
Install-Tool -Command 'uv'   -Id 'astral-sh.uv'      -Label 'uv'
Install-Tool -Command 'node' -Id 'OpenJS.NodeJS.LTS' -Label 'Node.js (LTS)'
Install-Tool -Command 'gh'   -Id 'GitHub.cli'        -Label 'GitHub CLI (gh)'

# ---------------------------------------------------------------------------
# 3. Install west via uv tool
# ---------------------------------------------------------------------------

Info 'Step 3: Installing west via uv tool...'

# 'uv tool list' prints "No tools installed" to stderr when nothing is
# installed. Under $ErrorActionPreference='Stop', Windows PowerShell promotes a
# native command's redirected (2>&1) stderr to a terminating NativeCommandError,
# even on success. Relax the preference in a child scope so a first-time install
# still works.
$uvToolList = & { $ErrorActionPreference = 'Continue'; uv tool list 2>&1 }
if ($uvToolList -match '^west ') {
    Ok 'west already installed via uv tool'
} else {
    uv tool install west
    Ok 'west installed'
}

# ---------------------------------------------------------------------------
# 4. Ensure the uv tool shim directory is on PATH
# ---------------------------------------------------------------------------

Info 'Step 4: Ensuring the uv shim directory is on PATH...'

# uv tool shims land in %USERPROFILE%\.local\bin on Windows.
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'

$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -like "*$LocalBin*") {
    Ok "$LocalBin already on user PATH"
} else {
    Warn "$LocalBin is not on PATH; running 'uv tool update-shell'..."
    uv tool update-shell
    # Also update PATH for the remainder of this session.
    $env:Path = "$LocalBin;$env:Path"
    Ok "$LocalBin added to PATH (restart your terminal to make it permanent)"
}

# Verify west is actually reachable.
if (-not (Command-Exists west)) {
    Die "west command not found even after the PATH update. Ensure '$LocalBin' is on your PATH and restart your terminal."
}
Ok "west reachable: $(west --version)"

# ---------------------------------------------------------------------------
# 5. Silence the Zephyr-base warning (west is used purely as a multi-repo tool)
# ---------------------------------------------------------------------------

Info 'Step 5: Silencing the Zephyr-base warning...'

# west prints the zephyr.base warning to stderr. Relax the preference so the
# redirect does not become a terminating error under $ErrorActionPreference='Stop'.
& { $ErrorActionPreference = 'Continue'; west config --global zephyr.base not-using-zephyr 2>&1 | Out-Null }
Ok 'zephyr.base set to not-using-zephyr (global)'

# ---------------------------------------------------------------------------
# 6. Initialise the west workspace and clone the sibling repositories
# ---------------------------------------------------------------------------

Info 'Step 6: Initialising the west workspace...'

$WestDir = Join-Path $WorkspaceDir '.west'

if (Test-Path $WestDir) {
    Ok '.west directory already exists; skipping west init'
} else {
    Info "Running: west init -l $ManifestName (from $WorkspaceDir)"
    Push-Location $WorkspaceDir
    try {
        west init -l $ManifestName
        Ok 'west workspace initialised'
    } finally {
        Pop-Location
    }
}

Info 'Running: west update (clone or fast-forward every project)...'
Push-Location $WorkspaceDir
try {
    # The -k and -r flags match what `manage update` passes. On a first run there
    # is no checked-out branch to preserve, so they change nothing; on a re-run of
    # this bootstrap, which is meant to be safe, they keep branches checked out
    # instead of detaching HEAD in every project.
    west update -k -r
    Ok 'west update complete'
    # Apply the zephyr.base setting to this workspace as well, in the same
    # stderr-tolerant child scope as the global one above.
    & { $ErrorActionPreference = 'Continue'; west config zephyr.base not-using-zephyr 2>&1 | Out-Null }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 7. Link the workspace-root files (idempotent)
# ---------------------------------------------------------------------------

Info 'Step 7: Linking workspace-root files...'
# Symbolic links, so a `west update` of the manifest repository propagates edits
# to the workspace root. Developer Mode (verified in Step 1) lets these be
# created without elevation. AGENTS.md and CLAUDE.md carry the agent brief that
# points AI agents at the governing Loom Foundation intent corpora.
$Links = @(
    @{ Name = 'README.md';  Target = "$ManifestName\workspace-root\README.md" },
    @{ Name = 'AGENTS.md';  Target = "$ManifestName\workspace-root\AGENTS.md" },
    @{ Name = 'CLAUDE.md';  Target = "$ManifestName\workspace-root\CLAUDE.md" },
    @{ Name = '.gitignore'; Target = "$ManifestName\workspace-root\.gitignore" },
    @{ Name = 'west.yml';   Target = "$ManifestName\west.yml" },
    @{ Name = 'manage.cmd'; Target = "$ManifestName\manage.cmd" }
)
foreach ($link in $Links) {
    $source = Join-Path $WorkspaceDir $link.Target
    if (Test-Path $source) {
        New-RelativeFileSymlink -Root $WorkspaceDir -LinkName $link.Name -RelativeTarget $link.Target
        Ok "$($link.Name) symlinked to $($link.Target)"
    } else {
        Warn "$($link.Target) not found; skipping $($link.Name)"
    }
}

# ---------------------------------------------------------------------------
# 8. Ensure the workspace directories exist (idempotent)
# ---------------------------------------------------------------------------
# west materialises a directory only when a project's path lands inside it, and
# tmp\ belongs to no project at all. Create the fixed set here so a fresh
# checkout has the same shape on every platform.
Info 'Step 8: Ensuring workspace directories...'
foreach ($dir in @('apps', 'corpora', 'packages', 'sites', 'skills', 'tmp')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkspaceDir $dir) | Out-Null
    Ok "$dir\ present"
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Info 'Bootstrap complete.'
Info 'Next steps:'
Info '  * Restart your terminal so the PATH changes take effect.'
Info "  * Run '.\manage.cmd help' from the workspace root for common tasks."
Info "  * See README.md at the workspace root, or $ManifestName\README.md."
