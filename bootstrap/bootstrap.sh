#!/bin/sh
# bootstrap.sh: Loom Foundation workspace bootstrap for macOS and Linux.
#
# Run this yourself: it installs system packages and modifies your PATH.
#
# Usage (from the manifest directory or the workspace topdir):
#   sh bootstrap/bootstrap.sh
#
# The script is idempotent: every step checks for an existing installation
# before acting. It fails loudly when a required package manager is absent.

set -e

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;34m[loom bootstrap]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Locate the workspace topdir (the parent of the manifest directory)
# ---------------------------------------------------------------------------

# The script may be invoked from any working directory, so everything is
# resolved from the script's own location rather than from the caller's cwd.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$MANIFEST_DIR/.." && pwd)"

info "Workspace root : $WORKSPACE_DIR"
info "Manifest dir   : $MANIFEST_DIR"

# ---------------------------------------------------------------------------
# 1. Detect OS and package manager
# ---------------------------------------------------------------------------

info "Step 1: Detecting OS and package manager..."

OS="$(uname -s)"
case "$OS" in
  Darwin)
    PM="brew"
    if ! command_exists brew; then
      die "Homebrew not found. Install it first: https://brew.sh
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
    ok "macOS with Homebrew detected"
    ;;
  Linux)
    if command_exists apt-get; then
      PM="apt"
    elif command_exists dnf; then
      PM="dnf"
    elif command_exists pacman; then
      PM="pacman"
    else
      die "No recognised package manager found (apt, dnf, or pacman). Install one first."
    fi
    ok "Linux with $PM detected"
    ;;
  *)
    die "Unsupported OS: $OS. Use bootstrap.ps1 on Windows."
    ;;
esac

# ---------------------------------------------------------------------------
# Package-manager install helper (idempotent per tool)
# ---------------------------------------------------------------------------

pm_install() {
  TOOL="$1"
  PKG="${2:-$1}"   # optional alternate package name
  if command_exists "$TOOL"; then
    ok "$TOOL already installed ($(command -v "$TOOL"))"
    return 0
  fi
  info "Installing $TOOL via $PM..."
  case "$PM" in
    brew)   brew install "$PKG" ;;
    apt)    sudo apt-get install -y "$PKG" ;;
    dnf)    sudo dnf install -y "$PKG" ;;
    pacman) sudo pacman -S --noconfirm "$PKG" ;;
  esac
  ok "$TOOL installed"
}

# ---------------------------------------------------------------------------
# 2. Install core tools: git, uv, Node.js, gh
# ---------------------------------------------------------------------------

info "Step 2: Installing core tools (git, uv, node, gh)..."

pm_install git git

# uv: use the platform package where one exists, otherwise the official script.
case "$PM" in
  brew) pm_install uv uv ;;
  apt|dnf|pacman)
    if command_exists uv; then
      ok "uv already installed"
    else
      info "Installing uv via the official install script (no distribution package)..."
      curl -LsSf https://astral.sh/uv/install.sh | sh
      ok "uv installed"
    fi
    ;;
esac

# Node.js: the binary is node everywhere, the package is nodejs outside brew.
case "$PM" in
  brew)          pm_install node node ;;
  apt|dnf|pacman) pm_install node nodejs ;;
esac

# GitHub CLI
case "$PM" in
  brew)   pm_install gh gh ;;
  apt)
    if command_exists gh; then
      ok "gh already installed"
    else
      # gh is not in the default apt repositories, so add GitHub's signed one.
      info "Installing gh via the official apt repository..."
      sudo mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update
      sudo apt-get install -y gh
      ok "gh installed"
    fi
    ;;
  dnf)
    if command_exists gh; then
      ok "gh already installed"
    else
      info "Installing gh via the official dnf repository..."
      sudo dnf install -y 'dnf-command(config-manager)' || true
      sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install -y gh
      ok "gh installed"
    fi
    ;;
  pacman) pm_install gh github-cli ;;
esac

# ---------------------------------------------------------------------------
# 3. Install west via uv tool
# ---------------------------------------------------------------------------

info "Step 3: Installing west via uv tool..."

if uv tool list 2>/dev/null | grep -q '^west '; then
  ok "west already installed via uv tool"
else
  uv tool install west
  ok "west installed"
fi

# ---------------------------------------------------------------------------
# 4. Ensure ~/.local/bin is on PATH (uv tool shims land there)
# ---------------------------------------------------------------------------

info "Step 4: Ensuring ~/.local/bin is on PATH..."

LOCAL_BIN="$HOME/.local/bin"

