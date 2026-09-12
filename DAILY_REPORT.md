# DAILY_REPORT — 2026-09-12 (agent 3345c1b3543d)

## Selected task
Priority 1 (make the test system smarter) — the 'Replay logs' step was
measured to dispatch ZERO alerts on every fixture while exiting 0, on BOTH
master and the active line. Fixed the root cause in the harness rather
than adding new capability, because every other metric (per-ability
coverage in particular) is built on this path and currently proves
nothing. Chosen over the LC-common registration gap (see Next task)
because the gap is comment-material on the rewrite discussion while this
is a self-contained defect with a full offline proof.

## Classification
`CONFIRMED` — defect proven by reproduction, and a 2-line fix flips the
measured outcome (alerts 0 → 14 on ka, 0 → 4 on ss).

## Evidence
- Repro on active-line tip 431b9d9: `luajit test/run_log.lua
  test/fixtures/ka.log` → `Bosses activated: 3, Alerts fired: 0,
  Handler errors: 0`, rc=0. Same for every fixture.
- Repro on master tip acd3f73: same numbers — the blindness is not
  introduced by Phase 4, it is latent on both trees: CombatHandler
  (master) and EventDispatcher (active) both resolve the boss via
  `trial:getActiveBoss()` == `trial.activeBosses[1]` (core/Trial.lua),
  while run_log.lua's injectBoss() populates only `trial.activeBoss`.
  `activeBosses` appears ZERO times in test/run_log.lua on both tips.
- Measured before/after on master (this branch): ka 0→14 alerts,
  ss 0→4 alerts, all 9 fixtures rc=0, zero handler errors.
- Measured before/after on the active line (2-line patch, throwaway
  worktree): ka 0→14 (rc=1 until the Falgravn swap below), ss 0→4 rc=0.
- The IsUnitValid call: no API source reachable from here documents it
  (esodecoded: 404 for IsUnitValid vs DoesUnitExist(string unitTag)
  present; its full Is*/Does* index lists no IsUnitValid; UESP opensearch
  zero hits; 0 occurrences across all six mirrored reference addons,
  which all use DoesUnitExist; incha itself uses DoesUnitExist for unit
  existence at core/Trial.lua:150). test/checks/globals.lua allows any
  `Is<Upper>` name as "ESO API", so the static check cannot catch this
  class. The official ESOUI wiki was unreachable (403) — see Uncertainties.

## Changes
- `test/run_log.lua` — injectBoss() now sets `trial.activeBosses =
  { instance }` (and clearBoss() clears it) so `getActiveBoss()` resolves.
  The bug is identical on both current trees and the fix hunks are
  identical; the branch is based on master because the active line
  contains `.github/workflows/close-linked-issues.yml`, which this fork
  has never contained and which a PAT without `workflow` scope cannot
  introduce (measured: push onto an edm base = "remote rejected ...
  refusing to allow a Personal Access Token to create or update workflow
  without workflow scope"). Delivering the same fix against the active
  line is staged for after #265 merges to master, or with a
  workflow-scoped token.
- `trial/ka/boss/Falgravn.lua` — the LN-DEBUG conduit probe calls
  `DoesUnitExist` (the documented API) instead of the never-documented
  `IsUnitValid`. Same line the file already marks "remove after LN/LS/RN/
  RS identification". On the active-line tree this swap is load-bearing
  for green CI (dispatched replay throws "attempt to call global
  'IsUnitValid'" at ka.log 11300ms and run_log exits 1 on handler
  errors); on master the probe body never executes in replay (measured:
  ka.log processes 5 EFFECT_CHANGED entries with 0 errors there, because
  the legacy table-shape entry strips changeType and the fn's
  `changeType ~= EFFECT_RESULT_GAINED` guard sees abilityId=133433 and
  returns early), so on master the swap is correctness-only.

## Tests
- `sh test/checks/all.sh` → all 11 checks passed (incl. branch-name).
- `luacheck .` → 0 warnings / 0 errors in 83 files.
- `luajit test/run_log.lua test/fixtures/*.log` → all 9 fixtures rc=0;
  ka alerts=14 errors=0, ss alerts=4 errors=0, others 0/0 (zone-only
  fixtures by design). Before this branch: every fixture alerts=0.

## Uncertainties
- Whether `IsUnitValid` exists in the live client could not be settled
  from here (official ESOUI wiki 403 on both reachable hosts). The swap
  to `DoesUnitExist` is the safe side of that uncertainty (documented +
  already used by this repo) and sits in a debug probe, but in-game
  behavior of the old call, if it ever existed, is UNVERIFIED.
- The 7 zone-only fixtures have no boss-activation events, so alerts=0
  there is expected, not proof; ka/ss are the two with events.
- The dev's own CI shows `static checks: success` on 431b9d9 while our
  replay of the same tree proves 0 alerts dispatched — 'Replay logs'
  exits 0 on the alert-zero path, so CI cannot see this class at all.
  This PR turns that step into a real gate without changing CI files.

## Manual verification required
None for the harness fix (fully proven offline). One optional line for
the dev, alongside the LN/LS/RN/RS clear that handleLinkEffect exists
for:
  Trial: KA / Boss: Falgravn / Needed: none new — while the LN-DEBUG
  probe prints, confirm `valid=` still reads true/false as before after
  the DoesUnitExist swap (one conduit spawn settles it).

## Recommended next task
LC registration gap on the active line (classification CONFIRMED-defect,
delivery = comment on #264, not a branch): EventDispatcher registers ids
solely from `boss.events` via `abilityIdsFor` (core/EventDispatcher.lua:302);
no boss sets `.common` on the active line (grep = 0) and none of the five
LC bosses merges `LCCommon.beginCastEntries/effectChangedEntries` the way
OC/SS/RG/DSR merge their common entries — 222475 (SOLAR_FLARE), 165972
(HINDERED), 214675 (RADIANCE) are registered by nobody on LC. Include the
KazpianEncounter.lua:174 merge-loop pattern as the fix sketch.
