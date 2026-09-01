#!/usr/bin/env python3
"""Verify the suggested patch series without touching the reviewed checkout.

    python3 .review/verify-patches.py --repo /tmp/incha --work /tmp/incha-verify

Per patch (each on its own pristine clone of the reviewed commit):
  A. `git apply --check`      - does it apply at all
  B. `git am`                 - does it apply as a commit series (commit count)
  C. luaparse over incha.txt  - does every shipped file still parse
  D. tools/static_checks.py   - only once a patch adds it

Then the whole series in order, plus .review/checks.py on the combined tree so
the before/after difference of merging everything is explicit.

Expected, and worth reading before reporting a "FAIL" column:
  * per-patch luaparse shows the 9 BOM files as failures on every tree except
    patch 01's own - that is the pre-existing F-01 defect, not the patch;
  * tools/static_checks.py from patch 07 legitimately reports the violations
    that patches 01/02/05/06 fix, so CI added by patch 07 must merge last.
"""

import argparse
import glob
import json
import os
import subprocess

BASE = "66977e3077bd4d046ca3621fc98c1754e8235651"


def run(args, cwd=None):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def fresh(work, repo):
    run(["rm", "-rf", work])
    code, out = run(["git", "clone", "-q", repo, work])
    if code != 0:
        raise SystemExit("clone failed: " + out)
    run(["git", "-C", work, "checkout", "-f", "-q", BASE])
    run(["git", "-C", work, "clean", "-fdq"])
    run(["git", "-C", work, "config", "user.name", "verify"])
    run(["git", "-C", work, "config", "user.email", "verify@localhost"])
    return work


def syntax(work, here):
    env = dict(os.environ)
    env.setdefault("NODE_PATH", "/tmp/luacheck/node_modules")
    r = subprocess.run(["node", os.path.join(here, "syntax.js")],
                       cwd=work, capture_output=True, text=True, env=env)
    lines = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.strip()]
    return r.returncode, (lines[-1] if lines else "no output")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--work", required=True)
    args = ap.parse_args()
    repo = os.path.abspath(args.repo)
    here = os.path.dirname(os.path.abspath(__file__))
    globals()["HERE"] = here
    patches = sorted(glob.glob(os.path.join(here, "patches", "*.patch")))
    if not patches:
        raise SystemExit("no patches found in patches/ next to this script")

    print("=" * 78)
    print("per patch: apply-check | git am (+commit count) | luaparse | static_checks")
    print("=" * 78)
    report = []
    for p in patches:
        pid = os.path.basename(p)[:2]
        work = fresh(args.work + "-" + pid, repo)
        apply_ok = run(["git", "-C", work, "apply", "--check", p])[0] == 0
        am = run(["git", "-C", work, "am", "-3", p])
        am_ok = am[0] == 0
        n = int(run(["git", "-C", work, "rev-list", "--count", BASE + "..HEAD"])[1] or 0)
        scode, sline = syntax(work, HERE)
        tcode, tout = None, ""
        if os.path.exists(os.path.join(work, "tools", "static_checks.py")):
            tcode, tout = run(["python3", "tools/static_checks.py"], cwd=work)
        print("%-42s apply=%-4s am=%-4s(%d commit%s)  luaparse=%-4s (%s)  static=%s"
              % (os.path.basename(p), "OK" if apply_ok else "FAIL",
                 "OK" if am_ok else "FAIL", n, "s" if n != 1 else "",
                 "OK" if scode == 0 else "FAIL", sline,
                 "n/a" if tcode is None else ("OK" if tcode == 0 else "see note")))
        if not am_ok:
            print("     am error: %s" % am[1].strip().splitlines()[-3:])
        if tcode not in (None, 0):
            print("     static_checks reports pre-existing findings that other "
                  "patches fix:\n       %s"
                  % "\n       ".join(tout.strip().splitlines()[-6:]))
        report.append({"patch": os.path.basename(p), "apply_check": apply_ok,
                       "git_am": am_ok, "commits": n, "luaparse_clean": scode == 0,
                       "luaparse_line": sline,
                       "static_checks": None if tcode is None else tcode == 0})
        run(["rm", "-rf", work])

    print()
    print("=" * 78)
    print("whole series, in numeric order, on one tree")
    print("=" * 78)
    work = fresh(args.work + "-all", repo)
    ok_all = True
    for p in patches:
        code, out = run(["git", "-C", work, "am", "-3", p])
        if code != 0:
            ok_all = False
            print("FAILED at %s:\n%s" % (os.path.basename(p), out.strip()[-600:]))
            run(["git", "-C", work, "am", "--abort"])
            break
    n = int(run(["git", "-C", work, "rev-list", "--count", BASE + "..HEAD"])[1] or 0)
    print("series applied: %s  (%d commits, %d files touched)"
          % ("yes" if ok_all else "NO", n,
             int(run(["git", "-C", work, "diff", "--name-only", BASE, "HEAD"])[1]
                 .strip().count("\n") + 1)))
    print(run(["git", "-C", work, "diff", "--stat", BASE, "HEAD"])[1].strip()[-1200:])

    scode, sline = syntax(work, HERE)
    print("\nluaparse on the combined tree: %s" % sline)
    if os.path.exists(os.path.join(work, "tools", "static_checks.py")):
        tcode, tout = run(["python3", "tools/static_checks.py"], cwd=work)
        print("tools/static_checks.py:    %s" % tout.strip().splitlines()[-1])

    code, out = run(["python3", os.path.join(HERE, "checks.py"),
                     "--repo", work, "--json", "/tmp/verify-findings.json"])
    print("\n.review/checks.py on the combined tree (baseline was 6 PASS / 6 WARN / 4 FAIL / 6 NOTE):")
    for ln in out.splitlines():
        if ln.startswith("[") or ln.startswith("PASS "):
            print("   " + ln)

    out_path = os.path.join(HERE, "patch-verification.txt")
    with open(out_path, "w") as fh:
        fh.write("patch series verification (see verify-patches.py docstring for "
                 "what each column means)\n")
        fh.write("BASE = %s\nseries_applied_in_order = %s\n\n" % (BASE, ok_all))
        fh.write(json.dumps({"per_patch": report}, indent=2) + "\n\n")
        fh.write(out)
    print("\ndetail written to .review/patch-verification.txt")


if __name__ == "__main__":
    main()
