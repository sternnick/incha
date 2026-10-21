# Ability cross-validation matrix — 2026-09-26

Evidence database per agents/workflow-code-review.md §9.3 roadmap item 3, serving the
per-trial sign-off subtask "Validate logic against reference addons" (e.g. #217).
Refs used: CrutchAlerts, DDDCombatAlerts, SanitysEdgeHelper, QcellRockgroveHelper,
HowToCloudrest, LucentCitadelHelper (local clones). Confidence vocabulary:
VERIFIED_REF_AND_LOG / HYPOTHESIS_REF_ONLY / INFERRED / NEEDS GAME.

## Blocking repo finding (applies to every trial)

7 of 9 fixture logs are 2-line stubs (BEGIN_LOG + ZONE_CHANGED, zero ACTION lines):
se.log, rg.log, cr.log, as.log, lc.log, oc.log, dsr.log. Only ka.log (33 lines) and
ss.log (22 lines) carry real events. Consequence: the log-confirmation rung of the
evidence ladder is unavailable for 7 trials — no sign-off item relying on replay can
reach VERIFIED until real Encounter logs are captured. This is the single highest-value
manual task in the sign-off milestones.

## Per-trial matrix

| Trial | Incha ids | Ref-covered | Ref+log verified | Ref-only gaps (Incha LACKS) | Incha-only (unvalidatable) |
|---|---|---|---|---|---|
| SS Sunspire | 48 | 23 | 2 | 10 (below) | 25 |
| SE Sanity's Edge | 76 | 28 | 0 (log empty) | 13 | 48 |
| RG Rockgrove | 40 | 40 | 0 (log empty) | ~30 (mostly trash + procs) | 0 |
| CR Cloudrest | 43 | 43 | 0 (log empty) | ~18 | 0 |
| AS Asylum Sanctorium | 11 | 7 | 0 (log empty) | 5 | 4 |
| LC Lucent Citadel | 29 | 25 | 0 (log empty) | 7 (mechanic-grade) | ~4 |
| OC Ossein Cage | 57 | 15 | 0 (log empty) | refs thin (only ~15 ids tracked) | 42 |
| KA Kyne's Aegis | 41 | 24 | 6 ref+log | 5 (below) | 16 log-backed (refs icon-only) |
| DSR Dreadsail Reef | 74 | 37 | 0 (log empty) | 6 (one alt-id discrepancy) | ~50 (refs thin) |

## Mechanic-grade ref-only gaps worth implementing (HYPOTHESIS_REF_ONLY until log/in-game)

- SS: 115702 StormFury beam (Sunspire.lua:480); 119596/122961 StormBreath trigger+20%
  (:250,:253); 124910/124915/124916+125693 Yolna takeoff/aim ids (:491-494);
  121074 Aspect of Winter + 121271 Lightning Storm — Nahvii servant sequence
  (NahvPortal.lua:11/13; Incha has only CONE/NEGATE/PINS).
- SE: 186937/186948 Chimera maul+inferno; 198613/186953/186952 inferno debuff 1-3;
  199119/186995 Wamasu storm+repulsion; 199235 circuit_charge debuff;
  187059/189163 warlock sunburst/wrathstorm; 188760 Ansuul breakdown[1];
  184802 Yaseyla true shot (all SanitysEdgeHelper Data.lua).
- RG: 150837 Xalvakka escape; 150529/149294 volatile shell; 153444 eviscerate-initial;
  157281 manifold+powerbash; 152760/152761 tentacle whip; 149232 molten earth;
  149648 chomp (Qcell 245-270, 120-122).
- CR: 87346 Overload pre-debuff; 103765 Hoarfrost AoE; 105291/105339/105363/105373
  shadow beads; 106023 break-amulet; 104019/104036/104047 spear lifecycle
  (HowToCloudrest + Crutch Cloudrest.lua 414-479).
- AS: 99027 Manifest Wrath; 95466 Unraveling Energies (+58246 speedboost);
  99819 Noxious Gas; 101354 Enrage (Crutch AbilityData:281, AsylumSanctorium:46-48,
  MiniPanel:286-288).
- LC: 126371 Structured Entropy; 219799 Splintered Burst; 214311/214136 Fate Sealer;
  222071 Heavy Shock; 222613 Weakening Charge; 223028/223029 Arcane Conveyance-initial.
- KA: 132468 Sanguine Prison CAST (Incha routes only the 132473 debuff —
  KynesAegis.lua:103 vs Falgravn.lua:20); 133936 Exploding Spear; 134196 Crashing Wave;
  134023/140606 Vrol+Yandir meteors.
- DSR: 166929 Summon Siren; 167702 Platform Fall; 170547 Elixir.

## Alt-id discrepancies (NEEDS GAME — do not change without a real log)

- DSR Heartburn: refs use 170481 (Crutch ReefGuardian.lua:7, DDD Data:903);
  Incha routes 163692 (ReefGuardian.lua:19). Likely begin-vs-end or old-id pair.
- AS Oppressive Bolts: Crutch registers 95585 but names 95687 "Soul Stained
  Corruption" for display (MiniPanel.lua:7 vs :282) — Incha's 95585 matches the
  registration id; confirm which id appears in real logs before touching.
- DSR Piercing Hailstone/Destructive Ember: refs 166178/166209 vs Incha 166192/166210
  (variant ids, DreadsailReef.lua:483-484).

## Method notes / false positives excluded

World-coordinate tables (CreateWorldTexture/CreatePositionIcon/pos_list) produced ~70
numeric false positives across SS/SE — excluded by call-site inspection. Ref shared
files (AbilityData/CombatAlertsData) attributed only via zone-block tables or
trial-named comments. Full per-id data in lane transcripts
(~/.hermes/cache/delegation/live/deleg_ac4d4276/).
