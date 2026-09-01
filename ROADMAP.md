# Incha — Roadmap

Working plan last updated 2026-08-30. Phases are ordered by dependency.
Checked items are **shipped** (committed). Unchecked items are pending.

---

## Known bugs — fix immediately

### P0 — mechanic completely non-functional
- [x] **OC / JynorahEncounter — `handleReflective` parameter order inverted.**
      `trial/oc/boss/JynorahEncounter.lua:97` — plain-function combatRoute entries receive
      `(self, context, alerts, result, abilityId, unitTag, ...)` but `handleReflective`
      declares them as `(self, context, alerts, abilityId, result, ...)`.
      The condition `result == ACTION_RESULT_EFFECT_GAINED` compares a numeric abilityId
      against an enum — never matches. Reflective Scales yellow border never fires.
      **Fix:** swap the 4th and 5th parameter names.

### P1 — state correctness bugs
- [x] **DSR / ReefGuardian — `acidRefluxBarId` missing from `stateSchema`.**
      Added `acidRefluxBarId = false` to `stateSchema`.
- [x] **DSR / Taleria — `lureBarId` missing from `stateSchema`.**
      Added `lureBarId = false` to `stateSchema`.
- [x] **RG / Oaxiltso — `sludgeTracker1Tag` / `sludgeTracker1Name` missing from `stateSchema`.**
      Added both with `nil` value and doc comments to `stateSchema`.
- [x] **OC / KazpianEncounter — `chainedA` / `chainedB` not in `stateSchema`.**
      Added `chainedA = nil`, `chainedB = nil` to `stateSchema`.
- [x] **OC / OsseinCageCommon — `_carrionStacks` not reset on wipe.**
      Module-level upvalue survives encounter wipes; the stack count shown after a wipe
      reflects the pre-wipe value until the next `EFFECT_FADED` fires.
      **Fix:** export `OsseinCageCommon.reset()` and call it from each boss `onWipe`.

### File encoding corruption
- [x] Eight files contained `a"EUR` sequences (corrupted `─` U+2500 box-drawing chars).
      Fixed: replaced all occurrences with `─` and re-saved as UTF-8 without BOM.
      `trial/cr/boss/ZmajaEncounter.lua` was already clean (used `-- --` style).
      Fixed files:
      - `trial/as/boss/OlmsEncounter.lua` (647 replacements)
      - `trial/lc/boss/DarielEncounter.lua` (232)
      - `trial/lc/boss/OrphicEncounter.lua` (279)
      - `trial/lc/boss/RyelazEncounter.lua` (237)
      - `trial/lc/boss/XorynEncounter.lua` (348)
      - `trial/lc/boss/XynizataEncounter.lua` (279)
      - `trial/oc/boss/KazpianEncounter.lua` (207)
      - `trial/oc/boss/ShaperEncounter.lua` (207)

---

## Architecture phases

### Phase 0 — Memory foundation
- [x] Auto-derive `modulesToUnload` per trial via `trialModules(prefix)` in `incha.lua`;
      `ZoneManager` calls `ModuleLoader.unload(entry.unloadList)` on zone exit so
      `package.loaded` entries are cleared between zone visits.
      **Architectural note**: ESO's `require` shim is lookup-only (no file I/O); all
      modules are executed at startup via `incha.txt`.  `package.loaded` can be cleared
      between zone visits, but the Trial objects and their boss-class references stay
      alive in `trials[]` so re-entry never re-requires anything at runtime.  True
      GC of module tables would require restructuring Factory to create fresh Trial
      instances on each zone entry — deferred.
- [ ] Verify GC baseline: `collectgarbage("count")` before/after entering and leaving
      a trial zone; confirm `package.loaded` sweep returns to pre-enter size.
- [x] `lib/Throttle.lua` — `Trial:onPowerUpdate` is bucket-gated (1% granularity)
      so health-rule evaluation and UI updates only fire when `healthPercent` changes
      meaningfully.  `Throttle:reset()` is called on boss transitions.
- [x] Reduce hot-path allocation in `HealthRules.evaluate` / `Panel` handlers:
      `HealthRules.evaluate` early-returns on nil rules (no `or {}` allocation);
      `Panel` info/action/header handlers skip `SetText` + `applyVisibility` when
      value is unchanged; `Trial:onPowerUpdate` uses `context.inCombat` instead of
      the `IsUnitInCombat` ESO API call.

### Phase 1 — `lib/` primitives
- [x] `lib/Timer.lua` — `Timer.new(duration)`, `:remaining()`, `:isExpired()`, `:reset()`.
      Used by all KA bosses.
- [x] `lib/Log.lua` — debug output gated behind a settings flag.
- [x] `lib/Throttle.lua` — formalized and in use via `Trial.healthThrottle`.

### Phase 2 — Settings foundation
- [x] `core/Settings.lua` — `ZO_SavedVars:NewAccountWide`-backed namespace (`Incha_SV`),
      defaults-merging, per-trial enable flags.

### Phase 3A — Config UI (LAM settings panel)
- [x] `ui/Menu.lua` — LibAddonMenu-2.0 panel wired via `## OptionalDependsOn`.
      `/incha` slash-command fallback always present.
      Settings panel has General, Overlay, KA, RG, DSR sections.
      **Add new trial sections as each trial reaches Phase X.2+.**

### Phase 3B — Overlay UI (in-play HUD)
- [x] `ui/Panel.lua` — `WINDOW_MANAGER` overlay implementing AlertSink vocabulary
      (`header`, `info1–10`, `action`, `clear`, `hideAction`; 10 info lines —
      INFO_LINE_COUNT in ui/Panel.lua:37 — in a 320x260 window.)
      Drag-to-move + lock; position/scale persisted in `core/Settings.lua`.
      Used by `ka`, `rg`, `dsr` as default bridge.

### Phase 4 — Retire BSCHTKA dependency for `ka`
- [x] Deleted `trial/ka/bridge/LegacyUI.lua` (dead 119-line bridge).
- [x] KA Factory now uses `Panel` directly; `ka` no longer depends on BSCHTKA at runtime.

