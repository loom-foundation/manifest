# install.ps1: Loom Foundation one-line workspace installer for Windows PowerShell.
#
#   irm https://raw.githubusercontent.com/loom-foundation/manifest/main/install.ps1 | iex
#
# Takes a fresh Windows machine from nothing to a working Loom Foundation
# workspace. It assumes nothing but PowerShell and winget: git is installed here
# if it is absent. Every Loom repository is public, so no GitHub sign-in and no
# organisation membership are needed; the clone happens over plain https.
#
# Non-interactive (skip the prompt):  $env:LOOM_WORKSPACE = 'C:\path\loom-foundation'
#
# Prerequisite this script cannot satisfy itself: Developer Mode must be enabled
# (Settings, System, For developers) so the bootstrap can create symbolic links
# without administrator rights. The bootstrap checks for it and explains how.

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "[loom install] $m" -ForegroundColor Blue }
function Die($m)  { Write-Host "[error] $m" -ForegroundColor Red; exit 1 }
function Have($n) { $null -ne (Get-Command $n -ErrorAction SilentlyContinue) }

function Update-SessionPath {
    # winget writes the new tool's directory into the persisted Machine and User
    # PATH values, but the current process keeps the copy it inherited at launch.
    # Rebuild $env:Path from both scopes so a freshly installed tool resolves
    # without the user having to open a new terminal.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

if (-not (Have winget)) {
    Die "winget not found. Install 'App Installer' from the Microsoft Store: https://aka.ms/getwinget"
}

if (Have git) {
    Info 'git already installed.'
} else {
    Info 'Installing git...'
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    Update-SessionPath
    if (-not (Have git)) {
        Die 'git is still not on PATH after installation. Open a new terminal and re-run this installer.'
    }
    Info 'git installed.'
}

# ---------------------------------------------------------------------------
# Choose the workspace location
# ---------------------------------------------------------------------------

$default = Join-Path (Get-Location).Path 'loom-foundation'
if ($env:LOOM_WORKSPACE) {
    $workspace = $env:LOOM_WORKSPACE
    Info "Workspace location taken from LOOM_WORKSPACE."
} else {
    # A scripted or redirected run has no console to prompt at. Ask the host
    # whether its user interface can prompt at all, and treat a prompt that
    # throws as the same case: without this, Read-Host under
    # $ErrorActionPreference='Stop' would abort the installer instead of
    # quietly taking the default, which is what the POSIX installer does when
    # it finds no tty.
    $workspace = $null
    if ($null -ne $Host.UI -and $null -ne $Host.UI.RawUI) {
        try {
            $ans = Read-Host "[loom install] Create the Loom Foundation workspace at '$default'? Enter to accept, or type a different path"
            if ([string]::IsNullOrWhiteSpace($ans)) { $workspace = $default } else { $workspace = $ans }
        } catch {
            $workspace = $null
        }
    }
    if ($null -eq $workspace) {
        $workspace = $default
        Info "Non-interactive session; using the default workspace location."
    }
}

Info "Workspace: $workspace"
New-Item -ItemType Directory -Force $workspace | Out-Null

# ---------------------------------------------------------------------------
# Clone (or fast-forward) the manifest repository inside the workspace
# ---------------------------------------------------------------------------

# The manifest repository must sit INSIDE the workspace directory: the bootstrap
# resolves the workspace top directory as the parent of 'manifest', and
# 'west init -l manifest' is run from that parent.
$manifest = Join-Path $workspace 'manifest'
if (Test-Path (Join-Path $manifest '.git')) {
    Info 'manifest already present; updating.'
    # A local manifest that has diverged, or has uncommitted work, must not abort
    # the installer. git writes to stderr when it refuses a fast-forward, and under
    # $ErrorActionPreference='Stop' that becomes a terminating error before the exit
    # code can be inspected, so relax the preference and check the code instead.
    # The POSIX installer tolerates the same case.
    & { $ErrorActionPreference = 'Continue'; git -C $manifest pull --ff-only 2>&1 | Write-Host }
    if ($LASTEXITCODE -ne 0) {
        Info 'Could not fast-forward the existing manifest; continuing with what is already on disk.'
    }
} else {
    Info 'Cloning manifest...'
    git clone https://github.com/loom-foundation/manifest.git $manifest
}

# ---------------------------------------------------------------------------
# Hand off to the bootstrap
# ---------------------------------------------------------------------------

Info 'Handing off to bootstrap...'
# bootstrap.ps1 runs as a file on disk, so it is subject to the execution
# policy. This installer is not: it arrives over the pipe through `iex`. Lift the
# policy for THIS process only. No administrator rights are required and the
# change does not persist beyond the current session.
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}
& (Join-Path $manifest 'bootstrap\bootstrap.ps1')
