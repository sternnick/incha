# DAILY_REPORT — 2026-09-28 nightly (workflow=INCHA-DAILY)

## Selected task
Priority ladder after PRs #11–#15: the cross-validation matrix shipped in PR #13
listed 7 "mechanic-grade ref-only gaps" for Lucent Citadel (sign-off subtask
"Validate logic against reference addons", LC milestone). This run converted the
gaps with COMPLETE ref semantics into routed mechanics — workflow-code-review.md
§2 Priority 4 (evidence exists) feeding Priority 5 batching.

## Classification
RESEARCH → implemented the CONFIRMED-by-two-refs subset; four ids stay
HYPOTHESIS_REF_ONLY / INFERRED (see Uncertainties).

## Evidence
- 223028/223029 (Arcane Conveyance initial debuff): CrutchAlerts
  zones/trials/LucentCitadel.lua:9 (comment: initial debuff precedes the real
  tether 223060 by ~4 s), registrations :317-318 RegisterForEffectChanged
  "group", EFFECT_RESULT_GAINED/FADED handlers :50-64.
- 222613 (Weakening Charge): Crutch LucentCitadel.lua:324
  RegisterForEffectChanged on "group"; alert body :86-99 (GAINED → notify,
  FADED → clear).
- Both refs use EVENT_EFFECT_CHANGED semantics consistently for these ids;
  LucentCitadelHelper covers the tether debuff 223060 only (modules/Xoryn.lua).
- Negative evidence (why 4 ids NOT routed): 126371 and 219799 appear ONLY in
  LCH constant tables (Xoryn.lua:18,29) — grep of whole addon shows no dispatch
  path (SplinteredBurst is wired to glass_stomp_id 219797, not 219799).
  222071 Heavy Shock: LCH Orphic.lua:169 carries the ref's own
  "TODO(wonder): This isn't working, find actual ability ID".
  214311 vs 214136 Fate Sealer: LCH alerts 214311 on
  ACTION_RESULT_EFFECT_GAINED_DURATION (Orphic.lua:183-186); Crutch's prominent
  alert filters 214136 ACTION_RESULT_BEGIN tank-only (ProminentV2.lua:416-422,
  AbilityData.lua:345). Summon-begin vs ball-effect pair — INFERRED, log needed.
- Delta watch: upstream master unchanged de1dea6 (7th quiet night), since-filter
  0 items; all 5 fork PRs #11–#15 re-verified OPEN/MERGEABLE.

## Changes
- trial/lc/LCCommon.lua: 3 new id constants + 2 handlers
  (handleConveyanceInitial, handleWeakeningCharge) wired into
  effectChangedEntries.gained — inherited by all 5 LC bosses via the existing
  merge loops, same pattern as HINDERED/RADIANCE.
- lang/en.lua: lc_conv_tether_soon, lc_conv_weakening_charge, lc_conv_weakening_you.

## Tests
- sh test/checks/all.sh → rc=0, 15/15 (branch-name ok on feature/*).
- luacheck . → 0 warnings / 0 errors in 91 files.
- Replays unchanged: ka 14 alerts / ss 4 alerts, 0 handler errors.
- Offline dispatcher probe (scratch lc_probe.lua, rc=0): all 3 ids appear in
  EventDispatcher.abilityIdsFor effect set for Xoryn AND Orphic; GAINED on
  groupN tags produces 3 alerts; boss1 target stays silent (player guard).

## Uncertainties
- 223028/223029 alert both partners at initial-debuff time → the "pick
  partners" wording may fire twice within ms when both debuffs land; cosmetic,
  no dedup added (LC fixture cannot reproduce, §1 honesty).
- Whether the initial debuffs also FADE at tether cast (Crutch removes icons
  on FADED, :56-64): Incha only alerts (no persistent state), so FADED is
  intentionally unrouted — nothing to release.
- All three ids: ref-source evidence only; a real LC Encounter log (the single
  highest-value manual item per PR #13) is still needed to promote to
  VERIFIED_REF_AND_LOG.

## Manual verification required
Trial: Lucent Citadel · Boss: Xoryn (or Orphic) · Difficulty: Veteran
Needed: confirm 223028/223029 GAINED lands ~4 s before the 223060 tether cast
and 222613 GAINED/FADING semantics, for the sign-off log.
While in the fight run /incha debug and record any Dispatcher lines with
ability 223028/223029/222613 (result codes + change types).
Also capture: 214311 vs 214136 — which id appears when the Fate-Sealer orb
summons (begin) vs applies its debuff. That settles the Fate Sealer conflict.

## Recommended next task
Batch the remaining LC unknowns (Fate Sealer id pair, 222071, 126371, 219799)
into the same LC log request (INGAME_VERIFICATION/PRIORITY 5); first fork PR
whose diff touches a research/abilities/ file should also record the 4 deferred
ids' confidence grades per §9.3 evidence-DB format.
