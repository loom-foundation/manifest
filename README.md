# workspace

The coordinator repository for the Loom Foundation workspace.
It holds the [west](https://docs.zephyrproject.org/latest/develop/west/) multi-repository manifest ([`west.yml`](west.yml)), the bootstrap scripts, and the workspace management CLI (`manage.mjs`).

west is used here purely as a multi-repository orchestrator: independent sibling checkouts under one root.
No Zephyr RTOS or build-system functionality is involved.

> **Bootstrap is a setup step you run yourself.**
> It installs system packages and modifies your PATH, so nothing runs it on your behalf.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| A shell | `sh` on macOS and Linux; PowerShell 5.1 or later on Windows. |
| A platform package manager | macOS: [Homebrew](https://brew.sh) (install it yourself; the scripts stop with a message if it is missing). Linux: apt, dnf, or pacman. Windows: winget, which ships with Windows 10 1709 and later. |

Everything else is installed for you, including git.
On Linux the package steps use `sudo`, so you need to be able to install packages on the machine.

---

## Setup

### Recommended: the one-line installer

Run it in the directory where you want the workspace to appear.

**macOS and Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/loom-foundation/workspace/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/loom-foundation/workspace/main/install.ps1 | iex
```

The workspace directory is named `loom-foundation` by default, created inside the directory you ran the command from.
The installer prints the proposed path and waits: press Enter to accept it, or type a different path.
Set `LOOM_WORKSPACE` beforehand to skip the prompt entirely (`LOOM_WORKSPACE=~/work/loom` on macOS and Linux, `$env:LOOM_WORKSPACE = 'C:\work\loom'` on Windows).
When the installer runs with no terminal attached, it takes the default without prompting.

The installer installs git if it is absent, creates the workspace directory, clones this repository into it as `workspace`, and then hands off to `bootstrap/bootstrap.sh` (or `bootstrap\bootstrap.ps1`).
Every Loom Foundation repository is public, so no GitHub sign-in and no organisation membership are needed; the clones happen over plain https.

> **Status of the Windows path.**
> The Windows scripts (`install.ps1` and `bootstrap/bootstrap.ps1`) are ported from an implementation that was validated on Windows, but this port has not itself been run on Windows and has not been parse-checked, because no PowerShell interpreter was available on the machine where it was written.
> It is pending its first real run.
> If you hit something, the fix is likely small and worth reporting.

### Windows prerequisites

Enable **Developer Mode** before running the bootstrap: Settings, System, For developers.
The bootstrap creates symbolic links at the workspace root, and without Developer Mode a non-administrator PowerShell cannot create them.
The bootstrap checks the setting before doing any work, and stops with step-by-step instructions if it is off.

Use a normal, non-elevated PowerShell.
winget does not need administrator rights, and neither does anything else the bootstrap does.

### Manual setup

If you would rather clone first, clone **into** the directory you intend to be the workspace, and only then run the bootstrap.

```sh
mkdir -p ~/Code/loom-foundation
git clone https://github.com/loom-foundation/workspace.git ~/Code/loom-foundation/workspace
sh ~/Code/loom-foundation/workspace/bootstrap/bootstrap.sh
```

On Windows, the last line becomes `~\Code\loom-foundation\workspace\bootstrap\bootstrap.ps1`.

The order matters.
The bootstrap resolves the workspace top directory as the **parent of the `workspace` directory**, working from the script's own location, and runs `west init -l workspace` from there.
So `workspace` must already sit inside the directory you want to become the workspace.
Clone it into `~/Code` and `~/Code` becomes the workspace top directory, with every project checkout landing beside the rest of your work.
The one-line installer arranges the correct order for you.

### What the bootstrap does

Every step checks for existing state before acting, so re-running it is safe.

1. Detects the OS and package manager; on Windows, verifies winget and Developer Mode.
2. Installs git, uv, Node.js, and the GitHub CLI.
3. Installs west with `uv tool install west`.
4. Ensures the uv shim directory (`~/.local/bin`, or `%USERPROFILE%\.local\bin`) is on PATH via `uv tool update-shell`, then verifies that `west` resolves.
5. Sets `zephyr.base` to `not-using-zephyr`, so west stops warning about a Zephyr tree that does not exist.
6. Runs `west init -l workspace` when `.west/` is absent, then `west update -k -r`.
7. Creates the workspace-root symbolic links, all with relative targets under `workspace/`, so they survive the workspace being moved.
8. Creates `corpus/`, `packages/`, and `tmp/`.

Restart your shell afterwards, so the PATH change takes effect.

---

## What gets installed

| Tool | How | Purpose |
|---|---|---|
| **git** | package manager (winget id `Git.Git`) | Clone and manage the repositories. |
| **uv** | package manager where one packages it, otherwise the official script (winget id `astral-sh.uv`) | Provides Python, and installs west. |
| **west** | `uv tool install west` | The multi-repository workspace orchestrator. |
| **Node.js** | package manager (winget id `OpenJS.NodeJS.LTS`) | The runtime for `manage.mjs`. |
| **GitHub CLI (`gh`)** | package manager (winget id `GitHub.cli`) | Creating repository remotes. |

The **Claude Code CLI is not installed** by the bootstrap.
Whether to run an AI coding agent, and which one, is left to the individual.

### The GitHub CLI is installed but not authenticated

The bootstrap installs `gh` and stops there.
Run `gh auth login` yourself the first time you need it, which is when you run `manage new-repo --remote`.
Everything else works unauthenticated, including the installer, the bootstrap, and `west update`, because every Loom Foundation repository is public.

---

## Workspace layout

After the bootstrap completes:

```
loom-foundation/              # the workspace top directory
├── .west/config              # west marker; points at workspace/west.yml
├── README.md                 # symlink -> workspace/workspace-root/README.md
├── AGENTS.md                 # symlink -> workspace/workspace-root/AGENTS.md
├── CLAUDE.md                 # symlink -> workspace/workspace-root/CLAUDE.md
├── .gitignore                # symlink -> workspace/workspace-root/.gitignore
├── manage.sh                 # symlink -> workspace/manage.sh   (macOS and Linux)
├── manage.cmd                # symlink -> workspace/manage.cmd  (Windows)
├── workspace/                # this repository, the entry point
│   ├── west.yml              # the repository-of-repositories manifest
│   ├── manage.mjs            # the workspace management CLI (all the logic)
│   ├── manage.sh             # POSIX launcher
│   ├── manage.cmd            # Windows launcher
│   ├── install.sh            # one-line installer, macOS and Linux
│   ├── install.ps1           # one-line installer, Windows
│   ├── bootstrap/
│   │   ├── bootstrap.sh      # macOS and Linux
│   │   └── bootstrap.ps1     # Windows
│   ├── repo-template/        # starter files copied into new repositories
│   ├── workspace-root/       # the sources of the workspace-root symlinks
│   └── README.md             # this file
├── .github/                  # organisation profile and community health files
├── corpus/
│   └── note/                 # the Note methodology corpus
├── manifesto/                # the Loom Manifesto
├── org/                      # brand, naming, trademarks, stewardship
├── packages/                 # created by bootstrap; holds no project yet
└── tmp/                      # created by bootstrap; ignored by git
```

The project paths come from [`west.yml`](west.yml), which is the single source of truth for what the workspace contains.
`corpus/`, `packages/`, and `tmp/` are created by the bootstrap, because west materialises a parent directory only when a project's path lands inside it.

---

## Update flow

Pull the repository you are working in, then update the workspace from the top directory:

```sh
git pull                # in workspace, or any project repository
./manage.sh update      # from the workspace top directory
```

`manage update` runs `west update -k -r`.
Both flags matter.
`-k` (`--keep-descendants`) leaves a checked-out branch alone when it already contains the new manifest revision; `-r` (`--rebase`) rebases the branch onto the new revision otherwise.
Without them, west detaches HEAD in every project it touches on every update, which is rarely what you want in a workspace you are also committing to.
Neither flag has a config-file equivalent, so both have to be passed on every invocation; that is the whole reason `manage update` exists.

Both flags act on a branch that is already checked out, so they do not apply to the very first clone.
A freshly bootstrapped workspace therefore has every project on a detached HEAD, at a local ref west calls `manifest-rev`.
Before you start working in a project, put it on a branch:

```sh
cd <project>
git fetch origin
git checkout main
```

From then on `manage update` keeps that branch checked out.

To snapshot every project's revision to a commit SHA, for a reproducible checkout:

```sh
west manifest --freeze > west.lock.yml
```

`--freeze` writes the resolved manifest to stdout, so redirect it to whatever file you want to keep.

### Using west directly

`manage` is a convenience wrapper.
west remains available, and these are the incantations worth knowing:

```sh
west update -k -r                      # sync the workspace to the manifest
west list                              # list the projects
west status                            # git status across every repository
west forall -c "git pull --ff-only"    # pull every repository
west forall -c "<any command>"         # run a command in every repository
```

---

## Creating a new repository

### With `manage new-repo`

```sh
./manage.sh new-repo <name> "<description>" [--into <dir>] [--role <role>] [--remote]
```

Step by step, this:

1. Validates the name against `^[a-z][a-z0-9-]*$`: lowercase letters, digits, and hyphens, starting with a letter.
2. Resolves the target directory. By default the repository is created at the workspace top directory; `--into <dir>` places it at `<dir>/<name>` instead. `<dir>` is workspace-relative, and an absolute path, or one that escapes the workspace, is rejected.
3. If the directory does not exist, creates it and copies `repo-template/.gitignore` and `repo-template/README.md` into it. If the directory exists **and is already a git repository**, adopts it as it stands and prints its current HEAD, overwriting nothing. If it exists and is not a git repository, the command stops and says so.
4. For a newly created repository, runs `git init`, `git add .`, and a first commit (`chore: scaffold <name>`), so the repository is immediately push-ready. A failure here is reported rather than swallowed.
5. Inserts a project block into `west.yml` carrying `name`, `path`, `description`, and `userdata.role`. The remote and the revision come from the manifest's `defaults:` block, so they are not repeated per project. The block goes into the `projects:` list, at the indentation the existing entries use, rather than being appended at end of file. When the structure cannot be recognised with confidence, nothing is written and the block is printed for you to place by hand. When `west.yml` already declares the project, it is left as it stands.
6. Without `--remote`, prints the `gh repo create` command (and the `git remote add` plus `git push -u` alternative) for you to run. With `--remote`, runs it: `gh repo create <org>/<name> --public --source <dir> --push`. If the repository already has an `origin`, it pushes the current branch instead of creating anything.

The role defaults to the repository name with hyphens replaced by spaces; `--role` overrides it.
The organisation is derived from an existing project's url as reported by `west list`, falling back to `loom-foundation`.

> `--remote` creates a **public** repository.
> The workspace manifest is public, so a private repository listed in it would simply fail to clone for everyone else.

Afterwards, commit the `west.yml` change in `workspace`, and run `./manage.sh update` so west starts tracking the new repository.

### By hand

1. Create the GitHub repository: `gh repo create loom-foundation/<name> --public`.
2. Copy `workspace/repo-template/.gitignore` and `workspace/repo-template/README.md` into it, and fill the README in.
3. Register it: add a project block to `west.yml` with `name`, `path`, a one-line `description`, and `userdata: { role: <role> }`. This is the only place the repository list lives.
4. Run `west update` (or `./manage.sh update`) from the workspace top directory to materialise it.
5. Commit the `west.yml` change in `workspace`.

---

## The `manage` command reference

Run these from the workspace top directory, where the bootstrap placed the launcher symlink.
Use `./manage.sh` on macOS and Linux, `.\manage.cmd` on Windows.
Both are thin shims over `workspace/manage.mjs`; `node workspace/manage.mjs <command>` works identically, from any directory, because the CLI resolves its paths from its own location rather than from your current one.

| Command | What it does |
|---|---|
| `help` | Prints the usage text. This is the default when no command is given. |
| `doctor` | Checks git, node, west, uv, and gh on PATH, printing each tool's version or `MISSING`. Exits non-zero when a **required** tool (git, node, west) is absent; uv and gh are reported as optional. |
| `update` | Runs `west update -k -r`. |
| `push` | Runs `west forall -c "git push"`, pushing every repository. |
| `status` | Runs `west list` for a workspace overview. Prints a `west init -l workspace` hint when the workspace is not initialised. |
| `new-repo <name> "<description>"` | Scaffolds a new repository, or adopts an existing local one. See above. |

The flags, all of them for `new-repo` only:

| Flag | Effect |
|---|---|
| `--into <dir>` | Creates the repository at `<dir>/<name>` instead of at the workspace top directory. `<dir>` is workspace-relative, for example `--into packages`. |
| `--role <role>` | Sets `userdata.role` in the `west.yml` block. Defaults to the repository name with hyphens replaced by spaces. |
| `--remote` | Creates the public GitHub repository with `gh repo create` and pushes, instead of printing the commands for you to run. Needs `gh auth login` first. |

An unknown command prints the help text and exits non-zero.

---

## Further reading

- [`workspace-root/README.md`](workspace-root/README.md) is the day-to-day reference, symlinked to the workspace root. It is deliberately short; the depth lives here.
- [`workspace-root/AGENTS.md`](workspace-root/AGENTS.md) is the brief for agents working in the workspace, symlinked to the workspace root as `AGENTS.md` and pointed at by `CLAUDE.md`.
- The Foundation records the intent behind its work as Note corpora. The corpus in this workspace is `corpora/note`; start at its `README.md`. Foundation-wide governance instruments live in `org/governance/`, and the reasoning behind all of it is in `manifesto/`.
- [`repo-template/`](repo-template/) holds the starter files copied into every new repository.