### Phase 5 — Markers/icons helper (OSI)
- [x] `OSI.SetMechanicIconForUnit` wired for KA/Falgravn: Prison, Instability,
      Blood Synergy icons using `GetAbilityIcon` textures.
- [ ] `OSI.CreatePositionIcon` for floor/world markers — requires in-game coordinate
      measurement for each boss room (see In-game verification section).

### Phase 6 — Flesh out `rg` / `dsr`
- [x] Infrastructure: `Trial.create`, `Factory`, `BossRegistry`, stub modules.
- [x] `rg`: Bahsei (enrage + ManifoldDebuff OSI), Oaxiltso (stub), Xalvakka (ManifoldDebuff OSI).
      Location bounds TBD (currently `Location.new(0,0,0,0,0,0)` — zone detection always false).
- [x] `dsr`: Lylanar (stub), ReefGuardian (stub), Taleria (stub).
      Location bounds TBD.
- [ ] Real `Location` bounds for both trials — verify unit zone coordinates in-game.
- [ ] Real HM health thresholds for RG (Bahsei, Oaxiltso, Xalvakka) and DSR (all bosses).
      RG reference confirms `maxTargetHP > 100_000_000` is the HM boundary; use
      `GetUnitMaxPower("boss1", POWERTYPE_HEALTH)` on a vet HM clear for exact values.
- [ ] **DSR / Lylanar** — register `lylanar_torrid_cleave = 167298` and
      `turlassil_brisk_rip = 167290` (frontal cleaves, currently untracked).
- [ ] **DSR / ReefGuardian** — register third crab ability `166585`; add Heartburn
      resolution tracking: `166031` (success) / `166032` (fail).
- [ ] **DSR / Taleria** — register second Barnacle Blade variant `174801`
      (existing `BARNACLE_BLADE = 163901` covers only one variant).

---

## Trial roadmap

### KA — Kyne's Aegis (zoneId = 1196) ✅ Complete (feature-complete)
- [x] Infrastructure: Factory, CombatHandler, BossRegistry, Location
- [x] Yandir (boss 1): totem timer, portal alert, connection node tracking
- [x] Vrol (boss 2): portal kill-timer, fog duration countdown + extension tracking,
      Harpoon conduit timer, Apothecary interrupt
- [x] Falgravn (boss 3): Prison/Instability/Blood Synergy OSI icons, BlockCast fix,
      Torturer 25 s pre-alert via `zo_callLater` + combat guard
- [ ] KA OSI floor icons (deferred — requires in-game coordinate measurement):
      connection nodes (×8), blood fountain spawns, torturer walk positions
- [ ] Falgravn: add prisoner-feed pre-wipe warning at stack 9 or 10 (current code tracks
      the counter but fires no alert before the group wipes at 11 stacks)

---

### RG — Rockgrove (zoneId = 1263) 🔄 In progress
- [x] Infrastructure: Factory, CombatHandler, BossRegistry stubs
- [x] Bahsei (boss 1): enrage at 50%/25% HP rules; ManifoldDebuff OSI mechanic icon
- [x] Oaxiltso (boss 2): stub
- [x] Xalvakka (boss 3): ManifoldDebuff OSI mechanic icon
- [ ] Real Location bounds (zone coordinates needed in-game)
- [ ] HM thresholds for all three bosses (verify in-game)
- [x] Oaxiltso real mechanics (reference: `QcellRockgroveHelper` at `D:\dev\AddOns\QcellRockgroveHelper`)
- [ ] Xalvakka: shield event parameters, first-jump timing (verify in-game)

---

### DSR — Dreadsail Reef (zoneId = 1344) 🔄 In progress
- [x] Infrastructure: Factory, CombatHandler, BossRegistry stubs
- [x] Lylanar (boss 1): stub
- [x] ReefGuardian (boss 2): stub
- [x] Taleria (boss 3): stub
- [ ] Real Location bounds (zone coordinates needed in-game)
- [ ] All boss mechanics — no reference addon for this trial yet

---

### AS — Asylum Sanctorium (zoneId = 1000) 📋 Planned

**Architecture note:** AS is a *concurrent* multi-boss fight — Olms is always present; Llothis and
Felms spawn and go dormant on timers. This doesn't fit the single-active-boss pattern.
Model it as a **single compound boss module** (`OlmsEncounter`) that tracks all three entities
internally, rather than wiring three separate boss modules through `BossRegistry`.

**Reference addons:** `AsylumPriorityTarget` (priority targeting UI), `AsylumTracker` (comprehensive
timer tracker). Key ability IDs extracted from both.

#### AS-1 — Infrastructure
- [ ] `trial/as/Factory.lua` — zone detection (zoneId=1000), create trial, wire `OlmsEncounter`
- [ ] `trial/as/CombatHandler.lua` — delegates combat/effect events to `OlmsEncounter`
- [ ] Register `as` in `incha.lua`; add `## Description` update for AS

#### AS-2 — OlmsEncounter (single compound module)
Boss name: `"Saint Olms the Just"` (from `GetUnitName("boss1")`)

**Ability IDs (from AsylumTracker/AsylumPriorityTarget):**
```
OLMS_STORM_THE_HEAVENS  = 98535   -- Kite! 41 s repeat
OLMS_TRIAL_BY_FIRE      = 98582   -- Below 25% HP
OLMS_SCALDING_ROAR      = 98683   -- Steam breath, 28 s repeat
OLMS_GUSTS_OF_STEAM     = 98868   -- Jumps at 90/75/50/25%
OLMS_EXHAUSTIVE_CHARGES = 95482   -- 12 s repeat
STATIC_SHIELD           = 96010   -- Protector shield on Olms
LLOTHIS_DEFILING_BLAST  = 95545   -- Cone — alert with target name
LLOTHIS_OPPRESSIVE_BOLTS = 95585  -- Interrupt!
FELMS_TELEPORT_STRIKE   = 99138   -- Jump — alert with target name
DORMANT                 = 99990   -- EFFECT_RESULT_GAINED = mini sleeps;
                                  --   FADED = mini wakes
BOSS_EVENT              = 10298   -- ACTION_RESULT_EFFECT_GAINED hitValue=1
                                  --   records exact mini-boss spawn timestamp
```
- [ ] Track Llothis active/dormant state via `DORMANT` effect on unitName search "Llothis"
- [ ] Track Felms active/dormant state via `DORMANT` effect on unitName search "Felms"
- [ ] Alert `showAction("INTERRUPT Llothis!")` on `OPPRESSIVE_BOLTS BEGIN`
- [ ] Alert `showAction("Cone → <name>")` on `DEFILING_BLAST BEGIN` (hitValue=2000 filter)
- [ ] Alert `showAction("Felms jump → <name>")` on `TELEPORT_STRIKE BEGIN`
- [ ] Alert `showAction("Kite!")` on `STORM_THE_HEAVENS BEGIN`; 6 s pre-warning from timer
- [ ] Alert `showInfo` for Static Shield (protector up/down)
- [ ] `onUpdate`: display countdown timers for next Defiling Blast (~21 s), Oppressive Bolts (~12 s),
      Storm the Heavens (~41 s), Teleport Strike (~21 s)
