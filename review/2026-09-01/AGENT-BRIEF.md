# Agent Brief — working the Incha review queue

**Audience:** whoever (human or AI assistant) picks up the findings in
`code-review-2026-09-01.md`. It is written for an assistant with repository
access and no prior context, because that is the case where unverified claims
cost the most.

---

## 0. The one rule

**Verify before you assert, and say which kind of statement you are making.**

* **CONFIRMED** — reproducible from this checkout with a command. Quote
  `file:line`, run the command, paste the output.
* **UNVERIFIED** — needs one ESO session or authoritative API documentation.
  Write it as a question with a probe, never as a fact.

About half of the value of this review is the negative results: F-25 and the
`zo_callLater` part of F-26 look like defects by shape and are not. § 2 of the
review exists so that nobody "fixes" working code. If you find yourself
changing something listed there, stop and re-read the finding.

---

## 1. Ground rules for this repository

| Rule | Source |
|---|---|
| Never commit to `master`; open a PR | `README.md`, branch protection |
| Branch names must be `feature/*` or `fix/*` | `.githooks/pre-push` (installed via `git config core.hooksPath .githooks`, `README.md:72`) |
| One writer per working tree; reviewers and validators are read-only | orchestration policy |
| Lua 5.1 semantics, no new globals, no new dependencies | `bootstrap.lua` (ESO provides no `require`, no file I/O) |
| Anything in `OptionalDependsOn` must stay optional | `incha.txt:7`, `README.md` |
| Do not reformat or rename beyond the change under work | review etiquette; the tree is consistent (no CRLF, no tabs) |
| Add the `## Version:` bump in `incha.txt` when user-visible behaviour changes | `incha.txt:3` |

Manifest discipline is load-bearing: ESO loads files in `incha.txt` order and
`bootstrap.lua:29-33` raises `require(...) module not registered` for anything
listed later. If a patch adds a `require`, the manifest order must be fixed in
the same commit — patch `05` shows the pattern, and `checks.py` C-03 enforces it.

## 2. Commands you should run, in this order

```sh
sh .review/run.sh --git                      # everything, human-readable
python3 .review/checks.py --repo . --json /tmp/f.json   # 22 checks, exit 1 on FAIL
python3 .review/inventory.py . > /tmp/inv.md # per-boss inventory
NODE_PATH=... node .review/syntax.js         # luaparse pass (optional but cheap)
```

Baseline at `66977e3`: **6 PASS · 6 WARN · 4 FAIL · 5 NOTE**.
After the whole patch series: **11 PASS · 5 WARN · 1 FAIL · 4 NOTE**, where the
remaining FAIL is the `showBossUI` decision (§ 4 of the review) and the WARNs
are the ones that need an in-game session. If your run disagrees with this
document, **the script is right and the document is stale** — say so instead of
editing the document to match your run.

## 3. The queue

### 3a. Already drafted as patches (`patches/`, `git am`-clean against `66977e3`)

Apply in this order; the numbers are the merge order, not priorities.

| # | Branch | Findings | What "done" means |
|---|---|---|---|
| 01 | `fix/strip-utf8-bom` | F-01 | `checks.py` C-01 and C-13 both PASS |
| 02 | `fix/panel-cache-and-control-name` | F-08, F-10 | C-15 PASS, C-14 PASS |
| 03 | `fix/boss-slot-and-alert-hygiene` | F-02, F-03, F-07 | C-05 still PASS; replay the KA and LC logs; confirm `context.bossUnitTag` is never used before it is set |
| 04 | `fix/hardmode-measurement-aid` | F-04, F-22 | C-18 still WARN (by design); the chat line and `/incha hp` must work without LAM installed |
| 05 | `feature/live-trial-enable` | F-09, F-24 | C-03 PASS after the manifest reorder; toggling a trial mid-zone visibly enables/disables the overlay |
| 06 | `fix/single-version-source` | F-17 | C-10 PASS |
| 07 | `feature/ci-static-validation` | F-01, F-14 | `python3 tools/static_checks.py` exits 0 **on the merged tree**; merge last |
| 08 | `fix/docs-drift-corrections` | F-16 | C-11 assertions PASS or are updated in the same commit |

