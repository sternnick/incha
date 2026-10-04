# DAILY_REPORT 2026-10-01

## Selected task
KA milestone subtask "Validate logic against reference addons" (#224) —
implementing the first mechanic-grade ref-only gap from the cross-validation
matrix KA row (PR #13 research doc): 132468 Sanguine Prison CAST. Chosen
because: upstream 9th quiet night (0 commits/comments/issues since 09-29),
the SS row is delivered (#17), the LC row is delivered (#16), and an
unattributed Falgravn 132468 edit was discovered dirty in the main
worktree (mtime 2026-09-30 22:39Z, inside the 09-30 run whose execution
record is 'unknown' = died) — the work was sound (ref-backed, correctly
wired) but had never been gated, committed, pushed, or PR'd. This run
finished the delivery.

## Classification
RESEARCH -> implemented; evidence class HYPOTHESIS_REF_ONLY
(single reference Crutch, 0 lines in test/fixtures/ka.log, in-game
verification pending #224).

## Evidence
- CrutchAlerts KynesAegis.lua:103 registers ACTION_RESULT_BEGIN on 132468
  ("PrisonCast" -> OnPrisonBegin); :44-45 timing note "seems to be 1.5s for
  the cast, then 8s for the prison".
- CrutchAlerts AbilityData.lua:332 lists 132468 = Sanguine Prison.
- Negative grep: only Crutch covers 132468 among all 6 ref clones; ka.log
  has 0 lines for the id (33-line fixture, zone 1196).
- Dispatch channel: EventDispatcher.dispatchBeginCast routes F+castTime>0
  to beginCast.started, F+castTime==0 to beginCast.instant — registering
  the id in BOTH buckets guarantees exactly one dispatch per BEGIN
  regardless of what GetAbilityCastInfo reports (same pattern as every
  other CUSTOM entry in Falgravn.lua).

## Changes
- trial/ka/boss/Falgravn.lua (+19): FALGRAVN_PRISON_CAST = 132468 constant,
  handlePrisonCast (showAction of existing lang key ka_falgravn_kill_prison,
  no new lang key, no invented strings), entry in _beginCastInstant +
  _beginCastStarted. Commit e9cfd49.

## Tests
- sh test/checks/all.sh: 15/15 rc=0
- luacheck .: 0 warnings / 0 errors, 91 files, rc=0
- 0-behind: merge-base --is-ancestor de1dea6 HEAD rc=0
- ka.log replay (auto-detect zone 1196): 33 entries 0 parse errors,
  14 alerts, 0 handler errors — unchanged baseline (132468 absent from the
  fixture, as expected)
- Offline dispatcher probe rc=0: 132468 in EventDispatcher.abilityIdsFor
  combat set = YES; synthetic BEGIN dispatch -> exactly 1 alert
  "Kill! (Prison)".

## Uncertainties
- hitValue guard NOT replicated: Crutch fires its icon only when
  hitValue == 1500; the EventDispatcher does not pass hitValue to CUSTOM
  handlers, so our alert may also fire on other ACTION_RESULT_BEGIN
  results of 132468 (e.g. a later phased hit). Settles with any real KA
  Encounter log or in-game observation (#224).
- 1.5 s lead time is Crutch's comment, not a log measurement.

## Manual verification required
Trial: Kyne's Aegis / Boss: Falgravn / Difficulty: Veteran (any)
Needed: (a) does 132468 ACTION_RESULT_BEGIN appear with hitValue other
than 1500 (would double the alert); (b) actual cast lead before the
132473 prison debuff lands. Capture one Encounter.log pull with
/incha debug on.

## Known KA ref-gap remainder (not this branch)
133936 Exploding Spear (Crutch KynesAegis.lua:108 + DDD :700);
134196 Crashing Wave, 134023 Vrol meteor, 140606 Yandir meteor
(DisplayFormat.lua:85-87 display timings only — need handler design,
not a one-line route). Each deserves its own branch/task.

## Recommended next task
KA row id 133936 Exploding Spear dodge/damage alert (RESEARCH, ref =
Crutch OnExplodingSpearBegin KynesAegis.lua:108 — read its handler
semantics before wiring). Alternative: SE row (13 ref-only gaps,
SanitysEdgeHelper Data.lua) once SE fixture log lands.
