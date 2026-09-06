#!/bin/sh
# test/checks/all.sh  -  run every static check and report them all.
#
# Runs each check even when an earlier one fails, so one run tells you
# everything that is wrong rather than one thing per round-trip. This mirrors
# what CI does (.github/workflows/checks.yml runs the same scripts as separate
# steps, each with `if: !cancelled()`), so a clean run here means a green
# pipeline.
#
# Usage (from the repository root):
#   sh test/checks/all.sh
#
# Exit code 0 = every check passed, 1 = at least one failed.

set -u

failed=""
passed=0

run() {
    name="$1"; shift
    if out=$("$@" 2>&1); then
        printf '  ok    %-16s %s\n' "$name" "$(printf '%s' "$out" | tail -1)"
        passed=$((passed + 1))
    else
        printf '  FAIL  %-16s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/          /'
        failed="$failed $name"
    fi
}

echo "static checks"
echo

run branch-name    sh     test/checks/branch-name.sh
run syntax         sh     test/checks/syntax.sh
run encoding       sh     test/checks/encoding.sh
run globals        luajit test/checks/globals.lua
run manifest       luajit test/checks/manifest.lua
run load-order     luajit test/checks/load-order.lua
run lang           luajit test/checks/lang.lua
run contracts      luajit test/checks/contracts.lua
run filters        luajit test/checks/filters.lua
run settings-usage luajit test/checks/settings-usage.lua
run state-reset    luajit test/checks/state-reset.lua

echo
if [ -z "$failed" ]; then
    echo "all $passed checks passed"
    exit 0
fi

echo "FAILED:$failed"
exit 1
