# Loom Foundation Workspace

The workspace is `west`-managed set of independent repositories (a repository of repositories).

## Common tasks

Run these from this directory (the workspace root).
Use `./manage.sh` on macOS and Linux, `.\manage.cmd` on Windows:

```sh
./manage.sh update                     # refresh every repository from GitHub
./manage.sh status                     # list the repositories and their state
./manage.sh push                       # push every repository with local commits
./manage.sh new-repo <name> "<desc>"   # scaffold a new repository (add --into <dir> to place it)
./manage.sh help                       # all commands
```

`manage` is a convenience wrapper over `west`; `west` still works directly if you prefer it.
