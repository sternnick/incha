# DAILY_REPORT — 2026-09-27 (feature/hm-threshold-dump)

## Selected task
Priority 5 (convert INGAME_VERIFICATION items into precise collection
requests) applied to the largest open evidence gap: the HM health
thresholds. 16 of 25 `hmHealthThreshold` declarations on master `de1dea6`
are sentinels (11x `math.huge`, 5x `100000001`; grep-verified this run).
Priority 1 items already shipped as fork PRs #11–#14; upstream quiet for
a 6th consecutive night (since-filter rc=0, master unchanged).

## Classification
`INGAME_VERIFICATION` → converted into a self-collecting diagnostic per
workflow-code-review.md §4 ("where the addon can collect the value
itself, prefer that").

## Evidence
- `grep hmHealthThreshold trial/` @ de1dea6: 25 declaring files;
  11x math.huge, 5x 100000001 (matches ledger open_findings "HM locked
  NORMAL" + staged 7e(i)/21c).
- `core/BossRegistry.lua:106-121`: `>= threshold` compare → math.huge
  never fires HARDMODE; 100000001 is below vet HM pools → always HARDMODE.
- `core/Trial.lua:340-343` comment: `context.isHM` gates real mechanics
  (Xalvakka jump timer, Taleria behemoth line) — impact is behavioral.
- `core/Trial.lua:296`: difficulty sampler reads
  `GetUnitPower(slot, POWERTYPE_HEALTH)` 3rd return (effectiveMax) —
  the diagnostic mirrors that fallback order.

## Changes
- `ui/Thresholds.lua` (new): `/incha thresholds` — block 1 = declared
  inventory across all 9 trials, each sentinel labelled with its real
  effect; block 2 = live `GetUnitPower` samples for boss1..boss4 of the
  current zone, name-matched via `registry:findByName`, plus a
  paste-ready `-- measured in-game: <trial>.<boss>.hmHealthThreshold = N`
  line. No game data invented — values come from the engine or the
  source declarations.
- `ui/Menu.lua`: `thresholds` sub-command + help line.
- `incha.txt`: manifest entry (manifest.lua enforces load order).
- `test/checks/hm-thresholds.lua` (new) + `all.sh` wiring: frozen
  sentinel baseline. NEW sentinel → CI fail; baseline/value mismatch →
  STALE fail; measured number → FIXED notice.

## Tests
- `sh test/checks/all.sh` → **16/16 rc=0** (new hm-thresholds check green:
  "25 boss files declare hmHealthThreshold (16 listed sentinels, 0 newly
  measured)").
- Negative tests: Bahsei baseline↔source mismatch → rc=1 (STALE);
  Yandir turned into 100000001 → rc=1 (NEW SENTINEL).
- `luacheck .` → **0 warnings / 0 errors / 93 files**.
- Offline smoke of the dump itself (harness tracker injection): inventory
  block correct; live block with a fake 280M Bahsei prints
  `boss1 "Bahsei" hp=.../280000000 ... match: rg/bahsei` + the assignment
  line. Not-in-zone and no-boss paths print guidance, no errors.
- Replays unchanged: ka 14 / ss 4 alerts, 0 handler errors.

## Uncertainties
- In-game formatting of `Log.print` (%q with a runtime string) untested
  on a real client — offline `d()` passthrough only.
- `GetUnitPower` effectiveMax on live HM bosses assumed ≥ max (the reason
  HM pools differ); sample falls back to max when 0, same as Trial.lua:296.
- Bosses detected by LOCATION (KA) whose engine name differs from the
  declared name print "no class matched by name" but still print the
  assignment line with `<boss>` placeholder — the human fills the key.

## Manual verification required
One run per trial with at least one sentinel boss (SS, RG, DSR, AS, CR,
LC, OC cover all 16): stand at any sentinel boss, `/incha thresholds`,
paste the block. Each printed number replaces one sentinel; CI then shows
FIXED and the baseline entry is dropped.

## Recommended next task
Delta watch + PR states (#11–#15). If upstream moves, re-verify open
branch rebases. Staged upstream text 21b–21e stays until writes unblock.
