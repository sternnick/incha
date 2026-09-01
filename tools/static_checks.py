#!/usr/bin/env python3
"""Static validation for the Incha addon (stdlib only, no network).

  python3 tools/static_checks.py            # exit 1 on any failure

Checks, in the order a failure would bite a player:
  1. encoding   - no UTF-8 BOM, no CRLF, no mojibake in any shipped file
  2. manifest   - every .lua on disk is listed in incha.txt exactly once
  3. load order - every require() target appears before its consumer
  4. naming     - created global controls start with the addon name
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXT_SUFFIXES = (".lua", ".txt", ".md")
FAILURES = []


def rel_paths():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".github", "node_modules")]
        for name in sorted(files):
            if name.endswith(TEXT_SUFFIXES):
                yield os.path.relpath(os.path.join(base, name), ROOT)


def read_bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        return fh.read()


def fail(check, msg):
    FAILURES.append("%s: %s" % (check, msg))


def check_encoding():
    for rel in rel_paths():
        raw = read_bytes(rel)
        if raw.startswith(b"\xef\xbb\xbf"):
            fail("encoding", "%s starts with a UTF-8 BOM (3 bytes at offset 0)" % rel)
        if b"\r\n" in raw:
            fail("encoding", "%s contains CRLF line endings" % rel)
        if b"\xef\xbf\xbd" in raw or b"\xc3\xa2\xc2\x80" in raw:
            fail("encoding", "%s contains mojibake / replacement chars" % rel)


def manifest_files():
    with open(os.path.join(ROOT, "incha.txt"), encoding="utf-8") as fh:
        return [ln.strip() for ln in fh
                if ln.strip().endswith(".lua") and not ln.startswith("##")]


def check_manifest():
    listed = manifest_files()
    on_disk = sorted(p.replace(os.sep, "/") for p in rel_paths()
                     if p.endswith(".lua") and not p.startswith("test" + os.sep))
    missing = sorted(set(on_disk) - set(listed))
    ghost = sorted(set(listed) - set(on_disk))
    dupes = sorted({p for p in listed if listed.count(p) > 1})
    for m in missing:
        fail("manifest", "%s exists on disk but is not in incha.txt (never loaded)" % m)
    for g in ghost:
        fail("manifest", "incha.txt lists %s which does not exist" % g)
    for d in dupes:
        fail("manifest", "%s is listed more than once" % d)


def check_load_order():
    order = {p: i for i, p in enumerate(manifest_files())}
    bad = []
    for rel, idx in order.items():
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for target in re.findall(r'require\("([^"]+)"\)', src):
            t = target + ".lua"
            if t in order and order[t] > idx:
                bad.append("%s (line %d of manifest) requires %s listed later"
                           % (rel, idx + 1, target))
    for b in sorted(set(bad)):
        fail("load order", b)


def check_control_names():
    for rel in rel_paths():
        if not rel.endswith(".lua"):
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for m in re.finditer(r'CreateControl\(\s*"([^"]+)"', src):
            name = m.group(1)
            if not name.lower().startswith("incha"):
                line = src[:m.start()].count("\n") + 1
                fail("naming", '%s:%d creates global control "%s" '
                     '(must start with the addon name)' % (rel, line, name))


def main():
    check_encoding()
    check_manifest()
    check_load_order()
    check_control_names()
    for f in FAILURES:
        print("FAIL " + f)
    print("%s: %d failure(s)" % ("FAILED" if FAILURES else "OK", len(FAILURES)))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