if echo "$PATH" | grep -q "$LOCAL_BIN"; then
  ok "~/.local/bin already on PATH"
else
  warn "~/.local/bin not on PATH; running 'uv tool update-shell' to add it..."
  uv tool update-shell
  # Also export it for the remainder of this script's run, because the shell
  # profile edit only takes effect in future shells.
  export PATH="$LOCAL_BIN:$PATH"
  ok "~/.local/bin added to PATH (restart your shell, or run: export PATH=\"$LOCAL_BIN:\$PATH\")"
fi

# Verify west is actually reachable before anything depends on it.
if ! command_exists west; then
  die "west command not found even after the PATH update. Check that $LOCAL_BIN is in your shell's PATH."
fi
ok "west reachable: $(west --version)"

# ---------------------------------------------------------------------------
# 5. Silence the Zephyr-base warning
# ---------------------------------------------------------------------------

info "Step 5: Silencing the Zephyr-base warning..."

# Loom uses west purely as a multi-repository orchestrator, with no Zephyr
# build system in sight. Setting this globally silences the warning before the
# workspace exists; it is set again on the workspace itself after init.
# west config is idempotent, so re-running is harmless.
west config --global zephyr.base not-using-zephyr 2>/dev/null || true
ok "zephyr.base set to not-using-zephyr (global)"

# ---------------------------------------------------------------------------
# 6. Initialise the west workspace and clone the sibling repositories
# ---------------------------------------------------------------------------

info "Step 6: Initialising the west workspace..."

if [ -d "$WORKSPACE_DIR/.west" ]; then
  ok ".west directory already exists; skipping west init"
else
  info "Running: west init -l manifest (from $WORKSPACE_DIR)"
  (cd "$WORKSPACE_DIR" && west init -l manifest)
  ok "west workspace initialised"
fi

# The -k and -r flags match what `manage update` passes. On a first run there is
# no checked-out branch to preserve, so they change nothing; on a re-run of this
# bootstrap, which is meant to be safe, they keep branches checked out instead of
# detaching HEAD in every project.
info "Running: west update (clone or fast-forward every project)..."
(cd "$WORKSPACE_DIR" && west update -k -r)
ok "west update complete"

# Apply the zephyr.base setting to the local workspace as well.
(cd "$WORKSPACE_DIR" && west config zephyr.base not-using-zephyr 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 7. Link the workspace-root files (idempotent)
# ---------------------------------------------------------------------------

info "Step 7: Linking workspace-root files..."

# The links are relative, with targets under manifest/, for two reasons: a
# `west update` of the manifest propagates edits straight through, and the
# links survive the whole workspace being moved.

link_root_file() {
  SRC_REL="$1"    # path relative to the workspace root, always under manifest/
  DEST_NAME="$2"  # the name to create at the workspace root
  if [ -f "$WORKSPACE_DIR/$SRC_REL" ]; then
    ln -sfn "$SRC_REL" "$WORKSPACE_DIR/$DEST_NAME"
    ok "$DEST_NAME symlinked to $SRC_REL"
  else
    warn "$SRC_REL not found; skipping $DEST_NAME"
  fi
}

link_root_file "manifest/workspace-root/README.md"  "README.md"
link_root_file "manifest/workspace-root/AGENTS.md"  "AGENTS.md"
link_root_file "manifest/workspace-root/CLAUDE.md"  "CLAUDE.md"
link_root_file "manifest/workspace-root/.gitignore" ".gitignore"

# The manage launcher needs the executable bit at its source, since the
# symlink carries the mode of whatever it points at.
if [ -f "$MANIFEST_DIR/manage.sh" ]; then
  chmod +x "$MANIFEST_DIR/manage.sh"
fi
link_root_file "manifest/manage.sh" "manage.sh"

# ---------------------------------------------------------------------------
# 8. Ensure the workspace directories exist (idempotent)
# ---------------------------------------------------------------------------

# west materialises a parent directory only when a project's path lands inside
# it, so directories that hold no project yet would be missing after a fresh
# checkout. Create them here so the layout is the same on every machine and on
# both platforms.
info "Step 8: Ensuring workspace directories..."
for dir in corpus packages tmp; do
  mkdir -p "$WORKSPACE_DIR/$dir"
  ok "$dir/ present"
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

info "Bootstrap complete."
info "Next steps:"
info "  1. Restart your shell (or run: export PATH=\"$LOCAL_BIN:\$PATH\")"
info "  2. Run './manage.sh help' from the workspace root for common tasks."
info "  3. Read README.md at the workspace root, or manifest/README.md for the full run-book."
