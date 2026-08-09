#!/bin/sh
# install.sh: one-line Loom Foundation workspace installer for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/loom-foundation/manifest/main/install.sh | sh
#
# Takes a bare machine to a working Loom workspace. Every Loom repository is
# public, so no GitHub sign-in and no organisation membership are needed; plain
# https clones are enough.
#
# This script assumes nothing but a POSIX shell and curl. It installs git via
# the platform package manager when git is absent, creates the workspace,
# clones the manifest repository INTO it, then hands off to the bootstrap that
# installs the remaining tools (uv, west, Node.js, gh).
#
# Non-interactive: set LOOM_WORKSPACE=/path before running to skip the prompt.
set -e

info() { printf '\033[1;34m[loom install]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- Detect OS and package manager ------------------------------------------
OS="$(uname -s)"
case "$OS" in
  Darwin)
    have brew || die "Homebrew is required. Install it from https://brew.sh then re-run."
    PM=brew ;;
  Linux)
    if   have apt-get; then PM=apt
    elif have dnf;     then PM=dnf
    elif have pacman;  then PM=pacman
    else die "No supported package manager found (apt, dnf, or pacman). See https://github.com/loom-foundation/manifest#readme"; fi ;;
  *) die "Unsupported OS: $OS. On Windows, use install.ps1. See https://github.com/loom-foundation/manifest#readme" ;;
esac

# --- git --------------------------------------------------------------------
if have git; then
  info "git already installed"
else
  info "Installing git..."
  case "$PM" in
    brew)   brew install git ;;
    apt)    sudo apt-get update && sudo apt-get install -y git ;;
    dnf)    sudo dnf install -y git ;;
    pacman) sudo pacman -S --noconfirm git ;;
  esac
fi

# --- Choose the workspace location ------------------------------------------
default="$(pwd)/loom-foundation"
if [ -n "$LOOM_WORKSPACE" ]; then
  workspace="$LOOM_WORKSPACE"
elif [ -r /dev/tty ]; then
  info "Create the Loom Foundation workspace at: $default"
  printf 'Press Enter to accept, or type a different path: '
  # This script normally arrives on stdin through the pipe, so the answer has to
  # be read from the terminal directly.
  read answer < /dev/tty || answer=""
  if [ -n "$answer" ]; then workspace="$answer"; else workspace="$default"; fi
else
  # Piped with no terminal available, so take the default.
  workspace="$default"
fi

# Expand a leading ~ if the reader typed one; read does not do it for us.
case "$workspace" in
  "~"/*) workspace="$HOME/${workspace#~/}" ;;
  "~")   workspace="$HOME" ;;
esac

info "Workspace: $workspace"
mkdir -p "$workspace"

MANIFEST_DIR="$workspace/manifest"
if [ -d "$MANIFEST_DIR/.git" ]; then
  info "manifest already present; updating."
  git -C "$MANIFEST_DIR" pull --ff-only || true
else
  info "Cloning manifest..."
  git clone https://github.com/loom-foundation/manifest.git "$MANIFEST_DIR"
fi

info "Handing off to bootstrap..."
exec sh "$MANIFEST_DIR/bootstrap/bootstrap.sh"
