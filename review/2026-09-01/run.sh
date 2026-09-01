#!/bin/sh
# Incha review — one-shot verification runner (read-only).
#
#   sh run.sh              # from wherever this folder lives (.review/ or review/<date>/)
#   sh run.sh --git        # also inspect git history
#
# Optional syntax pass: it needs Node + luaparse (ESO grammar is Lua 5.1):
#   npm install --prefix /tmp/luaparse luaparse
# or set NODE_PATH to an existing luaparse install.  Without it the pass is
# skipped and reported as NOTE; every other check is pure stdlib Python.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)

# Locate the repository root by walking up: this folder is .review/ in a working
# copy and review/<date>/ once the package is committed, so "parent of the
# script" is not a reliable answer.
REPO=$HERE
while [ "$REPO" != "/" ] && [ ! -f "$REPO/incha.txt" ]; do
    REPO=$(dirname "$REPO")
done
if [ ! -f "$REPO/incha.txt" ]; then
    echo "could not locate the repository root (no incha.txt above $HERE)" >&2
    exit 2
fi

: "${NODE_PATH:=/tmp/luaparse/node_modules}"
export NODE_PATH

if ! command -v node >/dev/null 2>&1 || ! node -e "require('luaparse')" >/dev/null 2>&1; then
    echo "note: luaparse unavailable; C-13 will be skipped (see header of this script)"
fi

cd "$REPO"
exec python3 "$HERE/checks.py" --repo . --json "$HERE/findings.json" "$@"
