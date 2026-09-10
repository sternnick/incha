#!/bin/sh
# test/checks/encoding.sh  -  file encoding hygiene.
#
# A UTF-8 BOM is three bytes before the first line of source. Lua tolerates it,
# which is exactly why it survives: nothing complains, but it shows up as a
# spurious first-line diff, breaks `head -1` style tooling, and makes the file
# look different from its neighbours for no reason.
#
# This repository previously recorded these as removed while nine files still
# carried them, so the check exists to keep the claim and the tree in step.
#
# Usage (from the repository root):
#   sh test/checks/encoding.sh
#
# Exit code 0 = clean, 1 = at least one finding.

set -u

findings=0
count=0

for f in $(find . \( -name '*.lua' -o -name '*.txt' -o -name '*.md' -o -name '*.sh' \) \
             -not -path './.git/*' -not -path './.claude/*' -not -path './.review/*' | sort); do
    count=$((count + 1))

    if head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf'; then
        echo "BOM     $f"
        findings=$((findings + 1))
    fi
done

if [ "$findings" -eq 0 ]; then
    echo "encoding: clean ($count files)"
else
    echo "encoding: $findings file(s) with a UTF-8 BOM"
fi

[ "$findings" -eq 0 ]
