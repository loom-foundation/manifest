#!/usr/bin/env node
/**
 * manage.mjs: cross-platform Loom Foundation workspace management CLI.
 *
 * ESM, Node built-ins only (no npm dependencies).
 * Paths are resolved relative to this script, so it works from any directory.
 *
 * Usage (via the workspace-root launchers, or node directly):
 *   ./manage.sh <command> [args]      # macOS / Linux
 *   .\manage.cmd <command> [args]     # Windows
 *   node manage.mjs <command> [args]
 *
 * Commands:
 *   help                                  Show this help text (default)
 *   doctor                                Check required tools are on PATH
 *   update                                Run `west update -k -r` (clone or
 *                                         fast-forward every repository, keeping
 *                                         and rebasing checked-out branches
 *                                         instead of detaching HEAD)
 *   push                                  Run `west forall -c "git push"` (push every repo)
 *   status                                Run `west list` (workspace overview)
 *   new-repo <name> "<desc>" [--into <dir>] [--role <r>] [--remote] [--protect]
 *                                         Scaffold a new repository in the
 *                                         workspace, or adopt one that already
 *                                         exists locally with content
 *                                         (--into places it at <dir>/<name>;
 *                                         --protect marks it protected in
 *                                         west.yml and, with --remote, applies
 *                                         the protection after the push)
 *   protect [<name>...]                   Apply main-branch protection to every
 *                                         project west.yml marks
 *                                         `userdata: protected: true` (or only
 *                                         to the named ones)
 */

import { spawnSync }                     from 'node:child_process';
import { existsSync, mkdirSync,
         readFileSync, writeFileSync,
         copyFileSync }                  from 'node:fs';
import path                              from 'node:path';
import { fileURLToPath }                 from 'node:url';

// ---------------------------------------------------------------------------
// Paths, all resolved relative to this script's own location (workspace/), so
// the CLI behaves identically whatever the current working directory is.
// ---------------------------------------------------------------------------
const HERE        = path.dirname(fileURLToPath(import.meta.url)); // workspace/
const TOPDIR      = path.resolve(HERE, '..');                     // workspace topdir
const SCAFFOLD    = path.join(HERE, 'repo-template');
const WEST_YML    = path.join(HERE, 'west.yml');

// Files every scaffolded repository starts from. They ship with this repository,
// so their absence is a broken workspace, not a normal condition.
const SCAFFOLD_FILES = ['.gitignore', 'README.md'];

// ---------------------------------------------------------------------------
// Cross-platform helpers
// ---------------------------------------------------------------------------

/**
 * Run a command, inheriting stdio so output goes straight to the terminal.
 * Returns the exit code (0 means success).
 * On Windows, shell: true is required for PATH-based tool resolution.
 */
function run(cmd, args = [], opts = {}) {
  const useShell = process.platform === 'win32';
  const result = spawnSync(cmd, args, {
    stdio: 'inherit',
    shell: useShell,
    ...opts,
  });
  if (result.error) {
    // ENOENT means the executable was not found at all.
    if (result.error.code === 'ENOENT') return 127;
    throw result.error;
  }
  return result.status ?? 1;
}

/**
 * Capture a command's stdout silently (used for version checks).
 * Returns { ok, stdout, stderr }, where ok means the process exited 0.
 */
