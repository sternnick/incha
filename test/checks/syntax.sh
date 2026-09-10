#!/bin/sh
# test/checks/syntax.sh  -  compile every Lua file in the addon.
#
# ESO reports a syntax error by silently refusing to load the addon, so a
# stray typo can ship without anyone noticing until a player enables it.
# LuaJIT's bytecode compiler is the cheapest possible gate: no game client,
# no log file, no ESO knowledge.
#
# Usage (from the repository root):
#   sh test/checks/syntax.sh
#
# Exit code 0 = every file compiles, 1 = at least one does not.

set -u

findings=0
count=0

for f in $(find . -name '*.lua' -not -path './.git/*' -not -path './.claude/*' -not -path './.review/*' | sort); do
    count=$((count + 1))
    if ! out=$(luajit -bl "$f" 2>&1 >/dev/null); then
        echo "SYNTAX  $f"
        echo "        $out"
        findings=$((findings + 1))
    fi
done

if [ "$findings" -eq 0 ]; then
    echo "syntax: clean ($count files)"
else
    echo "syntax: $findings file(s) failed to compile"
fi

[ "$findings" -eq 0 ]