- [ ] HP milestone alerts at 90/75/50/25% (Olms jump pre-warning)
- [ ] `reset()` on combat exit (wipe guard via `zo_callLater` + `IsUnitInCombat`)
- [ ] OSI icons: Oppressive Bolts targets (if applicable — verify if player-targeted)

#### AS-3 — In-game verification
- [ ] Real Location bounds — stand at room corners: `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
- [ ] Confirm exact boss name string returned by `GetUnitName("boss1")` in EN/other locales
- [ ] Confirm `hitValue` filter needed on Defiling Blast (ref uses `hitValue == 2000`)
- [ ] Verify mini-boss spawn timing (~12 s from `BOSS_EVENT`) for pre-warning accuracy
- [ ] HM thresholds for Saint Olms, Llothis, and Felms: `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`

---

### CR — Cloudrest (zoneId = 1051) 🔄 In progress

**Architecture note:** CR supports +0/+1/+2/+3 variants. The mini-bosses (Siroria, Relequen, Galenwe)
can be active simultaneously with Z'Maja. Use a single encounter module similar to AS,
or separate mini-boss sub-modules keyed by unit name. Recommend: single `ZmajaEncounter` that
registers handlers for all entities, gated by which variant is active.

**Reference addon:** `HowToCloudrest` (comprehensive tracker).

**Zone ID:** 1051 — confirmed in-game.

#### CR-1 — Infrastructure
- [ ] Determine zone ID (in-game verification)
- [ ] `trial/cr/Factory.lua`, `trial/cr/CombatHandler.lua`
- [ ] Register `cr` in `incha.lua`

#### CR-2 — Mini-boss mechanics (Siroria, Relequen, Galenwe)
These appear in the pre-Z'Maja phase (portal realm) and optionally alongside Z'Maja.

**Key ability IDs:**
```
-- Heavy Attacks (HA warning)
SIRORIA_HA    = 104755
RELEQUEN_HA   = 105780
GALENWE_HA    = 106375

-- Mini jumps (each mini teleports/jumps — dodge area)
SIRORIA_JUMP  = 106601
RELEQUEN_FLUX = 105796
GALENWE_TELE  = 106682

-- Interrupt channels
RELEQUEN_DIRECT_CURRENT  = 105380  -- Bash!
GALENWE_GLACIAL_SPIKES   = 106405  -- Bash!

-- Mini skills
SIRORIA_BANNER = 104902
RELEQUEN_JOLT  = 106614
GALENWE_DONUT  = 106378

-- Creeper root
RAZOR_THORNS   = 106656

-- Siroria
SIRORIA_DARK_TALONS   = 105765
SIRORIA_ROARING_FLARE = 103531  -- 110431 for execute phase

-- Relequen
RELEQUEN_OVERLOAD     = 87346   -- 103555 for debuff on player

-- Galenwe
GALENWE_HOARFROST_CAST  = 105151  -- 110466 execute
GALENWE_HOARFROST       = 103695  -- 110516 execute
GALENWE_HOARFROST_SYN   = 103697  -- 110525 execute
GALENWE_HOARFROST_AOE   = 103765
GALENWE_CHILLING_COMET  = 106374  -- 106367
```
- [ ] HA warnings for active mini-bosses
- [ ] Jump alerts with mini-boss name
- [ ] Interrupt alerts (`DIRECT_CURRENT`, `GLACIAL_SPIKES`)
- [ ] Overload target name alert (Relequen)
- [ ] Hoarfrost player icon via OSI (Galenwe)

#### CR-3 — Z'Maja encounter
```
-- Portal phases
ZMAJA_RESET        = 107478  -- Reset portals
PORTAL_OPEN        = 103946
PORTAL_CLOSED_1    = 104057
PORTAL_CLOSED_2    = 104792
PORTAL_CLOSED_3    = 105890
PORTAL_CLOSED_4    = 105218  -- player exits shadow realm

-- Malevolent Cores (balls)
CORE_EXPOSED       = 103980
CORE_PICKED_UP     = 103989  -- hitValue: ball picked up
CORE_MISSED        = 110202  -- ball hits player (not picked up)

-- Z'Maja mechanics
ZMAJA_JUMP         = 104564
ZMAJA_HIDE_JUMP    = 104452
CRUSHING_DARK_1    = 105152
CRUSHING_DARK_2    = 105172
CRUSHING_DARK_3    = 105239
SHADOW_SPLASH      = 105123  -- Drop from ceiling
BANEFUL_MARK       = 107196  -- Execute mechanic
SHADOW_BEAD_TICK   = 105339
SHADOW_BEAD_SPAWN  = 105363
SHADOW_BEAD_CHARGE = 105373
CREEPER_SPAWN      = 105016
OLORIME_SPEAR      = 104018  -- Spear grant
ZMAJA_SHACKLE_MINI = 107490  -- Mini dies → Z'Maja phase
```
- [ ] Portal open/close alerts
- [ ] Z'Maja jump alert + position tracking
- [ ] Crushing Darkness alert (kite)
- [ ] Shadow Splash cast bar
- [ ] Baneful Mark (execute) alert
- [ ] Malevolent Core: balls not picked up alert
- [ ] Olorime Spear: flash alert on spear grant

#### CR-4 — In-game verification
- [x] Zone ID constant — 1051 ✓
- [ ] Real Location bounds — stand at room corners: `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
- [ ] HM threshold for Z'Maja: `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`
- [ ] Confirm portal assignments fire correctly with all group configurations
- [ ] Verify Shadow Bead spawn/charge events for ground-icon eligibility

