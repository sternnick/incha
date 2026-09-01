# Handoff — how this package reaches the main developer

Verified against the GitHub API on 2026-09-01 (not inferred):

| Fact | Value | How it was checked |
|---|---|---|
| Working clone remote | `https://github.com/sternnick/incha/` | `git remote -v` in `/tmp/incha` |
| `sternnick/incha` | **fork** of `oseias-pt/incha`, default branch `master`, public | `GET /repos/sternnick/incha` → `"fork": true`, `parent.full_name` |
| Our permissions on the fork | `admin: true` (push, branch, PR, merge) | same response, `permissions` |
| Our permissions upstream | `pull: true` only — **no push** | `GET /repos/oseias-pt/incha` |
| Upstream state | `oseias-pt/incha`, default `master`, `has_issues: true`, 6 open issues, not archived | same |
| Open PRs on the fork | 1 — PR #1 `fix/mechanics-review-fixes` → `master`, opened 2026-09-01 | `GET /repos/sternnick/incha/pulls` |
| Branches already used for review work | `feedback/mechanics-review` (carries root `FEEDBACK.md`, 1 commit ahead of `master`, never merged), `review/proposed-fixes` (merged) | `GET /repos/sternnick/incha/branches` + compare |
| `master` protection on the fork | none (404) | `GET /repos/sternnick/incha/branches/master/protection` |
| Branch-name rule | `feature/*` or `fix/*` | `.githooks/pre-push`, installed per `README.md:72` |
| `.review/` | gitignored on purpose — `# Local review reports … to avoid accidental commits` | `.gitignore:18-19` |
| `fix/mechanics-review-fixes` vs `master` | ahead by 1 (`66977e3`), behind 0 | `GET /compare/master...fix/mechanics-review-fixes` |

Consequences, in order of practical importance:

1. **We cannot write to the main developer's repository.** Everything reaches
   Oseias either as a commit on a branch of *our* fork, or as a pull request
   opened against `oseias-pt/incha:master` from our fork.
2. The convention already established in this repository pair is exactly that:
   a review document committed on a `feature`/`feedback` branch, opened as a PR.
   `FEEDBACK.md` on `feedback/mechanics-review` is the previous instance (2026-08-31,
   85 lines, three P1 items). This package supersedes it and says so.
3. `.review/` stays gitignored and untouched. The delivered copy is committed
   under `review/2026-09-01/` on a dedicated branch, so the maintainer's rule
   ("no accidental local reports in the tree") survives and the package is still
   reviewable in the PR UI with diffs and inline comments.
4. Everything suggested in the patches is **unapplied** — the branches in
   `patches/` are `git am` artefacts, not pushes. Merging is the maintainer's call.

---

## 1. Recommended delivery (option A) — review package into our fork

One PR, self-contained, zero risk to `master`, reviewable line by line:

```sh
cd /tmp/incha
git fetch origin
git checkout -b feature/review-package-2026-09-01 origin/master
mkdir -p review/2026-09-01
cp -r .review/{README.md,code-review-2026-09-01.md,AGENT-BRIEF.md,HANDOFF.md,\
boss-inventory.md,checks.py,inventory.py,build-patches.py,verify-patches.py,\
syntax.js,run.sh,findings.json,patch-verification.txt,verification-output.txt} \
  review/2026-09-01/
cp -r .review/patches review/2026-09-01/patches
git add review/2026-09-01 REVIEW-2026-09-01.md
git commit -m "docs(review): full static review of 66977e3, 8 suggested patch branches

Suggestion-only: no tracked file under lib/, core/, ui/, trial/, test/ is
modified by this commit. See review/2026-09-01/README.md for how to re-run the
22 checks and how to apply the patches."
git push -u origin feature/review-package-2026-09-01
```

Then open the PR on `sternnick/incha` with `base = master`. GitHub also accepts a
one-line create URL, which is handy when `gh` is not installed:

```
https://github.com/sternnick/incha/compare/master...feature/review-package-2026-09-01?expand=1
```

## 2. Option B — put it in front of the main developer directly

Same branch, different PR target. Because `oseias-pt/incha` allows pull
requests from forks and we hold `pull` rights, one command does it (`gh`), or
the equivalent REST call, or the compare URL:

```sh
gh pr create --repo oseias-pt/incha --base master \
  --head sternnick:feature/review-package-2026-09-01 \
  --title "Static review of 66977e3 — 26 findings + 8 ready patches (no code touched)" \
  --body-file review/2026-09-01/PR-BODY.md
```

```sh
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -d '{"title":"…","head":"sternnick:feature/review-package-2026-09-01","base":"master","body-file":…}' \
  https://api.github.com/repos/oseias-pt/incha/pulls      # body must be inline JSON
```

```
https://github.com/oseias-pt/incha/compare/master...sternnick:feature/review-package-2026-09-01?expand=1
```

Recommendation: **A first, then B only after the maintainer says so.** A
cross-repository PR notifies the upstream owner and puts a 1 500-line package in
their inbox; `FEEDBACK.md` shows they already receive review material this way,
and PR #1 (the actual fixes) is still unmerged upstream. Let them merge PR #1
first so the review applies to a tree they have accepted.

## 3. Per-finding fix branches (optional, on request)

If the maintainer prefers review-per-PR instead of one package:

```sh
for p in review/2026-09-01/patches/*.patch; do git am -3 "$p"; done   # all eight, in order
# or one at a time:
git checkout -b fix/strip-utf8-bom 66977e3 && git am -3 review/2026-09-01/patches/01-*.patch
git push -u origin fix/strip-utf8-bom
```

**Base verification.** The series was built against the reviewed commit
`66977e3` and then re-verified on a fresh clone of `master` (`af2d477`): all
eight apply in order on both bases with `git am -3`, giving the same 9 commits /
25 files / +379 −49. So PR #1 does not have to merge first — although it should
merge first anyway, because patches 02/03 touch the same functions that PR #1
changed and a reviewer reading a diff against `master` should see PR #1's result.

Each patch is already a separate branch name inside the patch header, so
`git checkout -b <name> 66977e3 && git am -3 <patch>` reproduces the intended PR
branch exactly. Order and risk are in § 4 of the review; patch 07 (CI) goes last.

## 4. Relationship to `FEEDBACK.md` (branch `feedback/mechanics-review`)

| `FEEDBACK.md` item | Status in this package |
|---|---|
| #1 `hideAction()` stale cache | **F-08** — same conclusion, now with the reproduction path (`Trial.lua:186-192` + `hideActionWhenNoRule`) and a patch (`02`) |
| #2 replay loop never drives the 200 ms callbacks | **F-14** — same, plus the missing `zo_callLater` firing and the absence of any CI |
| #3 `GetPlayerRoles` not stubbed | **already resolved** — the stub is present at `test/harness/eso_api.lua:125`; the remaining open question is the *return order*, which is F-11-adjacent and has a probe (`/script local a,b,c,d = GetPlayerRoles() d(a,b,c,d)`) |

Three notes in `FEEDBACK.md` are also worth flagging so the maintainer is not
chased for something already fixed: the `OseinCageCommon.lua` filename in item 3
is spelled `OsseinCageCommon.lua`, and its P1 item 1 quotes `ui/Panel.lua` line
numbers from before `66977e3`.

## 5. What we deliberately did **not** do

* No change to any tracked source file, no reformatting, no dependency change.
* No commit to `master`, no force-push, no branch deletion, no `--no-verify`.
* No edit of `.gitignore` (the `.review/` rule is theirs).
* No upstream PR, no issue, no mention of anyone in GitHub — that is a call for
  the fork owner, and the command is in § 2.
* No invented constants. Zone IDs, unit names, world coordinates, HP pools and
  ability IDs are only ever quoted from this repository, or marked UNVERIFIED
  with a probe.