function capture(cmd, args = []) {
  const useShell = process.platform === 'win32';
  const result = spawnSync(cmd, args, {
    stdio: ['ignore', 'pipe', 'pipe'],
    shell: useShell,
    encoding: 'utf8',
  });
  const ok = !result.error && result.status === 0;
  return {
    ok,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

/** Extract the first non-empty line of a string (usually "git version 2.x"). */
function firstLine(s) {
  return s.split(/\r?\n/).find(l => l.trim()) || '';
}

// ---------------------------------------------------------------------------
// Project listing. This delegates to `west list` instead of hand-parsing
// west.yml, because west owns the manifest format: merges, imports, defaults,
// userdata and the rest. Re-deriving any of that here would be fragile and
// would understand only a small fragment of the schema.
// ---------------------------------------------------------------------------

/**
 * List the workspace's projects via `west list`, as { name, path, url }.
 *
 * Runs: west list -f "{name}|{path}|{url}"
 *
 * The manifest self-entry (`manifest|workspace|N/A`) is skipped, as is any row
 * with an empty url. Only rows carrying a real remote url are returned.
 *
 * Returns [] (and prints a loud diagnostic to stderr) when `west` is missing
 * or `west list` fails, for instance because the workspace is not initialised.
 */
function westProjects() {
  const result = capture('west', ['list', '-f', '{name}|{path}|{url}']);
  if (!result.ok) {
    console.error('Could not query projects via `west list`. Is the workspace initialised? Run: west init -l workspace');
    return [];
  }

  const projects = [];
  for (const raw of result.stdout.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const [name, projPath, url] = line.split('|');
    if (!url || url === 'N/A') continue; // manifest self-entry, or no remote
    projects.push({ name, path: projPath, url });
  }
  return projects;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function cmdHelp() {
  console.log(`
manage: the Loom Foundation workspace management CLI

Usage:
  ./manage.sh <command> [args]      (macOS / Linux)
  .\\manage.cmd <command> [args]     (Windows)

Commands:
  help                                    Print this help text (default)

  doctor                                  Check git, node, west, uv, and gh are
                                          on PATH; print each tool's version or
                                          "MISSING". Exits non-zero if any
                                          required tool (git, node, west) is absent.

  update                                  Run \`west update -k -r\` to clone or
                                          fast-forward every repository declared in
                                          west.yml, keeping checked-out branches
                                          (rebasing them onto the new manifest-rev)
                                          instead of detaching HEAD.
                                          Run from the workspace topdir.

  push                                    Push every repository (\`west forall -c "git push"\`).
                                          Run from the workspace topdir.

  status                                  Run \`west list\` for a workspace overview.
                                          If west is not initialised, a hint is shown.

  protect [<name>...]                     Apply main-branch protection to every
                                          project west.yml marks with
                                          \`userdata: protected: true\`, or only
                                          to the named ones (each must still be
                                          marked; west.yml is the record of
                                          which repositories are protected).
                                          The protection requires a pull request
                                          (no approvals demanded), forbids force
                                          pushes and deletions, and binds
                                          administrators. A project may also
                                          carry \`required-checks: […]\` in its
                                          userdata; those status checks are then
                                          required and must be up to date.
                                          Needs \`gh\` authenticated with admin
                                          rights on the repositories.

  new-repo <name> "<description>"         Scaffold a new repository, or adopt one
           [--into <dir>]                   that already exists locally with content:
           [--role <role>]                  • Validates the name (lowercase, hyphens)
           [--remote] [--protect]           • If <workspace>/<dir>/<name>/ does not
                                               exist: creates it, copies the scaffold
                                               .gitignore and README.md, then
                                               git-inits and commits it
                                             • If it already exists and is a git
                                               repository: adopts it as-is (no
                                               scaffold overwrite), and just wires
                                               it up
                                               (<dir> defaults to the workspace
                                               topdir; it is workspace-relative,
                                               for example --into packages)
                                             • Appends a project block to west.yml
                                               (path: <dir>/<name>), unless one is
                                               already there
                                             • With --remote: runs
                                               \`gh repo create --public --source
                                               --push\`, which creates the remote,
                                               wires it up, and pushes. When an
                                               \`origin\` is already set, pushes the
                                               current branch to it instead.
                                               Without --remote: prints the
                                               commands so you can run them yourself
                                             • With --protect: marks the project
                                               \`protected: true\` in west.yml and,
                                               when --remote pushed it, applies the
                                               protection right away
                                             • Prints next steps
`.trim());
}

function cmdDoctor() {
  // Required tools: exit non-zero if any are missing.
  // Optional tools: informational only.
  const required = ['git', 'node', 'west'];
  const optional = ['uv', 'gh'];

  let anyMissing = false;

  const check = (name, isRequired) => {
    const r = capture(name, ['--version']);
    if (r.ok) {
      const ver = firstLine(r.stdout || r.stderr);
      console.log(`  ${name.padEnd(8)} ${ver}`);
    } else {
      const tag = isRequired ? 'MISSING (required)' : 'MISSING (optional)';
      console.log(`  ${name.padEnd(8)} ${tag}`);
      if (isRequired) anyMissing = true;
    }
  };

  console.log('Doctor: checking tools on PATH.\n');
  for (const t of required) check(t, true);
  for (const t of optional) check(t, false);

  if (anyMissing) {
    console.error('\nOne or more required tools are missing. See workspace/README.md, Prerequisites.');
    process.exit(1);
  } else {
    console.log('\nAll required tools found.');
  }
}

function cmdUpdate() {
  // -k/--keep-descendants: when a checked-out branch already contains the new
  // manifest-rev, leave it checked out instead of detaching HEAD.
  // -r/--rebase: otherwise rebase (fast-forward) the checked-out branch onto
  // the new manifest-rev, again instead of detaching HEAD.
  // Neither flag has a config-file equivalent in west, so both have to be
  // passed explicitly on every single invocation.
  const code = run('west', ['update', '-k', '-r']);
  if (code === 127) {
    console.error("'west' not found. Install it with: uv tool install west");
    process.exit(1);
  }
  process.exit(code);
}

function cmdStatus() {
  const code = run('west', ['list']);
  if (code === 127) {
    console.error("'west' not found. Install it with: uv tool install west");
    process.exit(1);
  }
  if (code !== 0) {
    console.error('\nHint: if the workspace is not initialised, run: west init -l workspace');
  }
  process.exit(code);
}

function cmdPush() {
  const code = run('west', ['forall', '-c', 'git push']);
  if (code === 127) {
    console.error("'west' not found. Install it with: uv tool install west");
    process.exit(1);
  }
  process.exit(code);
}

function cmdNewRepo(args) {
  // Parse args: new-repo <name> "<description>" [--into <dir>] [--role <role>] [--remote]
  const positional = [];
  let role      = null;
  let doRemote  = false;
  let doProtect = false;
  let into      = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--role' && args[i + 1]) {
      role = args[++i];
    } else if (args[i] === '--into' && args[i + 1]) {
      into = args[++i];
    } else if (args[i] === '--remote') {
      doRemote = true;
    } else if (args[i] === '--protect') {
      doProtect = true;
    } else {
      positional.push(args[i]);
    }
  }

  const [name, description] = positional;

  if (!name || !description) {
    console.error('Usage: manage.mjs new-repo <name> "<description>" [--into <dir>] [--role <role>] [--remote]');
    process.exit(1);
  }

  // Validate the name: lowercase letters, digits and hyphens, starting with a letter.
  if (!/^[a-z][a-z0-9-]*$/.test(name)) {
    console.error(`Invalid repository name "${name}". Use lowercase letters, digits, and hyphens (it must start with a letter).`);
    process.exit(1);
  }

  // Resolve the target directory. `--into` names a workspace-relative directory
  // the repository is created inside, so the repository path becomes
  // <into>/<name>; the default is the workspace topdir. west.yml paths are
  // always forward-slashed, so separators are normalised, and absolute paths or
  // `..` escapes outside the workspace are rejected.
  const { repoDir, repoPathPosix } = resolveRepoTarget(into, name);

  const dirExists  = existsSync(repoDir);
  const gitDir     = path.join(repoDir, '.git');
  const isAdopting = dirExists && existsSync(gitDir);

  if (dirExists && !isAdopting) {
    console.error(`Directory already exists and is not a git repository: ${repoDir}`);
    console.error('Choose a different name, remove the directory, or `git init` it yourself first.');
    process.exit(1);
  }

  // Derive the role from the name when one was not supplied. Loom repositories
  // carry no organisation prefix, so the name is used as it stands.
  const effectiveRole = role || name.replace(/-/g, ' ');

  if (isAdopting) {
    // An existing local repository with content, for example one authored ahead
    // of its upstream remote. Adopt it as it stands rather than scaffolding over it.
    console.log(`\nAdopting existing repository at ${repoDir} ...`);
    const { ok, stdout } = capture('git', ['-C', repoDir, 'log', '-1', '--oneline']);
    if (!ok || !stdout.trim()) {
      console.warn('  Warning: the repository has no commits yet. Commit something before pushing.');
    } else {
      console.log(`  HEAD: ${stdout.trim()}`);
    }
  } else {
    // 1. Check the scaffold before creating anything. repo-template/ ships with
    //    the workspace repository, so a missing file means a broken workspace
    //    rather than a normal condition. Scaffolding on regardless would leave
    //    an empty directory and a repository with no commits.
    const missing = SCAFFOLD_FILES
      .map(f => path.join(SCAFFOLD, f))
      .filter(src => !existsSync(src));
    if (missing.length > 0) {
      console.error('\nScaffold files are missing, so the repository was not created.');
      for (const src of missing) console.error(`  not found: ${src}`);
      console.error('\nrepo-template/ ships with the workspace repository. Restore it (for example');
      console.error('with `git -C ' + HERE + ' status`) and run this command again.');
      process.exit(1);
    }

    // 2. Create the directory.
    console.log(`\nCreating ${repoDir} ...`);
    mkdirSync(repoDir, { recursive: true });

    // 3. Copy the scaffold files.
    for (const f of SCAFFOLD_FILES) {
      copyFileSync(path.join(SCAFFOLD, f), path.join(repoDir, f));
      console.log(`  copy   ${f}`);
    }

    // 4. git init plus a first commit, so the repository is immediately
    //    push-ready. A failure here is reported rather than swallowed: a
    //    repository with no commits cannot be pushed, and the cause (missing
    //    git identity, for instance) needs to reach the user.
    console.log('\nInitialising git repository ...');
    for (const [label, argv] of [
      ['git init',   ['init', '-q']],
      ['git add',    ['add', '.']],
      ['git commit', ['commit', '-q', '-m', `chore: scaffold ${name}`]],
    ]) {
      const code = run('git', ['-C', repoDir, ...argv]);
      if (code !== 0) {
        console.error(`\n${label} failed (exit ${code}) in ${repoDir}.`);
        console.error('The directory was created but the repository is not usable yet. Fix the');
        console.error('cause, then commit by hand before running `./manage.sh update`.');
        process.exit(code);
      }
    }
  }

  // 4. Append the project block to west.yml, unless it is already declared
  //    there, as happens for a repository adopted after being wired in by hand.
  if (westYmlHasProject(name)) {
    console.log(`\nwest.yml already declares project "${name}"; leaving it as it stands.`);
    if (doProtect && !westYmlProtection().get(name)?.protected) {
      console.log('  Add `protected: true` under its `userdata:` block by hand to record the protection.');
    }
  } else {
    console.log('\nAdding the project block to west.yml ...');
    appendToWestYml({ name, path: repoPathPosix, description, role: effectiveRole, protected: doProtect });
  }

  // 5. Remote handling.
  // Derive the organisation from an existing project's url:
  // https://github.com/<org>/<repo> yields <org> (the second-to-last path
  // segment). Fall back to the known default organisation when `west list`
  // yields no usable project, for instance when west is missing, the workspace
  // is not initialised, or no project has a remote url yet.
  const projects = westProjects();
  const firstUrl = projects.length > 0 ? projects[0].url : null;
  const org = firstUrl
    ? firstUrl.replace(/\/+$/, '').split('/').slice(-2, -1)[0]
    : 'loom-foundation';
  const ghCreateCmd  = `gh repo create ${org}/${name} --public --source ${repoDir} --push`;
  const remoteUrl    = `https://github.com/${org}/${name}.git`;
  const branch       = currentBranch(repoDir) || 'main';

  console.log('\n' + '-'.repeat(41));
  if (doRemote) {
    console.log('\nCreating the GitHub remote and pushing ...');
    const hasOriginResult = capture('git', ['-C', repoDir, 'remote', 'get-url', 'origin']);
    if (hasOriginResult.ok) {
      console.log(`  origin is already set to ${hasOriginResult.stdout.trim()}; pushing ${branch}.`);
      const pushCode = run('git', ['-C', repoDir, 'push', '-u', 'origin', branch]);
      if (pushCode !== 0) console.error('  git push failed.');
    } else {
      const ghCode = run('gh', ['repo', 'create', `${org}/${name}`, '--public', '--source', repoDir, '--push']);
      if (ghCode !== 0) {
        console.error('gh repo create failed. You can retry it manually:');
        console.error(`  ${ghCreateCmd}`);
      }
    }
    if (doProtect) {
      console.log('\nApplying main-branch protection ...');
      applyProtection(org, name, []);
    }
  } else {
    console.log('\nTo create the GitHub remote and push, run:');
    console.log(`  ${ghCreateCmd}`);
    console.log('  (or, if the GitHub repository already exists:)');
    console.log(`  cd ${repoDir}`);
    console.log(`  git remote add origin ${remoteUrl}`);
    console.log(`  git push -u origin ${branch}`);
    if (doProtect) {
      console.log(`  then: ./manage.sh protect ${name}`);
    }
  }

  // 6. Print the next steps.
  const remoteSteps = doRemote
    ? []
    : [`  · Create the remote and push (see the command${isAdopting ? '' : 's'} above).`];
  console.log(`
Next steps:
${isAdopting ? '' : `  · Edit ${repoDir}/README.md to fill in the description.\n`}${remoteSteps.join('\n')}
  · From the workspace topdir, run \`./manage.sh update\` to let west track the repository.
  · Commit the west.yml update in workspace (if it changed).
`);
}

// ---------------------------------------------------------------------------
// Branch protection
// ---------------------------------------------------------------------------

/**
 * Read each project's protection metadata from west.yml.
 *
 * `west list` cannot print userdata, so this scans west.yml itself, in the
 * same targeted spirit as westYmlHasProject(): only `- name:` boundaries and
 * the two protection keys are recognised, and anything else is left to west.
 *
 * Returns a Map from project name to { protected, requiredChecks }.
 */
function westYmlProtection() {
  const src   = readFileSync(WEST_YML, 'utf8');
  const lines = src.split(/\r?\n/);
  const map   = new Map();

  let current = null;
  for (const line of lines) {
    const nameMatch = line.match(/^\s*-\s*name:\s*(\S+)\s*$/);
    if (nameMatch) {
      current = { protected: false, requiredChecks: [] };
      map.set(nameMatch[1], current);
      continue;
    }
    if (!current) continue;
    if (/^\s*protected:\s*true\s*$/.test(line)) current.protected = true;
    const checks = line.match(/^\s*required-checks:\s*\[([^\]]*)\]\s*$/);
    if (checks) {
      current.requiredChecks = checks[1]
        .split(',')
        .map(s => s.trim().replace(/^["']|["']$/g, ''))
        .filter(Boolean);
    }
  }
  return map;
}

/**
 * The branch-protection settings applied to a protected project's main branch:
 * corpus-note's owner-agreed gate, generalised. A pull request is required (no
 * approvals demanded, so the owner merges their own), force pushes and branch
 * deletion are forbidden, and administrators are bound. When the project
 * declares `required-checks`, those status checks must pass and be up to date;
 * without them no status check is required, since demanding a context no
 * workflow reports would block every merge.
 */
function protectionBody(requiredChecks) {
  return {
    required_status_checks: requiredChecks.length > 0
      ? { strict: true, contexts: requiredChecks }
      : null,
    enforce_admins: true,
    required_pull_request_reviews: { required_approving_review_count: 0 },
    restrictions: null,
    allow_force_pushes: false,
    allow_deletions: false,
  };
}

/**
 * Apply main-branch protection to one repository via `gh api`.
 * Returns true on success.
 */
function applyProtection(org, name, requiredChecks) {
  const body = JSON.stringify(protectionBody(requiredChecks));
  const result = spawnSync('gh', [
    'api', '-X', 'PUT',
    `repos/${org}/${name}/branches/main/protection`,
    '--input', '-',
  ], {
    input: body,
    stdio: ['pipe', 'pipe', 'pipe'],
    shell: process.platform === 'win32',
    encoding: 'utf8',
  });
  if (result.error || result.status !== 0) {
    const detail = firstLine(result.stderr || '') || `exit ${result.status}`;
    console.error(`  ${name}: FAILED (${detail})`);
    return false;
  }
  const checksNote = requiredChecks.length > 0
    ? `required checks: ${requiredChecks.join(', ')}`
    : 'no required checks';
  console.log(`  ${name}: main protected (${checksNote})`);
  return true;
}

function cmdProtect(args) {
  const wanted     = args.filter(a => !a.startsWith('--'));
  const protection = westYmlProtection();
  const projects   = westProjects();
  if (projects.length === 0) process.exit(1);

  // Resolve each project's organisation from its own remote url.
  const byName = new Map(projects.map(p => [p.name, p]));

  let targets;
  if (wanted.length > 0) {
    targets = [];
    for (const name of wanted) {
      if (!byName.has(name)) {
        console.error(`Unknown project "${name}"; it carries no remote url in west.yml.`);
        process.exit(1);
      }
      if (!protection.get(name)?.protected) {
        console.error(`Project "${name}" is not marked protected in west.yml.`);
        console.error('west.yml is the record of which repositories are protected: add');
        console.error('`protected: true` under its `userdata:` block, then run this again.');
        process.exit(1);
      }
      targets.push(name);
    }
  } else {
    targets = projects
      .map(p => p.name)
      .filter(name => protection.get(name)?.protected);
    if (targets.length === 0) {
      console.log('No project in west.yml is marked `userdata: protected: true`; nothing to do.');
      return;
    }
  }

  console.log('Applying main-branch protection ...\n');
  let failures = 0;
  for (const name of targets) {
    const org = byName.get(name).url.replace(/\/+$/, '').split('/').slice(-2, -1)[0];
    const checks = protection.get(name).requiredChecks;
    if (!applyProtection(org, name, checks)) failures++;
  }
  if (failures > 0) {
    console.error(`\n${failures} of ${targets.length} repositories failed; see above.`);
    process.exit(1);
  }
  console.log(`\nAll ${targets.length} protected.`);
}

/** True when west.yml already carries a `- name: <name>` project entry. */
function westYmlHasProject(name) {
  const src = readFileSync(WEST_YML, 'utf8');
  const re  = new RegExp(`^\\s*-\\s*name:\\s*${name}\\s*$`, 'm');
  return re.test(src);
}

/** Current branch name of a git repository, or null when it cannot be determined. */
function currentBranch(repoDir) {
  const { ok, stdout } = capture('git', ['-C', repoDir, 'branch', '--show-current']);
  const branch = stdout.trim();
  return ok && branch ? branch : null;
}

// ---------------------------------------------------------------------------
// Target-directory resolution for new-repo
// ---------------------------------------------------------------------------

/**
 * Resolve where a new repository should be created.
 *
 * @param into  Optional workspace-relative directory to place the repository
 *              inside (the repository becomes <into>/<name>). Accepts either
 *              separator; defaults to the workspace topdir when null or empty.
 * @param name  The repository (and directory) name.
 * @returns { repoDir, repoPathPosix }: the absolute filesystem directory to
 *          create, and the forward-slashed path to write into west.yml.
 *
 * Exits with a message when `into` is absolute or escapes the workspace topdir.
 */
function resolveRepoTarget(into, name) {
  const raw = (into ?? '').trim();

  if (path.isAbsolute(raw)) {
    console.error(`--into must be a workspace-relative directory, not an absolute path: ${raw}`);
    process.exit(1);
  }

  // Normalise to a clean forward-slashed relative directory, dropping a leading
  // ./ and any trailing slash. An empty string means the workspace topdir.
  const dirPosix = raw
    .replace(/\\/g, '/')
    .replace(/\/+$/, '')
    .replace(/^\.\/+/, '')
    .replace(/^\.$/, '');

  const repoPathPosix = dirPosix ? `${dirPosix}/${name}` : name;

  // Guard against `..` traversal escaping the workspace.
  const repoDir = path.resolve(TOPDIR, repoPathPosix);
  const rel     = path.relative(TOPDIR, repoDir);
  if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) {
    console.error(`--into must stay inside the workspace; "${raw}" resolves outside it.`);
    process.exit(1);
  }

  return { repoDir, repoPathPosix };
}

// ---------------------------------------------------------------------------
// west.yml append helper
// ---------------------------------------------------------------------------

/**
 * Render a project block as an array of lines, at the given list indentation.
 *
 * The block carries name, path, description and userdata.role only. The remote
 * and the revision come from the manifest's `defaults:` block, so repeating
 * them per project would be redundant and would drift from the manifest style.
 */
function projectBlockLines({ name, path: repoPath, description, role, protected: isProtected }, itemIndent) {
  const item = ' '.repeat(itemIndent);       // indentation of the `- name:` line
  const prop = ' '.repeat(itemIndent + 2);   // indentation of its properties
  const lines = [
    `${item}- name: ${name}`,
    `${prop}path: ${repoPath}`,
    `${prop}description: "${description}"`,
    `${prop}userdata:`,
    `${prop}  role: ${role}`,
  ];
  if (isProtected) lines.push(`${prop}  protected: true`);
  return lines;
}

/** Indentation width of a line, or null for a blank line or a full-line comment. */
function structuralIndent(line) {
  if (!line.trim()) return null;
  const indent = line.match(/^[ ]*/)[0].length;
  if (line.trim().startsWith('#')) return null;
  return indent;
}

/**
 * Refuse to edit west.yml, printing the block for the user to place by hand.
 * A refusal the user can act on beats a silently broken manifest.
 */
function refuseWestYmlEdit(project, reason) {
  console.error(`\nCould not place the project block in ${WEST_YML}:`);
  console.error(`  ${reason}`);
  console.error('\nwest.yml was left untouched. Add this block to the `projects:` list by hand:\n');
  for (const line of projectBlockLines(project, 4)) console.error(line);
  console.error('');
  process.exit(1);
}

/**
 * Insert a project block into west.yml's `projects:` list.
 *
 * Appending at end of file is wrong: the moment any top-level key or trailing
 * content follows `projects:`, the block lands outside the list and the
 * manifest breaks. So the list is located, the last line belonging to it is
 * found, and the block is inserted there, leaving whatever follows intact.
 *
 * The indentation is taken from the existing entries rather than assumed, so
 * the appended block matches the file's own style. When the structure cannot
 * be recognised with confidence, nothing is guessed and nothing is written.
 */
function appendToWestYml(project) {
  const src       = readFileSync(WEST_YML, 'utf8');
  const newline   = src.includes('\r\n') ? '\r\n' : '\n';
  const lines     = src.split(/\r?\n/);

  // Locate the `projects:` key. More than one means an ambiguous manifest
  // (imports, multiple documents), which is not something to guess at.
  const keyIdxs = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^[ ]*projects:[ \t]*$/.test(lines[i])) keyIdxs.push(i);
  }
  if (keyIdxs.length === 0) refuseWestYmlEdit(project, 'no `projects:` list was found.');
  if (keyIdxs.length > 1)   refuseWestYmlEdit(project, `${keyIdxs.length} \`projects:\` keys were found, so the target is ambiguous.`);

  const keyIdx    = keyIdxs[0];
  const keyIndent = structuralIndent(lines[keyIdx]);

  // Scan forward for the last line belonging to the list. The list ends at the
  // first structural line indented no further than the `projects:` key itself.
  let lastIdx    = -1;
  let itemIndent = null;
  for (let i = keyIdx + 1; i < lines.length; i++) {
    const indent = structuralIndent(lines[i]);
    if (indent === null) continue;          // blank line or comment: may sit inside the list
    if (indent <= keyIndent) break;         // back out to the parent level: the list has ended
    lastIdx = i;
    if (itemIndent === null && /^[ ]*-[ ]/.test(lines[i])) itemIndent = indent;
  }

  if (lastIdx === -1)    refuseWestYmlEdit(project, 'the `projects:` list is empty, so its style cannot be inferred.');
  if (itemIndent === null) refuseWestYmlEdit(project, 'the `projects:` list has no recognisable `- name:` entry.');

  const block = ['', ...projectBlockLines(project, itemIndent)];
  lines.splice(lastIdx + 1, 0, ...block);

  writeFileSync(WEST_YML, lines.join(newline), 'utf8');
  console.log(`  added project "${project.name}" to west.yml`);
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

const [,, cmd = 'help', ...rest] = process.argv;

switch (cmd) {
  case 'help':     cmdHelp();          break;
  case 'doctor':   cmdDoctor();        break;
  case 'update':   cmdUpdate();        break;
  case 'push':     cmdPush();          break;
  case 'status':   cmdStatus();        break;
  case 'new-repo': cmdNewRepo(rest);   break;
  case 'protect':  cmdProtect(rest);   break;
  default:
    console.error(`Unknown command: ${cmd}`);
    console.error('Run `node manage.mjs help` for usage.');
    cmdHelp();
    process.exit(1);
}
