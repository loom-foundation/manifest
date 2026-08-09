#!/bin/sh
# manage.sh: POSIX launcher for the Loom Foundation workspace management CLI.
#
# Bootstrap symlinks this at the workspace root, so you can run e.g.
#   ./manage.sh update
# from the workspace top directory. All the logic lives in manage.mjs; this is
# a thin shim that finds it (resolving symlinks) and hands off to node.

# Resolve this script's real directory, following symlinks.
SOURCE="$0"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;                         # absolute, so use it as it stands
    *)  SOURCE="$DIR/$SOURCE" ;;   # relative, so resolve against the link's dir
  esac
done
DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

exec node "$DIR/manage.mjs" "$@"
