# DAILY_REPORT 2026-09-29

## Selected task
SS milestone subtask "Validate logic against reference addons" (#217) —
implementing the mechanic-grade ref-only gaps from the cross-validation
matrix SS row (PR #13), specifically the Yolna takeoff events. Chosen
because LC (yesterday) and the KA row (rewrite territory per #224) are
taken/deferred, and the SS takeoff evidence is complete in a reference
addon while Incha routes none of it.

## Classification
RESEARCH -> implemented subset; evidence class HYPOTHESIS_REF_ONLY
(one reference, no log lines; promotion path = SS sign-off log, #229).

## Evidence
CrutchAlerts `zones/trials/sunspire/Sunspire.lua` (local clone):
- `:491-493` Takeoff75/50/25 registered result=nil (BEGIN pair) for
  124910/124915/124916; handlers `:297-361` DisplayDamageable(22.8/23.4/23.5).
- `:494` TurnOffAim 125693 with ACTION_RESULT_EFFECT_GAINED; `:363-372`
  OnYolFly re-arms by HP bracket (<30% → 23.5, <55% → 23.4, <80% → 22.8).
Negative evidence: grep of all 6 ref clones for these ids = Crutch-only.
ss.log = 0 lines for all four ids (fixture has no takeoff events).
DDDCombatAlerts: no coverage. So NOT promoted to two-ref consistency.

## Changes
`trial/ss/boss/Yolna.lua` only (+60):
- 4 id constants with route comments; takeoff entries in
  `_beginCastEntry` (instant+started copies), AimOff in
  `combatEvent.other` (EFFECT_GAINED has no dedicated bucket).
- Handlers arm the existing `landingTimer` (row-4 renderer already
  renders it). No new lang keys, no state fields, no CA bar.

## Tests
- `sh test/checks/all.sh` → 15/15, rc=0.
- `luacheck .` → 0 warnings / 0 errors, 91 files.
- Replays: ss 4 alerts / ka 14 alerts, 0 handler errors (unchanged).
- Offline dispatcher probe: all 4 ids in `abilityIdsFor` combat set;
  BEGIN arms landingTimer to 22.8/23.4/23.5; AimOff hp60 → 22.8
  (exactly Crutch's <0.8 branch), hp90 → unarmed. rc=0.

## Uncertainties
- Whether takeoffs are castTime=0 (instant) or timed on the real client:
  both buckets armed, so either path fires the landing arm once. If the
  engine emits F then T with castTime>0, the started handler arms and
  the T event is a no-op (executed bucket empty) — no double-arm.
- 125693's real-world result type is ref-claimed EFFECT_GAINED on
  COMBAT_EVENT; combatEvent.other accepts any non-damage result, so the
  arm is result-insensitive — an early aim-off event would arm a landing
  that the bracket logic still gates on HP.
- All four ids remain HYPOTHESIS_REF_ONLY: no log confirmation exists.

## Manual verification required
Trial: Sunspire / Boss: Yolnahkriin / Vet (any mode)
Run `/incha debug`, then observe row 4 at each fly phase: a "Landing"
countdown should appear the moment Yolna lifts off (~22-24 s out) at the
76% / 51% / 26% thresholds and again after mid-air aim re-acquisition.
Capture the pull's Encounter.log into test/fixtures/ss.log — one pull
promotes all four ids to VERIFIED_REF_AND_LOG and also settles the
deferred SS ids.

## Deferred from the same matrix row (with reason)
- 121074 / 121271 (Nahvii servant METEOR/KITE): part of a fixed 22-step
  SERVANT_SEQUENCE table (NahvPortal.lua:16-39) — a sequence-tracking
  feature, not a route entry. Needs its own task + likely a settings key.
- 115702 StormFury beam, 119596/122961 StormBreath telegraphs: ref
  handlers are CreateWorldTexture floor telegraphs (Sunspire.lua:237-253)
  — Incha has NO world-texture drawing layer (grep: none in trial/lib/core).
  Implementing an alert would deviate from ref behaviour (sound/banner vs
  floor graphic); the honest deliverable is a drawing-capability decision,
  not a guessed alert. Recommend a docs/decisions or issue discussion.

## Recommended next task
SS sign-off log ingestion when captured (#229): replay against the new
Yolna routes + coverage report; then the Nahvii servant-sequence feature
as its own branch (RESEARCH done, implementation = new capability).
