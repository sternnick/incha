# Review package — 2026-09-01 (`66977e3`)

Automated + manual static review of the Incha trial-mechanics overlay. **Read-only
output**: nothing under `lib/`, `core/`, `ui/`, `trial/` or `test/` is modified, no
`.gitignore` rule was touched, and every suggested change is delivered as an
unapplied patch under `patches/`.

Two layouts are supported deliberately:

* a **working copy**, where this folder is `.review/` (gitignored — that is the
  repository's own rule at `.gitignore:18-19`);
* the **committed package**, where it is `review/2026-09-01/` on a review branch.

The scripts locate the repository root by walking up from their own location and
locate each other by filename, so both layouts behave identically.

## Where to start

| If you are | Read |
|---|---|
| the maintainer, 2 minutes | `../../REVIEW-2026-09-01.md` (repo root) |
| the maintainer, in earnest | `code-review-2026-09-01.md` — 26 findings, each with `file:line` evidence, impact, a suggested change, and a way to verify |
| the assistant doing the work | `AGENT-BRIEF.md` — ground rules, do-not-touch list, per-patch definition of done, probe set |
| deciding how this reaches the main developer | `HANDOFF.md` — verified fork/PR mechanics for `sternnick/incha` → `oseias-pt/incha` |

## Contents

| File | What it is |
|---|---|
| `code-review-2026-09-01.md` | the review (§ 1 method, § 2 verified-solid, § 3 findings F-01…F-26, § 4 work order, § 5 drafted CI, § 6 appendix) |
| `REVIEW-2026-09-01.md` (repo root) | one-screen cover note |
| `AGENT-BRIEF.md` | operating brief for whoever works the queue, human or model |
| `HANDOFF.md` | repository topology, delivery options, exact commands |
| `PR-BODY.md` | ready-to-paste pull-request description |
| `boss-inventory.md` | generated per-boss table: detection rule, HM threshold, schema fields, route counts, info slots, lifecycle hooks |
| `checks.py` | the 22 mechanical checks behind every CONFIRMED claim; stdlib-only; exit 1 on FAIL |
| `inventory.py` | regenerates `boss-inventory.md` |
| `syntax.js` | optional Lua 5.1 grammar pass via `luaparse` |
| `run.sh` | one-shot runner |
| `build-patches.py` | regenerates `patches/` from `66977e3`; every edit is an assertion-guarded exact replacement, so an upstream line move fails the build instead of guessing |
| `verify-patches.py` | per-patch and whole-series verification (apply-check, `git am`, luaparse, static checks) |
| `patches/*.patch` | 8 suggested fixes, 9 commits, `git am`-clean against `66977e3` |
| `findings.json` | machine-readable check results |
| `verification-output.txt` | the run that produced the finding numbers quoted in the review |
| `patch-verification.txt` | the verification run for the patch series |

## Reproduce

```sh
sh run.sh --git                                   # everything, read-only
python3 checks.py --repo . --json findings.json   # exit 1 while F-01/F-06/F-08 are open
python3 "$(pwd)/inventory.py" "$(git rev-parse --show-toplevel)" > /tmp/boss-inventory.md
```

Optional syntax pass (otherwise C-13 reports NOTE and skips):

```sh
npm install --prefix /tmp/luaparse luaparse
NODE_PATH=/tmp/luaparse/node_modules sh run.sh
```

## Status at hand-off

| Tree | Result |
|---|---|
| `66977e3` as reviewed | **6 PASS · 6 WARN · 4 FAIL · 5 NOTE** (exit 1) |
| `66977e3` + all 8 patches | **11 PASS · 5 WARN · 1 FAIL · 4 NOTE** |

The four FAILs in the reviewed tree are the BOM set (F-01), its syntax
consequence (C-13), `showBossUI` unread (F-06) and the `hideAction` cache (F-08).
After the series, the single remaining FAIL is `showBossUI`, which is a product
decision rather than a defect — see § 4 of the review.
