## What this is

A full static review of `66977e3` — 26 findings, 22 reproducible checks, and 8
`git am`-clean patch branches. **Suggestion-only: no file under `lib/`, `core/`,
`ui/`, `trial/` or `test/` is touched by this PR, and `.gitignore` is unchanged.**

* Start here: `REVIEW-2026-09-01.md` (repo root, 1 screen)
* Detail: `review/2026-09-01/code-review-2026-09-01.md`
* Patches: `review/2026-09-01/patches/` (order and risk in § 4)
* Operating brief for whoever works the queue: `review/2026-09-01/AGENT-BRIEF.md`
* Delivery/branch mechanics for this fork pair: `review/2026-09-01/HANDOFF.md`

## Numbers

| | |
|---|---|
| Checks at `66977e3` | 6 PASS · 6 WARN · 4 FAIL · 5 NOTE (exit 1) |
| Checks with all 8 patches | 11 PASS · 5 WARN · 1 FAIL · 4 NOTE |
| Remaining FAIL | `showBossUI` unread — a product decision, see F-06 |
| Patch series | 8 patches / 9 commits / 25 files / +379 −49, applies in order, all files parse |

## The three items that need your input, not a patch

1. **F-06** `showBossUI` — nine checkboxes, zero readers. Wire the header or delete the setting?
2. **F-04 / F-22** HM thresholds — 16 of 25 bosses unusable, 42 `isHM` gates depend on them. Patch `04` adds `/incha hp` so one session can settle it.
3. **F-11** `EVENT_COMBAT_EVENT` argument order — a 2-minute in-game probe decides whether `core/CombatHandler.lua:10-18` is current.

## Reproduce

```sh
sh review/2026-09-01/run.sh --git
python3 review/2026-09-01/checks.py --repo . --json /tmp/f.json
python3 review/2026-09-01/verify-patches.py --repo . --work /tmp/verify
```

Supersedes `FEEDBACK.md` on `feedback/mechanics-review` (its item 3 is already
resolved — the `GetPlayerRoles` stub is at `test/harness/eso_api.lua:125`).