---

### LC — Lucent Citadel (zoneId = 1478) 🔄 In progress

**Architecture note:** Sequential bosses, fits single-active-boss model.
5–6 encounters: Baron, Cavot, Orphic, Xoryn, Zilyesset (with Count Ryelaz).
ArcaneKnot may be a sub-phase or trash encounter — verify in-game.

**Reference addons:** `LucentCitadelHelper` (LCH), `LucentCitadel` (LC).

**Zone ID:** 1478 — confirmed in-game.

#### LC-1 — Infrastructure
- [ ] Determine zone ID
- [ ] `trial/lc/Factory.lua`, `trial/lc/CombatHandler.lua`
- [ ] Register `lc` in `incha.lua`; stub bosses: Baron, Cavot, Orphic, Xoryn, Zilyesset

#### LC-2 — Common / trash mechanics
These apply throughout all encounters:
```
HINDERED          = 165972  -- Tank swap debuff → OSI icon for tanks
RADIANCE_DEBUFF   = 214675  -- Screen border alert (CombatAlerts.AlertBorder)
SOLAR_FLARE       = 222475  -- Dremora Spellcaster cast bar alert
```
- [ ] `trial/lc/LCCommon.lua`: Hindered OSI icon (tank-only), Radiance border, Solar Flare cast bar

#### LC-3 — Orphic
From LCH: color-change mechanic, clock mechanic (cardinal/non-cardinal).
- [ ] Verify Orphic ability IDs from LCH.Orphic module (not yet read — verify separately)
- [ ] Color-change alert (was `orphicIsCastingColorChange` tracked in LC status)
- [ ] Clock phase alert