Re-generate and re-verify the series rather than hand-editing a `.patch`:

```sh
python3 .review/build-patches.py --work /tmp/incha-work --out .review/patches
python3 .review/verify-patches.py  --repo . --work /tmp/incha-verify
```

`build-patches.py` fails loudly if upstream moved a line — that is intentional;
fix the anchor in the builder, not the patch by hand.

### 3b. Findings with no patch, on purpose

| Finding | Why no patch | What to do instead |
|---|---|---|
| **F-06** `showBossUI` unread in all nine trials | Product decision: wire the header or delete nine checkboxes | Ask. Do not pick one silently. |
| **F-22 / F-04** 16 unusable HM thresholds, 42 dependent gates | The numbers only exist inside the game | Run the `/incha hp` probe once per boss, write the measured values, then re-run C-07/C-18 |
| **F-05** three proximity constants | `lib/MapUtils` switched to world units; the right values are empirical | Measure standing next to a group member, record `GetUnitWorldPosition` distance |
| **F-12** Falgravn AABB vs. its own OSI node tables | Needs corner coordinates | Walk the room corners, log `GetUnitWorldPosition("player")` |
| **F-13** five trials detect bosses by localised name | Needs unit names per client language | Log `GetUnitName("boss1")` per locale, then add unit-tag matching |
| **F-11** `EVENT_COMBAT_EVENT` argument list | No authoritative docs reachable from the review environment | Run the probe in § 6C.2 of the review and paste the dump |
| **F-21** 16 unrouted ability IDs | Routing them is game-design work, not a fix | Either implement per the ROADMAP phase, or move the constants into the ROADMAP and delete them |
| **F-23** unused locals | Mixed bag | Wire the seven `*_FIRST_CD` values; use-or-delete the seven redundant ID sets; drop the dead colour palettes |
| **F-15, F-19, F-20** history/unload/TODO hygiene | Process, not code | One issue each |

### 3c. In-game probe set (one session, ~2 h, unblocks most of 3b)

```
/incha hp                          # after patch 04: name + max + effectiveMax per boss slot
/script d(GetZoneId(GetUnitZoneIndex("player")))         # zone IDs (not GetCurrentMapZoneIndex)
/script local a,b,c,d=GetPlayerRoles() d(a,b,c,d)        # role order used by 7 call sites
/script d(GetUnitName("boss1"), GetUnitName("boss2"))    # F-13, per client language
```

Plus the snippets inside F-05, F-11 and F-12 of the review.

## 4. Reporting format

For every change you make:

```
finding: F-xx (CONFIRMED | UNVERIFIED)
file:line before -> after, with one sentence of why
command run: exact command + exit code + the decisive line of output
still unverified: what you could not check here, and the probe that would close it
```

For every finding you *reject*: name the check or the line that contradicts it.
"Looks fine" is not a result. If a reviewer (human or model) asserts something
about this codebase without a `file:line` and a command, treat it as a question,
not a finding.

## 5. Known limits of this package

* No ESO client here: nothing in `§ 3c` can be settled offline. Do not fabricate
  zone IDs, ability IDs, unit names, world coordinates or HP pools. An invented
  ability ID is worse than a missing one, because it routes silently to nothing.
* `test/run_log.lua` needs a Lua interpreter; the harness stubs `zo_callLater`
  as a no-op (F-14), so anything time-deferred is invisible to it. Do not read a
  green harness run as proof of behaviour.
* `luaparse` accepts a BOM; only the byte-level check catches F-01.
* The live signatures of `EVENT_COMBAT_EVENT` / `EVENT_EFFECT_CHANGED` were not
  reachable from this environment (F-11).
