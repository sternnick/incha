#!/bin/sh
# test/checks/per-run-artifacts.sh  -  no per-run report file may be tracked.
#
# DAILY_REPORT.md and FORK_COORDINATION.md are notes a scheduled run writes for
# itself and overwrites next run. .gitignore already names DAILY_REPORT.md with
# the reason - "must not pollute feature branches" - but an ignore rule stops an
# untracked file, never a tracked one: commit it once (git add -f, or an editor
# that adds what it just wrote) and the ignore silently stops applying to it.
#
# Tracking them is not cosmetic, it is what jams the queue. Two branches that
# each ADD the same path conflict add/add on merge no matter what else they
# contain, so N such branches produce N*(N-1)/2 collision pairs and the PR queue
# cannot drain in any order without manual conflict resolution on files whose
# content is a timestamped log. Seven branches here do exactly that.
#
# Usage (from the repository root):
#   sh test/checks/per-run-artifacts.sh
#
# Exit code 0 = the tree tracks neither file, 1 = at least one is tracked.

set -u

paths="DAILY_REPORT.md FORK_COORDINATION.md"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "per-run-artifacts: not a git repository, cannot inspect the index"
    exit 1
fi

tracked="$(git ls-files -- $paths)"

if [ -n "$tracked" ]; then
    echo "per-run-artifacts: per-run report file(s) are tracked:"
    printf '%s\n' "$tracked" | sed 's/^/     /'
    echo "   They are per-run notes, not source. Remove them from this branch:"
    echo "     git rm --cached DAILY_REPORT.md FORK_COORDINATION.md"
    echo "   and leave them untracked - .gitignore already covers both."
    echo "   Why this is a gate and not a preference: any two branches that each"
    echo "   add one of these paths collide add/add on merge, which is how the PR"
    echo "   queue gets stuck on files that carry no decisions."
    exit 1
fi

echo "per-run-artifacts: ok (no per-run report file tracked)"