#### LC-4 — Xoryn
```
SPLINTERED_BURST     = 219799  -- Crystal Atronach AOE on tank
GLASS_STOMP          = 219797  -- Splintered Shards cast
ARCANE_CONVEYANCE    = 223024  -- Tether cast
ARCANE_CONVEYANCE_DB = 223060  -- Tether debuff
LUSTROUS_JAVELIN     = 223546  -- Mantikora Javelin
NECROTIC_BARRAGE     = 223198
ACCELERATING_CHARGE  = 214542  -- Channel before chain lightning (interrupt!)
FLUCTUATING_CURRENT  = 214597  -- Debuff: holding for up to 15 s → death
OVERLOADED_CURRENT   = 214745  -- Debuff from dropping fluctuating current
TEMPEST              = 215107  -- Group-wide line mechanic from mirrors
KNOT_CARRY           = 213477  -- Player picks up knot → alert with name
```
- [ ] Accelerating Charge interrupt alert
- [ ] Fluctuating Current player icon (timer OSI + alert if >12 s held)
- [ ] Arcane Conveyance cast alert: `223024` / `ACTION_RESULT_BEGIN` — group-wide warning
      *before* the debuff lands (currently only the tethered player's debuff `223060` is tracked)
- [ ] Knot Carry: who holds it → `showInfo` for **all** players, not just the holder.
      Reference (`LCH.Xoryn`): `knotHolder = GetNameForId(targetUnitId)` shown to everyone.
- [ ] Tether debuff player icons
- [ ] Tempest line mechanic alert

**Missing vs. LucentCitadelHelper (Ryelaz):**
- [ ] Add-spawn alerts gated on `self.playerSide`: `summon_shardborn_lightweaver = 218113`
      (light side) and `summon_gloomy_blackguard = 218109` (dark side). These adds require
      priority attention; their spawns are currently unannounced.

#### LC-5 — Zilyesset (with Count Ryelaz)
```
BRILLIANT_ANNIHILATION = 214187  -- Room wipe → cast bar
BLEAK_ANNIHILATION     = 214203  -- Room wipe → cast bar
PORCINLIGHT            = 219329  -- Player is on dark side (with Count Ryelaz)
PORCINDARK             = 219330  -- Player is on light side (with Zilyesset)
SUMMON_LIGHTWEAVER     = 218113  -- Big add (light side)
SUMMON_BLACKGUARD      = 218109  -- Big add (dark side)
```
OSI pad icons (world coordinates from LCH.Zilyesset — 6 numbered pads):
```
Count Ryelaz side:  [127371,33533,132051] [125015,33533,133229] [122751,33533,131966]
Zilyesset side:     [127396,33541,128074] [124978,33541,126882] [122814,33541,127806]
```
- [ ] Annihilation cast bar alert (both Brilliant and Bleak, deduplicate with `annihilationOngoing` flag)
- [ ] Player side detection (`showInfo` which boss room they're in)
- [ ] Big add alert when on matching side
- [ ] OSI pad number icons (1/2/3 on each side) — requires OSI

#### LC-6 — Baron and Cavot
These modules exist in LC main but LCH doesn't cover them → mechanics unknown without reading LC boss files.
- [ ] Read `LucentCitadel/boss/Baron.lua` and `Cavot.lua` to extract ability IDs
- [ ] Implement once abilities are known

#### LC-7 — In-game verification
- [x] Zone ID — 1478 ✓
- [ ] Boss name strings
- [ ] Real Location bounds — stand at room corners: `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
- [ ] HM thresholds for all bosses: `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`
- [ ] Pad icon coordinate accuracy (LCH coords pre-measured but verify they match)

---

### OC — Ossein Cage (zoneId = 1548) 🔄 In progress

**Architecture note:** 3 sequential bosses, fits single-active-boss model.
Boss 1: Jynorah (with Skorkhif mini). Boss 2: Kazpian. Boss 3: Shaper of Flesh.

**Reference addons:** `OsseinCageHelper` (OCH), `AsquartOsseinCageHelper` (Asquart).

**Zone ID:** 1548 — confirmed in-game.

#### OC-0 — Immediate bugs (see Known Bugs section above)
- [x] Fix `handleReflective` parameter order in JynorahEncounter (P0 — mechanic completely broken)
- [x] Add `chainedA = nil`, `chainedB = nil` to KazpianEncounter `stateSchema`
- [x] Export `OsseinCageCommon.reset()` and call from each boss `onWipe` to clear
      `_carrionStacks` (currently stale after wipes)

#### OC-1 — Infrastructure
- [ ] Determine zone ID
- [ ] `trial/oc/Factory.lua`, `trial/oc/CombatHandler.lua`
- [ ] Register `oc` in `incha.lua`; stub bosses: Jynorah, Kazpian, ShaperOfFlesh

#### OC-2 — Common / trash mechanics
```
HINDERED             = 165972   -- Tank swap debuff → OSI icon (tank-only)
MURDEROUS_TRAUMA     = 245785   -- Tormented Carrion Reaper heavy → heal absorption
SECOND_BOSS_TRAUMA   = 245919   -- Boss 2 heavy trauma
SPECTRAL_REVENGE     = 236569   -- Spectral Revenant
SKULLSTORM           = 236631   -- Skullmancer → cast bar alert
ASPECT_OF_TERROR     = 245318
TOXIC_IRE            = 160007   -- Spectral Revenant → "Toxic Ire (you)" alert
CORVID_SWARM         = 236947   -- Murder Corvid → screen border debuff
CURSED_TERRAIN       = 236571   -- Tormented Deadraiser → screen border debuff
DETONATE_SOUL_DB     = 236778   -- Soul Devourer → cast bar alert on player
LIFE_DRAIN           = 236751   -- Soul Devourer → alert on player
THISA_BLOOD_DIVE     = 238847   -- Blood Drinker → alert
CAUSTIC_CARRION_1    = 240708   -- Trash/Boss1/3 portals debuff → show stack count
CAUSTIC_CARRION_2    = 241089   -- Boss2 portals debuff
```
- [ ] Hindered OSI icon (tank-only)
- [ ] Skullstorm cast bar
- [ ] Toxic Ire alert (only once per 10 s to avoid spam)
- [ ] Screen borders for Corvid Swarm, Cursed Terrain
- [ ] Detonate Soul cast bar + alert
- [ ] Life Drain alert
- [ ] Caustic Carrion stack display (`showInfo`) with color gradient (6/8/10 max by boss)

#### OC-3 — Jynorah (boss 1)
Two dragons: **Myrinax** (sparking/blue) and **Valneer** (blazing/red), plus main bosses Jynorah and Skorkhif.

```
-- Curses
SPARKING_CURSE_CAST  = 234000   -- From Jynorah
BLAZING_CURSE_CAST   = 234276   -- From Skorkhif
SPARKING_CURSE_DB    = 234008   -- Debuff on player
BLAZING_CURSE_DB     = 234280   -- Debuff on player

-- Stomps (dodge area)
COLDFLAME_STOMP      = 234521   -- Jynorah
BRIMSTONE_STOMP      = 234524   -- Skorkhif

-- Fire walls
COLDFLAME_SURGE      = 234321   -- Jynorah → "Surge (you)" if player hit
BRIMSTONE_SURGE      = 234330   -- Skorkhif → "Surge (you)" if player hit

-- Titanic Clash (phase where dragons fight each other)
TITANIC_CLASH        = 232375   -- Phase start → ~37.5 s duration countdown
TITANIC_CLASH_HIT_V  = 232460   -- Hits Valneer
TITANIC_CLASH_HIT_M  = 232465   -- Hits Myrinax

-- Titanic Leaps (dragons leap in room)
MYRINAX_LEAP_UPPER   = 233477
MYRINAX_LEAP_EXIT    = 234704
MYRINAX_LEAP_MID     = 233452
VALNEER_LEAP_UPPER   = 233489
VALNEER_LEAP_EXIT    = 234722
VALNEER_LEAP_MID     = 233466
-- Cooldowns: first=5s, recurring=48s, execute=48s (adjust by leaps since Clash)

-- Heat Rays (from dragon summons)
JYN_HEAT_RAY         = 234141   -- Jynorah's dragon summon
SKOR_HEAT_RAY        = 234161   -- Skorkhif's dragon summon

-- Reflective Scales (tank mechanic — don't hit during this)
MYRINAX_REFL_SCALES  = 233321
VALNEER_REFL_SCALES  = 233330

-- Tail Slams
MYRINAX_TAIL_SLAM    = 235800
VALNEER_TAIL_SLAM    = 235803

-- Incinerating Smash
INCINERATING_SMASH   = 233594
SWIFT_DETONATION     = 234437

-- Dragon breath (ground icon on target)
MYRINAX_GOADED_BREATH = 234548
VALNEER_GOADED_BREATH = 234558

-- Portal phase
-- (ability IDs TBD — verify in-game)
```
- [ ] Curse debuff alert with color (blue=sparking, red=blazing)
- [ ] Stomp alert (dodge!)
- [ ] Surge alert when player is targeted
- [ ] Titanic Clash phase: countdown timer in `showInfo`
- [ ] Titanic Leap countdown between leaps
- [ ] Heat Ray alert (show only if relevant curse active — match Jyn vs Skor)
- [ ] Reflective Scales: screen border or cast bar when on tank
- [ ] Dragon breath: OSI ground icon on targeted player
- [ ] Portal phase alert + boss-side assignment hint

#### OC-4 — Kazpian (boss 2)
```
-- Molag Kena mechanics
HEAVY_SHOCK          = 235206   -- Interrupt!
STORM_SLAM           = 235201
STORM_SURGE          = 235205

-- Chains
DOMINATORS_CHAINS_1  = 232773   -- Chain cast
DOMINATORS_CHAINS_2  = 232775
CHAINS_ACTIVE_1      = 232779   -- Chain debuff active
CHAINS_ACTIVE_2      = 232780
TORTUROUS_CHAINS     = 236338   -- Debuff: players too close

-- Giant Sword
SWORD_KB_PULSE_1     = 235495
SWORD_KB_PULSE_2     = 244937
SWORD_CONES          = 232574
SWORD_SHOCK_SPEAR    = 235514

-- Kazpian own
KAZPIAN_TRAUMA       = 245165   -- Frenzy trauma
AGONIZER_BOMBS       = 237149
BITING_BLAZE_1       = 235354   -- Cast
BITING_BLAZE_2       = 246009
VILE_LEAP            = 235557
SEETHING_VILE_LEAP   = 245208
VILE_TELEPORT        = 232969   -- Teleport to start portal phase

-- Trash helpers
STRICKEN             = 235594   -- Tank swap debuff
RITUAL_BUFF          = 234349   -- Pain Channeler portal active
FIREBOMB_DB          = 245264
TREMOR_SHARDS        = 245255   -- King Khrogo
IMMOLATING_SPHERE    = 237011   -- Incinerator
```
- [ ] Heavy Shock interrupt alert
- [ ] Chains alert with targets (who is chained)
- [ ] Torturous Chains: alert if player has both chain debuffs nearby (too close)
- [ ] Giant Sword: alert on cones/knockback pulse
- [ ] Agonizer Bombs alert
- [ ] Biting Blaze: cast bar alert
- [ ] Vile Leap / Seething Vile Leap alert
- [ ] Portal phase: detect via `VILE_TELEPORT` or `RITUAL_BUFF`

#### OC-5 — Shaper of Flesh (boss 3)
- [ ] Read `OsseinCageHelper/modules/ShaperOfFlesh.lua` to extract ability IDs
- [ ] Implement once abilities are known

#### OC-6 — In-game verification
- [x] Zone ID — 1548 ✓
- [ ] Boss name strings
- [ ] Real Location bounds — stand at room corners: `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
- [ ] HM thresholds (Jynorah/Skorkhif dragon_max_hp=242176464 on vet HM confirmed; verify Kazpian + Shaper): `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`
- [ ] Portal color assignment logic (Jynorah) — verify curse tracking accuracy
- [ ] Caustic Carrion max danger stacks per boss (6/8/10 per OCH)

---

### SE — Sanity's Edge (zoneId = 1427) 📋 Planned

**Architecture note:** 3 sequential bosses, fits single-active-boss model.
Boss 1: Exarchanic Yaseyla. Boss 2: Chimera. Boss 3: Ansuul the Tormentor.

**Reference addons:** `SanitysEdgeHelper` (SEH), `SlipsSanitysEdgeAssist` (SSEA).

#### SE-1 — Infrastructure
- [ ] `trial/se/Factory.lua`, `trial/se/CombatHandler.lua`
- [ ] Register `se` in `incha.lua`; stub bosses: Yaseyla, Chimera, Ansuul

#### SE-2 — Yaseyla (boss 1)
**Cleanup:**
- [ ] Remove dead constant `ARCHER_TRUE_SHOT = 184802` (no combatRoute entry; or add a
      comment block explicitly marking it unimplemented to explain the gap).

```
-- Primary abilities
FIREBOMB_TOSS        = 183660
SHRAPNEL             = 199131
KNIFE_BLAST          = 183803   -- 183804
VENGEFUL_STRIKE      = 185071
VANTONS_CLARITY      = 184041   -- Portal synergy
SEETHE               = 162783   -- Enrage

-- Wamasu charges (Contramagis Wamasu)
WAMASU_CHARGE_1      = 191133
WAMASU_CHARGE_2      = 191139
WAMASU_CHARGE_3      = 191134
WAMASU_CHARGE_4      = 200544
WAMASU_CHARGE_5      = 200558
WAMASU_CHARGE_6      = 200559

-- Wamasu Charged Headbutt
HEADBUTT_1           = 184999
HEADBUTT_2           = 185002
HEADBUTT_3           = 185000

-- Wamasu Overwhelming Lightning
OVW_LIGHTNING_1      = 183598
OVW_LIGHTNING_2      = 198510
OVW_LIGHTNING_3      = 183599

-- Frost Bombs (Tomb mechanic)
TOMB_FROSTBOMB_1..9  = 183790,183783,192304,191049,188065,199254,185406,183768,185392

-- Hindered
HINDERED             = 165972   -- Tank swap debuff → OSI icon (tank-only)

-- Trueshot
TRUESHOT             = 184802
```
HP milestone alerts (from SSEA defaults): 90%, 70%, 50%, 30%, 20%, 10% — Wamasu + Archers warning;
60%, 35% — portal phase; 80%, 55%, 25%, 20%, 10% — Shrapnel warning.

- [ ] Hindered OSI icon (tank-only)
- [ ] Wamasu charge cast bar + ground icon on targeted player
- [ ] Fire Bomb Toss alert
- [ ] Shrapnel alert
- [ ] Knife Blast cast bar
- [ ] Vengeful Strike alert
- [ ] Frost Bomb OSI target icon (who has it)
- [ ] Portal alert on Vanton's Clarity
- [ ] HP milestone pre-warnings (Wamasu/portal/Shrapnel phases)
- [ ] Enrage (Seethe) alert

#### SE-3 — Chimera (boss 2)
Chimera alternates between active (stone-form off) and petrified phases. Key timers:
- Despawn timer (active → petrify countdown)
- Chain Lightning repeat timer

```
-- Chain Lightning (many variants)
CHAIN_LIGHTNING      = {183858,183898,183911,183913,184033,184028,184036,
                        184032,184029,184030,183915,183917,183885}

-- Chain Circuit debuffs on players
CHAIN_CIRCUIT_DB     = {184063,184068,184066,184067}

-- Arctic Shred (~5.5 s cooldown)
ARCTIC_SHRED         = 184275

-- Lifecycle
VIVIFY               = 186000   -- Comes out of stone
PETRIFY              = 185038   -- Goes back into stone

-- Sub-boss abilities
LION_DOUBLE_STRIKE   = 186969   -- Ascendant Lion
GRYPHON_PECK         = 187002   -- Ascendant Gryphon
```
OSI position icons (portal locations — hard-coded world coordinates):
```
WAMASU_PORTAL:  [182466, 40391, 222635]
LION_PORTAL:    [187456, 40387, 222644]
GRYPHON_PORTAL: [185015, 40390, 228119]
```
Crystal number icons (used during active phase for positioning):
- Normal mode: 4 sets of 3 positions each
- HM: 5 sets of 3 positions each
- Coordinates in SEH.data (need to read `SanitysEdgeHelper` main data file)

- [ ] Vivify/Petrify: track active/petrified state
- [ ] Despawn timer countdown in `showInfo` when Chimera is active
- [ ] Chain Lightning timer countdown
- [ ] Chain Circuit debuff OSI player icon
- [ ] Arctic Shred alert
- [ ] Lion Double Strike + Gryphon Peck cast bar alerts
- [ ] OSI portal icons (Wamasu/Lion/Gryphon positions)
- [ ] Crystal number icons (need coordinates from SEH data file)

#### SE-4 — Ansuul the Tormentor (boss 3)
**Missing vs. SanitysEdgeHelper:**
- [ ] Register 4th breakdown variant `188760` — reference: `{188760, 188766, 188768, 188769}`.
      Incha has 188766/68/69; if the game fires 188760 the triplet transition silently fails.
- [ ] Add warlock add alerts: `ansuul_warlock_sunburst = 187059` and
      `ansuul_warlock_wrathstorm = 189163` (Warlock adds cast both with no current alert).
- [ ] `hmHealthThreshold = 100000000` is a round-number TODO sentinel — measure in-game.

The most complex SE boss. Has a maze phase (The Ritual) and a split-clone phase (Breakdown).

```
-- Primary mechanics
POISONED_MIND        = {184707,184709,199644,184711}  -- Poison debuff → green border
MANIC_PHOBIA         = {185117,185123,185171,185251}  -- Player icon (fear marker)
WRACK                = 184621   -- Kite lightning
CALAMITY             = 186728   -- Heavy cone → timer countdown
SUNBURST             = 199344   -- Fire explosion circle
WRATHSTORM           = 189163
EXECUTE              = 198482
CORRUPT              = 187091

-- Enraged Atronachs
ENRAGED_INFERNO      = 183778   -- Interrupt!
ENRAGED_FLARE        = 183784

-- Phase transitions
THE_RITUAL           = (TBD)    -- Maze starts (EFFECT_GAINED) / ends (EFFECT_FADED)
BREAKDOWN_RED        = (TBD)    -- Split red clone
BREAKDOWN_GREEN      = (TBD)    -- Split green clone
BREAKDOWN_BLUE       = (TBD)    -- Split blue clone
```
OSI corner icons (world coordinates from SEH):
```
GREEN corner: [196570, 30199, 38049]
RED corner:   [200014, 30199, 44150]
BLUE corner:  [203417, 30199, 38080]
```
Calamity timers (from SEH data): first Calamity CD and recurring Calamity CD (check SEH data file).
Split HP tracking: all three clones named "Ansuul the Tormentor" — differentiate by buff
(`ansuul_red_split_breakdown`, `ansuul_green_split_breakdown`, `ansuul_blue_split_breakdown`).

- [ ] Poisoned Mind: CombatAlerts green border on player
- [ ] Manic Phobia: OSI player icon
- [ ] Wrack: cast bar / kite alert
- [ ] Calamity: countdown timer + alert when imminent
- [ ] Sunburst: alert
- [ ] Enraged Inferno: interrupt alert
- [ ] The Ritual (maze): phase entry/exit alert + timer
- [ ] Breakdown: show colored clone HP (via combat event damage accumulation + reticle-over check)
- [ ] OSI corner icons (green/red/blue positions)
- [ ] Enraged Fragment: target marker on `"Enraged Fragment"` units

#### SE-5 — In-game verification
- [ ] Confirm zone ID = 1427 matches the correct zone (verify with `GetUnitZoneByIndex`)
- [ ] Real Location bounds — stand at room corners: `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
- [ ] HM thresholds for all three bosses: `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`
- [ ] Breakdown ability IDs (`ansuul_red/green/blue_split_breakdown`) — read SEH main data file
- [ ] Chimera crystal number icon coordinates — read SEH data file
- [ ] Calamity cooldown values — read SEH data file
- [ ] Chimera despawn CD and Chain Lightning CD — read SEH data file

---

## In-game verification backlog
(Items requiring a live ESO session)

### All new trials
- [x] Zone ID for CR — 1051 ✓ confirmed in-game
- [x] Zone ID for LC — 1478 ✓ confirmed in-game
- [x] Zone ID for OC — 1548 ✓ confirmed in-game
- (AS=1000, SE=1427, KA=1196, RG=1263, DSR=1344, SS=1121 — vintage-plausible, treat as confirmed until a misfire is reported)
- [ ] Boss name strings for `BossRegistry.nameAliases` in each trial's Factory
- [ ] Real Location bounds for AS, CR, LC, OC, SE — stand at boss room corners and run:
      `/script local x,y,z,_ = GetUnitWorldPosition("player"); d(x..","..y)`
      Record min/max x/z at each corner; y is the floor plane.

### KA
- [ ] OSI floor icon world coordinates: connection nodes (×8), blood fountains, torturer walk spots

### RG
- [ ] Real Location bounds for zone detection
- [ ] HM thresholds: Bahsei, Oaxiltso, Xalvakka
- [ ] Xalvakka shield event params + first-jump timing

### DSR
- [ ] Real Location bounds
- [ ] All boss mechanics (no reference addon found)

### OC
- [ ] dragon_max_hp on non-HM vet (242,176,464 confirmed for HM from OCH)
- [ ] Portal-phase ability IDs for Jynorah

### SS
- [ ] Recalibrate `isGroupMemberNearby` threshold for Yolna (was 2.8 on old normalised scale) — [#29](https://github.com/oseias-pt/incha/issues/29)
- [ ] Recalibrate `isGroupMemberNearby` threshold for Lokke (was 4.5 on old normalised scale) — [#30](https://github.com/oseias-pt/incha/issues/30)
- [ ] Recalibrate `isGroupMemberNearby` threshold for Nahvii (was 7.0 on old normalised scale) — [#31](https://github.com/oseias-pt/incha/issues/31)

### SE
- [ ] Breakdown split-clone ability IDs
- [ ] Chimera crystal icon coordinates (normal + HM)
- [ ] Calamity first/recurring cooldown values

---

## Open architecture questions

1. **`core/` must not depend on `ui/`** — currently `core/Trial.lua` does
   `require("ui.Bridge")`, which inverts the dependency layer.  `Bridge` is a
   pure interface (no WINDOW_MANAGER calls, no UI state) and belongs in core.
   Fix: move `ui/Bridge.lua` → `core/Bridge.lua`; update the two callers:
   `core/Trial.lua` and `ui/Panel.lua` both `require("core.Bridge")`.
   Update `incha.txt` accordingly (remove `ui/Bridge.lua`, add `core/Bridge.lua`
   in the core block before `core/Trial.lua`).

2. **Module-level mutable state in `*Common` files**: `OsseinCageCommon._carrionStacks` and
   `_toxicIreLastMs` are module-level upvalues. They survive wipes and re-entries within
   a session — any code path that reads them between a wipe and the next `EFFECT_FADED`
   shows stale data. Pattern: move shared counters into a `Trial`-context object or export
   a `reset()` function called from each boss's `onWipe`. Same audit recommended for
   `SunspireCommon` and `RockgroveCommon` if they carry mutable upvalues.

3. **AS/CR concurrent-boss model**: both trials have multiple simultaneous boss entities.
   We need either (a) a compound module that handles all entities internally, or
   (b) a small extension to `Trial` that supports multiple "active" bosses.
   Option (a) is lower risk and doesn't change the existing API.

2. **`modulesToUnload` drift**: each new trial added without updating this list extends
   the session-lifetime leak. Consider auto-deriving from Factory `require` calls (Phase 0).

3. **Zone ID discovery**: for trials without a known ID, stand inside the trial
   zone and run:
   ```
   /script d(GetZoneId(GetUnitZoneIndex("player")))
   ```
   The result is the zone **ID** (decimal integer) that goes in the Factory
   `zoneId` field — this is what `ZoneManager.getPlayerZoneId()` compares
   against.  Note: `GetCurrentMapZoneIndex()` returns a different number (the
   zone *index*, not the ID); do not use that for Factory values.

4. **OSI dependency**: SE and LC use OSI extensively. Ensure `## OptionalDependsOn: OdySupportIcons`
   remains in `incha.txt` (already present) and all OSI calls are nil-guarded.

---

## HM thresholds — shipped trials  (in-game measurement required)

The following bosses are implemented (mechanics complete) but `hmHealthThreshold` is
still `math.huge` or a placeholder `100000001`.  Until the correct value is supplied,
`detectDifficulty()` always returns `NORMAL`, silently skipping HM-specific alerts.

**How to measure:**  Pull on Vet HM → `/script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))`

| Boss file | Current value | Trial |
|---|---|---|
| `trial/cr/boss/ZmajaEncounter.lua` | `math.huge` | Cloudrest — Z'Maja |
| `trial/as/boss/OlmsEncounter.lua` | `math.huge` | Asylum Sanctorium — Saint Olms / Llothis / Felms |
| `trial/dsr/boss/Lylanar.lua` | `100000001` (placeholder) | Dreadsail Reef boss 1 (Lylanar / Turlassil) |
| `trial/dsr/boss/Taleria.lua` | `100000001` (placeholder) | Dreadsail Reef boss 3 |
| `trial/dsr/boss/ReefGuardian.lua` | `100000001` (placeholder) | Dreadsail Reef boss 2 |
| `trial/lc/boss/DarielEncounter.lua` | `math.huge` | Lucent Citadel — Dariel |
| `trial/lc/boss/XynizataEncounter.lua` | `math.huge` | Lucent Citadel — Xynizata |
| `trial/oc/boss/JynorahEncounter.lua` | `math.huge` | Oathsworn Pit — Jynorah |
| `trial/oc/boss/KazpianEncounter.lua` | `math.huge` | Oathsworn Pit — Kazpian |
| `trial/oc/boss/ShaperEncounter.lua` | `math.huge` | Oathsworn Pit — Shaper of Flesh |

---

## Proximity threshold recalibration  (in-game measurement required)

`lib/MapUtils.lua` was rewritten in `fix/maputils-world-position` to use
`GetUnitWorldPosition` instead of the normalised-map-coordinate API.  The threshold
values in the three callers below were calibrated for the old `normalised-map × 1000`
scale and **must be recalibrated** in world units before the new implementation is
production-ready:

| Caller | Old threshold |
|---|---|
| `trial/ss/boss/Yolna.lua` | 2.8 |
| `trial/ss/boss/Lokke.lua` | 4.5 |
| `trial/ss/boss/Nahvii.lua` | 7.0 |

---

## Settings granularity  (design + implementation)

The current settings panel exposes a single global on/off toggle.  Finer control
would let players enable only the trials or bosses they care about:
- Per-trial toggles (disable all CR alerts while progging elsewhere)
- Per-boss toggles within a trial
- Per-mechanic category toggles (disable HM-only alerts in normal mode)

## Panel flexible line count  (UI)

The info panel renders a fixed number of lines regardless of content.  A
variable-height panel that shows only populated lines would reduce clutter for bosses
with few active timers.

## i18n / Localisation layer  (architecture)

All user-visible strings are hard-coded in English.  To support other locales:
- Create `lang/en.lua` with all NPC name strings, alert labels, and action strings
- Create `lang/de.lua`, `lang/fr.lua` etc. sourced from ESO reference addons
- Create `core/Lang.lua` loader: reads `GetCVar("Language.2")`, requires the
  matching `lang/<code>.lua`, falls back to `en` for any missing key
- Replace all hardcoded NPC name strings in boss files **and** in
  `BossRegistry.nameAliases` with `Lang.*` key lookups
- Replace alert/action string literals in all encounter modules with `Lang.*` keys
