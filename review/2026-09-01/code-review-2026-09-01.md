# Incha — External Code Review

| | |
|---|---|
| Repository | `sternnick/incha` (local clone `/tmp/incha`) |
| Commit reviewed | `66977e3` — *fix: trial-mechanics review fixes (MapUtils, Nahvii, HealthRules, harness stubs)* |
| Branch | `fix/mechanics-review-fixes` (1 commit ahead of `origin/master`, working tree clean) |
| Date | 2026-09-01 |
| Reviewer | pi / sternnick (automated + manual static review) |
| Mode | **Read-only. No tracked file in the repository was modified.** This document and the scripts in `.review/` (gitignored via `.gitignore:19`) are the only additions. |

---

## 1. Scope and method

Reviewed by reading the code and by running reproducible static checks — not by sampling.

Read in full: `bootstrap.lua`, `incha.lua`, `incha.txt`, all 13 files under `core/`, all 8 under `lib/`, all 3 under `ui/`, all 9 `trial/*/Factory.lua`, all 5 `*Common.lua`, `README.md`, `ROADMAP.md` (903 lines), `test/README.md`, plus `trial/ka/boss/Falgravn.lua`, `trial/ss/boss/Lokke.lua`, `trial/oc/*` and `trial/lc/LCCommon.lua` in detail.

Executed (see `.review/run.sh`, all read-only, stdlib Python + optional `luaparse`):

| Check | Result |
|---|---|
| Byte-order-mark scan, all `.lua`/`.txt`/`.md` | **FAIL — 9 files** |
| Syntax parse of all 69 `.lua` files (Lua 5.1/5.2/5.3 grammar) | **FAIL — the same 9 files, all at 1:1** |
| `incha.txt` ↔ disk (missing / never-loaded / duplicate entries) | PASS — 65 files, exact match |
| Load-order simulation (every `require()` target precedes its consumer) | PASS |
| Module self-registration name vs file path | PASS |
| ~370 `combatRoutes`/`effectRoutes` entries vs both `CombatHandler` dispatch shapes | PASS — 0 mismatches |
| Settings keys written by the LAM panel but never read | **FAIL — `showBossUI`** |
| `hideAction` vs `action` text-cache symmetry | **FAIL** |
| Global control naming vs addon name | WARN — `InchPanel` |
| HM thresholds | WARN — 7 × `math.huge`, 5 × `100000001` |
| Proximity threshold unit scale | WARN — 3 call sites |
| Version-string consistency | NOTE — 3 different values |
| Documentation drift assertions | NOTE — 6 contradictions |
| Duplicate-commit history scan | NOTE — 42 messages appear twice, 57 merges / 204 commits |
| Declared ability IDs that no route table ever uses | **WARN — 16 IDs** |
| `context.isHM` gates vs. placeholder thresholds | WARN — 42 gates in 4 modules |
| `CA.castAlertsStart` handles discarded (bar cannot be stopped) | WARN — 6 sites |
| `zo_callLater` handles discarded (not cancellable) | NOTE — 8 sites, all triaged benign |
| `local function` forward references (would bind `nil`) | PASS — none in 69 files |
| `test/run_log.lua` zone map + boss order vs. `incha.lua`/Factories | PASS — exact match, 9/9 |
| Instability frame assets vs. `INST_FRAMES` / `%02d` path format | PASS — `frame_01…frame_40` |

All 22 checks are in `.review/checks.py`; `boss-inventory.md` is a generated per-boss table (`inventory.py`), and `patches/` holds the suggested fixes as `git am`-able commits (verified in `patch-verification.txt`).

Codebase shape for reference: 69 Lua files, ~11.9 k lines (`lib` 366, `core` 1026, `ui` 816, `trial` 8509, `test` 1051), 9 registered zones, 25 boss modules, ~410 ability-ID constants, 370 declared routes.

Every finding below is labelled **CONFIRMED** (evidence in this repo, reproducible with `run.sh`) or **UNVERIFIED** (needs one in-game session or the current ESO API docs; a probe is provided). Nothing is presented as fact without evidence.

---

## 2. What is solid — please do not "fix" these

Stated so the follow-up work is aimed at the right places. Each item was verified, not inferred.

* **Module system.** ESO exposes no `require`/file I/O; `bootstrap.lua` implements a lookup-only shim and every module self-registers. Load order in `incha.txt` is therefore the whole contract — and it is currently correct for all 65 files, including the 12-file core block before `ui/` and `core/Trial.lua`.
* **Mechanic dispatch.** `core/CombatHandler.lua` separates routing (data) from behaviour (functions), with a `common` handler short-circuit and a legacy fallback. All 370 route entries agree with their dispatch shape — the `handleReflective` parameter-order bug (ROADMAP P0) has not recurred anywhere.
* **Failure isolation.** `EventPipeline:enable` wraps every ESO callback in `pcall` (`core/EventPipeline.lua:23-30`); `disable` unregisters everything unconditionally. A broken boss module cannot take the client down.
* **Hot-path discipline.** `Throttle` bucketing on health percent, `_staticText` precompilation in `HealthRules.register`, `SetText` diffing in `Panel`, `AlertSink:emit` returning plain values instead of a payload table, `context.inCombat` instead of a C round-trip. Coherent and deliberate.
* **Optional dependencies.** All 26 `OSI.*` call sites are behind `if OSI` / `OSI and` / early-return guards; `CombatAlerts` access is funnelled through `lib/CA.lua`. Matches the rule stated in `README.md`.
* **Lifecycle contract.** `onEnter` / `onCombatState` / `onWipe` / `onLeave` are documented in one place (`core/Trial.lua:13-43`) and consistently implemented, including "keep long-lived position icons across a wipe, discard on zone exit".
* **Defensive UI.** `AlertSink:showInfo(n, …)` ignores out-of-range slots; `Panel` handles are built once and never rebuilt per event.
* **Encoding hygiene (partial).** No `aEUR`-style mojibake remains anywhere, and no `.lua`, `.txt` or `.md` file uses CRLF or tabs for indentation — the 9 BOMs in F-01 are the only encoding defect.
* **No nil-call class bugs.** Every one of the 69 files was swept for a call site that precedes its own `local function` declaration (Lua binds `nil` there, and `ROADMAP.md` shows the team already hit this once and left a comment about it). Zero occurrences.
* **Borders always expire.** All 13 `CA.border(true, …)` call sites pass an explicit duration, so a missed `border(false)` cannot leave a stuck screen tint — this was checked precisely because nine boss modules have no `onLeave` (see F-25).
* **Harness and addon agree.** `test/run_log.lua` `TRIAL_CONFIG` matches `incha.lua:25-33` on all nine zone IDs and reproduces every Factory's boss order exactly, so offline log replays exercise the same graph as the game.
* **Asset/code agreement.** `resources/instability/` holds exactly `frame_01…frame_40`, matching `INST_FRAMES = 40` and the `"Incha/resources/instability/frame_%02d.dds"` format string.

---

## 3. Findings

Severity: **S1** breaks a trial at load/runtime · **S2** wrong behaviour in live content · **S3** edge-case correctness or misleading state · **S4** documentation / hygiene.

### F-01 · S1 · CONFIRMED — Nine source files start with a UTF-8 BOM

```
trial/as/boss/OlmsEncounter.lua   trial/lc/boss/OrphicEncounter.lua
trial/cr/boss/ZmajaEncounter.lua  trial/lc/boss/RyelazEncounter.lua
trial/lc/boss/DarielEncounter.lua trial/lc/boss/XynizataEncounter.lua
trial/lc/boss/XorynEncounter.lua  trial/oc/boss/KazpianEncounter.lua
                                trial/oc/boss/ShaperEncounter.lua
```

Evidence
* Bytes `EF BB BF` at offset 0 (`file(1)`: "Unicode text, UTF-8 (with BOM) text"); `luaparse` rejects each at `1:1`.
* Introduced by `a4e2942` (2026-08-25, *"Refactor R3: replace Location.new(0,0,0,0,0,0) with nil — 13 boss files"*).
* Contradicts `ROADMAP.md:35` — *"re-saved as UTF-8 without BOM"* — and `ROADMAP.md:36`, which lists `ZmajaEncounter.lua` as "already clean".

Why it matters
A BOM is not part of Lua's grammar. ESO does not use `luaL_loadfilex`; it reads the file and compiles the body itself. If its compiler does not skip those three bytes, each of these files fails to parse at line 1, never executes `package.loaded[...] = …`, and the next `require` of it raises `require('trial.lc.boss.XorynEncounter'): module not registered` (`bootstrap.lua:29-33`). Because the Factory requires its bosses at load time, one bad file disables **the whole trial**: LC loses 5/5 bosses, OC 2/3, AS 1/1, CR 1/1 — i.e. four trials silently dead with a single chat error. Whether ESO tolerates a BOM is **UNVERIFIED** (external API docs unreachable today); the cleanup is free either way, and the same failure class already bit this project once (`aEUR` mojibake).

Suggested change
```sh
# strip the 3 bytes; git diff should list exactly these 9 files, first line only
for f in trial/as/boss/OlmsEncounter.lua trial/cr/boss/ZmajaEncounter.lua \
         trial/lc/boss/*.lua trial/oc/boss/KazpianEncounter.lua trial/oc/boss/ShaperEncounter.lua; do
    sed -i '1s/^\xEF\xBB\xBF//' "$f"
done
```
And make it impossible to re-introduce: add `check C-01` to `.githooks/pre-push` (already shipped, opt-in) and to CI (§ 5).

Note: no Lua interpreter exists in this environment, so the log-replay harness could not be executed here; and even where a Lua file loader tolerates a BOM, the harness would not surface this — the check has to be byte-level.

---

### F-02 · S2 · CONFIRMED — `EVENT_POWER_UPDATE` ignores `unitTag`; boss health can come from any "boss*" unit

Evidence — `core/Trial.lua:71-73` accepts `unitTag` and drops it:
```lua
onPowerUpdate = function(eventCode, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)
    self:onPowerUpdate(powerValue, powerMax)
end,
```
The only filters registered are power type and unit-tag **prefix** `"boss"` (`core/EventPipeline.lua:36-39`). `Trial:onPowerUpdate` (`core/Trial.lua:158-174`) then writes `self.context.healthPercent` from whichever unit fired and evaluates `boss.healthRules` against it.

Impact — in rooms with concurrent boss-tagged units (LC `Ryelaz`+`Zilyesset`, AS Olms + Llothis/Felms, CR, OC, and any add that carries a `bossN` tag), HP-percent milestones and `context.healthPercent` can be driven by the wrong entity. `trial/ss/boss/Lokke.lua:302` (`showLaserLandingLine`) reads `context.healthPercent` for the "Can Fly In" line, so the number shown can belong to a different unit.

Suggested change — carry the matched slot through detection and gate on it:
```lua
-- core/Trial.lua, onPowerUpdate pipeline entry
onPowerUpdate = function(eventCode, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)
    self:onPowerUpdate(unitTag, powerValue, powerMax)
end,

-- core/Trial.lua, Trial:onPowerUpdate
function Trial:onPowerUpdate(unitTag, powerValue, powerMax)
    ...
    local boss = self:getActiveBoss()
    if not boss then return end
    if self.activeBossUnitTag and unitTag ~= self.activeBossUnitTag then return end
```
`activeBossUnitTag` is set in `onBossesChanged` (see F-03, same slot). If position-based detection supplied no slot, fall back to the current behaviour so nothing regresses.

---

### F-03 · S2 · CONFIRMED — hardmode detection always reads `boss1`

Evidence — `core/Trial.lua:123-141`: detection iterates `boss1`–`boss4` by name, but difficulty is taken from a fixed slot:
```lua
local _, _, effectiveMax = GetUnitPower("boss1", POWERTYPE_HEALTH)
self.context:setDifficulty(self.registry:detectDifficulty(bossClass, effectiveMax))
```
Same pattern in `trial/ka/boss/Falgravn.lua:469` and `:471` (`GetUnitName("boss1")` for the `[HM: ON]` header).

Impact — when the registry matches `boss2`/`boss3`/`boss4` (the loop's own comment cites Ryelaz+Zilyesset), `isHM` and the header name describe a different unit.

Suggested change — record the slot alongside the class and expose it on the context:
```lua
-- onBossesChanged, inside the name loop
if candidate then bossClass = candidate; matchedSlot = slot; break end
...
-- after the instance is created
self.activeBossUnitTag = matchedSlot
self.context.bossUnitTag = matchedSlot or "boss1"
local _, _, effectiveMax = GetUnitPower(self.context.bossUnitTag, POWERTYPE_HEALTH)
```
`TrialContext` already carries `bossId`/`bossKey`; one more field keeps boss modules from hard-coding slots. `trial/ka/boss/Falgravn.lua:469` then becomes `GetUnitName(context.bossUnitTag)`.

---

### F-04 · S2 · CONFIRMED — hardmode detection is non-functional for 12 of 25 bosses

`hmHealthThreshold` is `math.huge` in 7 modules (`trial/as/boss/OlmsEncounter.lua`, `trial/cr/boss/ZmajaEncounter.lua`, `trial/lc/boss/DarielEncounter.lua`, `trial/lc/boss/XynizataEncounter.lua`, `trial/oc/boss/{Jynorah,Kazpian,Shaper}Encounter.lua`) and the placeholder `100000001` in 5 (`trial/dsr/boss/{Lylanar,ReefGuardian,Taleria}.lua`, `trial/rg/boss/{Bahsei,Xalvakka}.lua`). `BossRegistry:detectDifficulty` (`core/BossRegistry.lua:61-71`) therefore returns `NORMAL` forever for those 7, and for the 5 placeholders the boundary is an unmeasured guess. This is already tabulated in `ROADMAP.md:841-862`; it is listed here because nothing in the code or CI makes the gap visible — only the ROADMAP table does.

Suggested change — two mechanical aids rather than a code change:
1. Have `Trial:enable()` `Log.warn` once per zone-enter when `hmHealthThreshold` is `math.huge` or the known placeholder, so the gap is visible during normal play and normal logs.
2. Add a debug slash command (`/incha hp`) that prints `GetUnitMaxPower(context.bossUnitTag, POWERTYPE_HEALTH)` at pull, i.e. automate the "how to measure" step already written in `ROADMAP.md:847`.

---

### F-05 · S2 · CONFIRMED (impact) — Sunspire proximity alerts cannot fire

`lib/MapUtils.lua:5-17` was rewritten to measure `GetUnitWorldPosition` distance, and its own header says callers "must be recalibrated (see GitHub issues #29, #30, #31)". The three call sites still pass pre-rewrite values:

| Call site | Threshold now interpreted as world units |
|---|---|
| `trial/ss/boss/Yolna.lua:106` | 2.8 |
| `trial/ss/boss/Lokke.lua:230` | 4.5 |
| `trial/ss/boss/Nahvii.lua:173` | 7 |

For scale, the arena geometry already in the repo (`trial/ka/boss/Falgravn.lua:67-107`) spans thousands of world units between wall and boss. A 2.8-unit radius is sub-collision; the "Block! (Glacial Fist)"-style alerts will fire only for `AreUnitsEqual("player", unitTag)` and never for group members.

Suggested change — measure once, then make the unit explicit and self-guarding:
```lua
-- in-game, stand next to a group member at the range you want to warn about:
/script local _,x1,_,z1 = GetUnitWorldPosition("player")
        local _,x2,_,z2 = GetUnitWorldPosition("group1")
        d(math.sqrt((x1-x2)^2 + (z1-z2)^2))
```
```lua
-- lib/MapUtils.lua
function MapUtils.isGroupMemberNearby(unitTag, thresholdWorldUnits)
    if IsDeveloperModeEnabled and Log.isEnabled() and thresholdWorldUnits < 50 then
        Log.warn("isGroupMemberNearby: threshold %g looks like a pre-rewrite value", thresholdWorldUnits)
    end
```
Also worth noting: `MapUtils.isGroupMemberNearby` computes a `sqrt` on a hot path (per Glacial Fist/Fog event); comparing squared distance against `threshold * threshold` avoids it.

---

### F-06 · S2 · CONFIRMED — `showBossUI` is a write-only setting in all nine trials

* Declared in `core/Settings.lua:34` and `:39-46`.
* Exposed as nine LAM checkboxes (`ui/Menu.lua:91-92`, `132-133`, `151-152`, `170-171`, `190-191`, `217-218`, `244-245`, `271-272`, `291-292`).
* Read by **nothing** — verified mechanically (`checks.py` C-06 scans every `.lua` outside `Settings.lua`/`Menu.lua`; the only other occurrence is the harness's own defaults table at `test/harness/eso_api.lua:232`).

Consequence: the header line that `ui/Panel.lua:1-15` documents as "boss name / HM status" is only ever written by six call sites in three trials (`trial/se/boss/ChimeraEncounter.lua:105`, `trial/se/boss/AnsuulEncounter.lua:77` and `:148`, `trial/ka/boss/Falgravn.lua:469`/`:471`, `trial/cr/boss/ZmajaEncounter.lua:427`) for phase call-outs (and `ui/Panel.lua:183` documents the info slots as 1-7). On a normal boss transition the header is empty for all nine trials, and the checkbox the user toggles has no effect.

Suggested change — pick one, do not leave it as-is:
1. **Implement it** in `Trial:onBossesChanged` right after `self.context:setBoss(instance)`:
   ```lua
   if Settings.trial(self.id).showBossUI then
       self.alerts:showHeader((bossClass.name or (bossClass.nameAliases and bossClass.nameAliases[1]) or bossClass.key))
   end
   ```
   Interactions to accept deliberately: SE/CR/OC phase call-outs overwrite it (that is the desired precedence), and it must be set only on an actual boss change, not on every `BOSSES_CHANGED`.
2. **Delete it** from `DEFAULTS.trials` and the nine LAM rows. Safe without a `SCHEMA_VERSION` bump — `ZO_SavedVars` deep-merges defaults, and a stored-but-absent-from-defaults key is simply ignored (per the comment at `core/Settings.lua:16-17`).

---

### F-07 · S3 · CONFIRMED — no `alerts:clear()` on a boss→boss transition

`Trial:onBossesChanged` (`core/Trial.lua:101-156`) calls the outgoing boss's `onLeave` (`:107-112`), then, if a new boss class is found, immediately installs it. `self.alerts:clear()` appears only in the "no boss found" branch (`:152`) and in `Trial:disable` (`:254`).

Impact — in rooms where the boss list changes directly from one matched entity to another (concurrent-entity content: LC, AS, CR, OC), `header` text from the previous encounter ("TRIPLET PHASE!", "Maze phase!", "Shadow Realm - Group 2") and any info lines the new boss does not immediately rewrite stay on screen until the new encounter overwrites them.

Suggested change
```lua
if self.activeBoss then
    if self.activeBoss.onLeave then self.activeBoss:onLeave(self.context) end
    self.activeBoss = nil
    self.alerts:clear()          -- header + info lines are per-encounter
end
```
(`Panel.alerts.clear` deactivates the panel; it becomes visible again on the first `header`/`info`/`action` of the new encounter, which happens inside the first 200 ms `onUpdate`. If that flicker is undesirable, split `clear()` into `clearText()` that keeps `ctrl.active`.)

---

### F-08 · S3 · CONFIRMED — `hideAction` desynchronises the `Panel` text cache

`ui/Panel.lua:202-214` skips `SetText` when the cached string is unchanged:
```lua
action = function(text)
    ...
    if ctrl.actionText ~= s then
        ctrl.actionText = s
        ctrl.action:SetText(s)
    end
```
`ui/Panel.lua:215-219` clears the control but not the cache:
```lua
hideAction = function()
    if not ctrl then return end
    ctrl.action:SetText("")
    -- leave panel visible  -  info lines may still carry timer data
end,
```
Reachable path: `core/Trial.lua:186-192` calls `alerts:hideAction()` on every 1 % health bucket change where no health rule matches and `boss.hideActionWhenNoRule` is set (`true` for Falgravn, `trial/ka/boss/Falgravn.lua:242`). Sequence `showAction("Move!")` → `hideAction()` → later `showAction("Move!")` ⇒ the diff check suppresses the `SetText`, and the action line stays blank while the panel believes it is displaying. The same asymmetry exists in `panel_clear` (`:65`) — that one *does* reset the cache, which is why `clear` is safe and `hideAction` is not.

Suggested change
```lua
hideAction = function()
    if not ctrl then return end
    ctrl.action:SetText("")
    ctrl.actionText = ""      -- keep the cache honest (see panel_clear)
end,
```
`checks.py` C-15 asserts this symmetry so the regression cannot return.

---

### F-09 · S3 · CONFIRMED — per-trial "Enable" only applies on the next zone change

The flag is evaluated once, at enter time (`core/ZoneManager.lua:61-67`). The LAM `setFunc`s write the value and nothing else (`ui/Menu.lua:126`, `:145`, `:164`, `:184`, `:211`, `:238`, `:265`, `:285`; KA has no Enable row). So switching a trial **off** mid-run keeps it running until you leave the zone, and switching it **on** mid-run does nothing until you re-enter. (Overlay toggles do refresh — they call `Panel.refresh()`.)

Suggested change — one re-evaluation entry point, called from the toggles:
```lua
-- core/ZoneManager.lua
function ZoneManager.refresh()
    local zoneId = getPlayerZoneId()
    local entry  = trials[zoneId]
    if entry and entry ~= activeEntry and activeTrial then
        disableCurrentTrial()
    end
    if entry then
        local sv  = Settings.get()
        local tsv = sv and sv.trials[entry.trialId]
        if tsv and tsv.enabled == false then
            if activeEntry == entry then disableCurrentTrial() end
            return
        end
    end
    enableTrialForZone(zoneId)      -- early-returns when already active
end
```
```lua
-- ui/Menu.lua, every "Enable" row
setFunc = function(v) Settings.get().trials.ss.enabled = v; ZoneManager.refresh() end
```

---

### F-10 · S3 · UNVERIFIED — global control name `InchPanel`

`ui/Panel.lua:80` — `WINDOW_MANAGER:CreateControl("InchPanel", GuiRoot, CT_CONTROL)`. ESO restricts the global control names an addon may create to its own name; `ADDON_NAME = "incha"` / `ADDON_TITLE = "Incha"` (`bootstrap.lua:15-19`), and `InchPanel` is neither. The usual outcome is an error/warning at startup and a control that is not exposed globally. Flagged UNVERIFIED because the authoritative statement should come from an in-game `/reloadui`, not from this reviewer.

Suggested change: `"Incha_Panel"` (one line; `checks.py` C-14 now asserts the prefix for every named control).

---

### F-11 · S3 · UNVERIFIED — `EVENT_COMBAT_EVENT` argument list

`core/CombatHandler.lua:10-18` documents (and `:88-91` consumes) this order:
```
eventCode, result, isError, abilityName, abilityGraphic, hitStatus,
unitTag, unitName, sourceUnitTag, sourceUnitName, sourceUnitId, unitId, abilityId, overflow
```
This is the older signature; ZOS has added parameters to this event over the years (and `EVENT_EFFECT_CHANGED`'s `iconName` is a texture object in modern API). We could **not** confirm the current signature from outside the game: the usual API-doc hosts were unreachable (angoulish pages 404, uobo.net timeout, code-search endpoints require auth or a browser checkpoint). If the live signature has extra parameters *before* `unitTag`, every route handler receives shifted arguments — the same class of bug as F-01's silent failure but with a much bigger blast radius. Given that KA is described as feature-complete and validated in-game, the likeliest state is "fine as-is"; it still deserves a two-minute confirmation:

```lua
-- one-shot probe, then /run and hit anything once
/script local h = function(e, ...) for i = 1, 24 do d(i .. ": " .. tostring(select(i, ...))) end end
        EVENT_MANAGER:RegisterForEvent("InchaProbe", EVENT_COMBAT_EVENT, h)
```
Expected: slot 1 = result, then the order listed above. If the dump shows additional values before `unitTag`, `CombatHandler.onCombatEvent` needs the new positions — and `test/harness/log_reader.lua` should be re-checked at the same time, because the harness parses encounter-log columns, not live event arguments.

---

### F-12 · S3 · CONFIRMED — Falgravn's detection box and its floor-icon coordinates disagree

`trial/ka/boss/Falgravn.lua:241` registers the AABB
```lua
Falgravn.location = Location.new(73700, 84500, 6000, 22500, 50200, 61900)
```
while the same file's floor-icon tables (`:67-107`) put connection nodes at x ≈ 22 300–27 800, z ≈ 7 000–13 000 and torturers at y ≈ 7 700. The AABB's y range (6 000–22 500) matches that geometry; its x and z ranges do not contain it. Both cannot be the same coordinate space: either the AABB never matches (detection falls back to the name loop at `core/Trial.lua:123-133`, so nothing appears broken while floor icons are wrong) or the icon coordinates came from another source (the comment says they are inherited from BSCHTKA) and are wrong.

Only KA uses position-based detection at all (`trial/ka/boss/{Yandir,Vrol,Falgravn}.lua` — 3 sites); the other eight trials rely on `name`/`nameAliases`. Note also `core/Location.lua:12-16` uses strict `<`/`>`, so standing exactly on a boundary excludes the boss — harmless with padded boxes, worth a comment.

Suggested change — one in-game pass resolves it (and `ROADMAP.md:773-774` already asks for it): record `GetUnitWorldPosition("player")` at the arena corners, then set the AABB from the *same* source as the OSI node coordinates, and add the measured node coordinates as a comment so the two can never drift apart again.

---

### F-13 · S3 · CONFIRMED — boss detection for five trials depends on localised names

SE, LC, OC (and AS/CR) declare only `nameAliases`, e.g. `KazpianEncounter.nameAliases = { "Overfiend Kazpian" }` (`trial/oc/boss/KazpianEncounter.lua:52`); their own comments say *"may fail on non-EN clients"*. RG/DSR/SS additionally carry `-- TODO: verify exact unit name` on `name` (`trial/rg/boss/Bahsei.lua:68`, `trial/dsr/boss/Lylanar.lua:106`, …). On a non-English client those trials never activate — no error, just nothing.

Suggested change (cheap, and it closes the backlog automatically)
```lua
-- core/Trial.lua, onBossesChanged, after the name loop, inside `if Log.isEnabled() then`
for _, slot in ipairs({"boss1","boss2","boss3","boss4"}) do
    if DoesUnitExist(slot) then
        Log.debug("unmatched slot %s name=%q", slot, GetUnitName(slot))
    end
end
```
Then ask for one German/French log or one debug capture, and store the confirmed strings in the Factory instead of guessing them.

---

### F-14 · S3 · CONFIRMED — the test harness cannot see most of the risk surface, and there is no CI

* `test/README.md` documents the stubs honestly: `zo_callLater` **does not execute callbacks**, `GetUnitWorldPosition` returns `(0,0,0,0)`, `IsUnitInCombat` is always `false`, `CombatAlerts`/`OSI` are `nil`. Deferred paths are therefore untested: Falgravn's icon creation (`trial/ka/boss/Falgravn.lua:398-404`, 3.1 s delay), its HM reset (`:472-474`), Lokke's `laserResetTimer` (`trial/ss/boss/Lokke.lua:211-218`).
* Phase 1 asserts nothing ("run-without-errors"); the Phase 2 snapshot/coverage plan in `test/README.md` is not implemented.
* `.github/` contains only `CODEOWNERS` — no workflow. The single existing guard is `.githooks/pre-push`, which enforces branch naming only and is opt-in (`git config core.hooksPath .githooks`, per `README.md`).

Suggested change: add CI (§ 5) with the checks in this folder, and give the harness a `zo_callLater` that runs callbacks against the simulated clock (the runner already advances `GetGameTimeMilliseconds`) — that alone turns a large class of untested code into tested code. The snapshot idea in the README is the right Phase 2; the per-ability coverage counter is the one that will actually find dead IDs.

---

### F-15 · S4 · CONFIRMED — nearly every change exists twice in history

204 commits, 57 merges, 42 commit messages appearing more than once. The pattern is a pair of independent commits with the same message, both merged: `674262a`/`1493a64`, `0123e4a`/`5ffc191`, `ad72e85`/`3b196b1`, `46e6792`/`67ad2af`, `80f3cee`/`0bfdad5`, `b5e533c`/`5ebb397`, `9936709`/`8afa6ad` (Appendix D has the full set). Trees are consistent (the merges are clean, `git show` of a merge is empty), so nothing is corrupted — but `bisect` and `blame` pick an arbitrary one of the two, and two independent authors making the same fix is a workflow smell (most likely the same change produced twice and merged twice, which is exactly how conflicting duplicate edits eventually appear).

Suggested change: fix the flow rather than rewrite history. One branch = one author of the change; the branch is merged, never re-committed onto `master`. If the double-authoring is deliberate (agent + human), make it visible with a trailer so deduplication is possible (`Co-authored-by:`), and consider `git log --first-parent` in tooling.

---

### F-16 · S4 · CONFIRMED — documentation contradicts the code in six places

| Where | Claim | Reality |
|---|---|---|
| `README.md:12-16` | AS / CR / SE / LC / OC "📋 Planned" | Routed modules exist for all of them; `trial/cr/boss/ZmajaEncounter.lua` alone is 637 lines with 43 routes |
| `README.md:101` | `trial/<id>/Dispatcher.lua` | Layer removed (commit *"refactor: remove Dispatcher layer…"*) |
| `README.md:35` | "folder must be named `incha` — the manifest requires it" | Nothing in `incha.txt` requires it; `bootstrap.lua:15` sets `ADDON_NAME` and `incha.lua:36` compares against it |
| `ROADMAP.md:35-46` | files re-saved "without BOM" | 9 files have one (F-01) |
| `ROADMAP.md:90` and `ui/Panel.lua:36` | Panel renders `info1–3` and is 200 pt tall | `ui/Panel.lua:37-38`: `INFO_LINE_COUNT = 10`, `local W, H = 320, 260`; bosses write lines 1–7, `ui/Panel.lua:183` documents 1-7 |
| `ROADMAP.md:217`, `:327`, `:418` | "zoneId = TBD" for CR / LC / OC | Registered as 1051 / 1478 / 1548 in `incha.lua:30`, `:32`, `:33`, and marked "confirmed in-game" at `ROADMAP.md:763-766` |

Also: `ROADMAP.md:801-808` ("Open architecture questions" #1) still describes the `core → ui.Bridge` inversion that has since been fixed (`core/Bridge.lua` exists, `ui/Bridge.lua` does not, `incha.txt` lists `core/Bridge.lua`), and the numbered list restarts at 2 (two items numbered 2, two numbered 3).

And the trial-name inconsistency, which matters because it appears in user-facing places: `test/README.md:74-78` labels zone 1000 as "Aetherian Archive (AS)", 1051 as "Cradle of Shadows (CR)" and 1548 as "Oathsworn Pit (OC)", while `README.md:12-16`, `ROADMAP.md:161/217/327/418` and the module name `OsseinCageCommon` say Asylum Sanctorium / Cloudrest / **Ossein** Cage. `ROADMAP.md:858-860` then calls OC "Oathsworn Pit". Please pick one set of display names — the zone IDs are a separate question (Appendix C-1) and the in-game confirmations recorded in the ROADMAP are the best evidence available.

---

### F-17 · S4 · CONFIRMED — three different version strings

`incha.txt:3` `## Version: 0.0.1` · `incha.lua:51` `v0.1.0 loaded` · `ui/Menu.lua:24` `version = "0.1.0"`. Suggest deriving both strings from a single `ADDON_VERSION` in `bootstrap.lua` (the file already centralises identity, `bootstrap.lua:11-24`) so the LAM panel, chat line and manifest cannot drift.

---

### F-18 · S4 · CONFIRMED — five `stateSchema` entries are `= nil`, i.e. no-ops

`trial/rg/boss/Oaxiltso.lua:62-63` (`sludgeTracker1Tag`, `sludgeTracker1Name`), `trial/oc/boss/KazpianEncounter.lua:66-67` (`chainedA`, `chainedB`), `trial/oc/boss/JynorahEncounter.lua:78` (`playerCurse`). In a Lua table constructor, `k = nil` stores nothing, so `BossBase.fromSchema` (`lib/BossBase.lua:25-31`) cannot create the field. The behaviour is harmless (fresh instances; readers tolerate nil), but `ROADMAP.md:24-27` records these as P1 fixes — and the ROADMAP wording ("Added both with `nil` value … to `stateSchema`", `ROADMAP.md:25`) is accurate about the edit while implying an effect. Two related points:
* Prefer an explicit sentinel that survives the table, e.g. `chainedA = false` — the convention already used elsewhere in the same files (`trial/ka/boss/Falgravn.lua:285` `prisonBarId = false`, `:283` `alertList = function() return {} end`).
* `JynorahEncounter.playerCurse` is assigned at `:158`, `:167` and cleared at `:289` but **never read** — either it feeds a display that was not finished, or it is dead state.

---

### F-19 · S4 · CONFIRMED — the module-unload machinery is documented more strongly than it behaves

`core/ModuleLoader.lua:34-42` says clearing `package.loaded` makes modules "eligible for garbage collection". In practice `BossRegistry.new` (`core/BossRegistry.lua:6-20`) keeps every boss class, the `Trial` objects live forever in `ZoneManager.trials`, and the boss instances keep module-level upvalues alive. `ROADMAP.md:51-60` describes this correctly and defers it; only the code comment overstates. Suggest rewording the comment and, if the memory baseline matters, doing the `collectgarbage("count")` experiment already listed as an open Phase-0 item (`ROADMAP.md:61-62`).

Related: keeping per-encounter state in module upvalues is the deliberate pattern in `trial/ka/boss/Falgravn.lua:29-31`/`:121-123` (`_posIcon*`, `_instAnim`) and is the same pattern that produced the OC `_carrionStacks` wipe bug (fixed via `OsseinCageCommon.reset()`). `ROADMAP.md:811-816` already recommends auditing `SunspireCommon`/`RockgroveCommon`; grep confirms neither currently holds a mutable upvalue (module-level mutable state in `trial/` exists only in `trial/oc/OsseinCageCommon.lua:42`/`:46` and `trial/ka/boss/Falgravn.lua:29-31`, `:121-123`), so the audit result is "clean" — worth recording in the ROADMAP so nobody repeats it.

---

### F-20 · S4 · CONFIRMED — 17 `TODO` markers ship in boss modules

`grep -w TODO trial` → 17, all of them the in-game verification backlog (HM pools, unit names, first-jump timings, `ATTRIBUTE_VISUAL_POWER_SHIELDING`). That is legitimate work-in-progress, but it is duplicated between code comments and `ROADMAP.md` and therefore drifts. Suggest one canonical location (the ROADMAP table or GitHub issues) and code comments that reference the issue number — which the project already does well for #29-#31.

---

### F-21 · S3 · CONFIRMED — 16 declared ability IDs are never routed, so those mechanics can never alert

`checks.py` C-17 classifies every unused UPPER-CASE constant by whether its numeric ID appears elsewhere in the same file. 16 IDs appear **nowhere** except their own declaration — the mechanic is documented, measured, and has no route:

| File | Lines | IDs | Mechanic (from the comment) |
|---|---|---|---|
| `trial/cr/boss/ZmajaEncounter.lua` | 67, 96-98, 100-101 | 103765, 105339, 105363, 105373, 106023, 105291 | Gale Hoarfrost AoE, Malevolent Bead tick/spawn/charge, Break Amulet, Malicious Sphere |
| `trial/dsr/boss/Taleria.lua` | 47-52 | 174679, 169938, 174689, 169936, 174691, 169935 | the three portal debuffs (green/yellow/purple) and their AoEs |
| `trial/dsr/boss/Lylanar.lua` | 61, 77 | 166355, 166364 | pre-Firebrand / pre-Frostbrand telegraphs |
| `trial/dsr/boss/ReefGuardian.lua` | 28 | 165987 | Acid Pool |
| `trial/se/boss/YaseylaEncounter.lua` | 45 | 184802 | Archer True Shot |

This is not a bug — the corresponding ROADMAP phases are open (`ZmajaEncounter.lua:532` still carries the `CR-3 TODO` for the portal/mini-boss world state). It matters because a reader of the *code* sees an ID table and reasonably assumes the mechanic is live. Either route them, or move each block into the ROADMAP section for that boss and delete the constant, so "declared" and "implemented" mean the same thing again.

### F-22 · S3 · CONFIRMED — 42 hardmode branches rest on a boundary nobody measured

`BossRegistry:detectDifficulty` (`core/BossRegistry.lua:61-71`) is a single `>=` against `hmHealthThreshold`. The full inventory of all 25 modules:

| Threshold value | Modules | Verdict |
|---|---|---|
| `math.huge` | Olms, Zmaja, Dariel, Xynizata, Jynorah, Kazpian, Shaper (7) | `detectDifficulty` can never return `HARDMODE` |
| `100000001` | Lylanar, ReefGuardian, Taleria, Bahsei, Xalvakka (5) | guess — mis-detects in *both* directions |
| *field absent* | Lokke (commented out at `:134`), Nahvii, Yolna, Oaxiltso (4) | no HM detection at all; `context.isHM` stays `false` |
| `72 769 370` | Vrol **and** Yandir | measured-precision, but the *same* number for two different bosses — re-measure at least one |
| `248 386 060` | Falgravn | measured-precision |
| round `40/70/80/100 M` | Ryelaz, Chimera, Orphic, Yaseyla, Xoryn, Ansuul (6) | round numbers = estimates |

Where it bites: 42 `context.isHM` / `.difficulty` reads live in exactly the four modules that carry the `100000001` guess — `Lylanar.lua` 16 gates, `Bahsei.lua` 14, `Xalvakka.lua` 7, `Taleria.lua` 5. Those are not cosmetic reads: they select which info lines are drawn and which timers are armed. One wrong constant therefore *silently shows or hides whole mechanics*. F-04 (this document) covers the same ground from the detection side; patch `04-fix-hardmode-measurement-aid` addresses both by making the placeholder loud in chat and adding `/incha hp` to read the real pools in one pull.

### F-23 · S4 · CONFIRMED — 39 unused locals, two of them hiding unimplemented behaviour

`checks.py` C-17b. Two groups matter more than the rest:

* **Seven `*_FIRST_CD` constants are never wired** (`OrphicEncounter.lua:17,19`, `XynizataEncounter.lua:12,14`, `JynorahEncounter.lua:50`, `YaseylaEncounter.lua:48,53`). These are measured *first-occurrence* cooldowns; the handlers arm their timers with the repeating value instead, so the first cast of the pull is announced with the wrong lead time. `trial/ka/boss/Vrol.lua` is the model for how to do this (`Timer:reset(duration)` on the first event).
* **Seven ID-set constants duplicate literals already inline in the route tables** (`ZmajaEncounter.lua:9,17,25`, `Bahsei.lua:38`, `Xalvakka.lua:51,52`). `Bahsei.lua` documents `MT_ATTACK_IDS` as *the* MT-detection mechanism (`:12`, `:143`) while the routing table at `:211-213` uses the three literals directly. Nothing is broken — the filter does happen, via the route table — but a future edit to `MT_ATTACK_IDS` would silently do nothing. Use the constant in the table, or drop it.

The rest are colour palettes (`AnsuulEncounter.lua:39-40`, `YaseylaEncounter.lua:58-59`, `Nahvii.lua:51`), `Falgravn.lua:14` (`ICON_INSTABILITY`, superseded by the animated `frame_%02d` icons), and three timing constants in `OlmsEncounter.lua`/`ZmajaEncounter.lua`.

### F-24 · S3 · CONFIRMED — the settings panel is asymmetric: Kyne's Aegis has no Enable checkbox

`ui/Menu.lua` exposes an "Enable" row for SS (`:126`), RG (`:145`), DSR (`:164`), AS (`:184`), CR (`:211`), SE (`:238`), LC (`:265`) and OC (`:285`). The KA section (`:83-115`) has four rows — `showBossUI`, `showPercent`, `portalIconVrol`, `posIconsFalgravn` — and no Enable row, even though `core/Settings.lua` defines `trials.ka.enabled` and `core/ZoneManager.lua:61-67` honours it. The flagship trial's tracking cannot be switched off from the UI, and the panel's own structure implies a capability the code does not offer. Combined with F-06 (all nine `showBossUI` checkboxes are write-only), the panel currently shows 9 dead checkboxes and is missing 1 live one. Patch `05-feature-live-trial-enable` adds the KA row and makes all nine Enable rows take effect immediately (F-09).

### F-25 · S4 · CONFIRMED (triaged, no action proposed) — nine boss modules implement no `onLeave`

`inventory.py` flags Lylanar plus all five LC and all three OC modules. Checked individually because "missing teardown" is a strong claim: none of them calls `CA.castAlertsStart`, none creates an OSI icon, none registers a delayed bar — they only use `CA.alertCast`, which is a one-shot bar that expires by itself, and `CA.border`, which always carries a duration (see § 2). The real exposure is therefore limited to `Lylanar`'s state flags surviving a zone exit, and those are re-initialised by `onWipe`/`fromSchema` on the next pull. Recorded so that it is *not* "fixed" as if it were a leak — the two things worth doing instead are in F-26.

### F-26 · S3 · CONFIRMED — six persistent cast bars cannot be cancelled

`lib/CA.lua` `CastAlertsStart` returns a handle for exactly this purpose. Six call sites throw it away, so the bar runs its full duration even if the boss dies, the pull resets, or the player leaves the zone:

| Site | Duration |
|---|---|
| `trial/rg/RockgroveCommon.lua:116` | 13 500 ms — the worst case |
| `trial/rg/RockgroveCommon.lua:108` | variable (`dur`) |
| `trial/dsr/DreadsailCommon.lua:111` | 6 000 ms — shared by all three DSR bosses |
| `trial/dsr/DreadsailCommon.lua:121` | 5 000 ms — same |
| `trial/ka/boss/Falgravn.lua:515` | variable (`dur`) |
| `trial/rg/boss/Oaxiltso.lua:106` | 2 750 ms |

The eight `zo_callLater` calls that discard their handle (`checks.py` C-20) were read one by one and are fine: each callback re-tests the state it touches (`if not IsUnitInCombat("player")`, `if self.x then`) and none of them writes to a control. The asymmetry is worth stating so the C-20 NOTE does not read as six more bugs.

---

## 4. Suggested order of work

Everything below is drafted in `patches/` as `git am`-able commits against `66977e3`. Nothing has been pushed to `master`, and no patch has been applied to the reviewed checkout. Branch names follow `.githooks/pre-push` (`feature/*` or `fix/*` only).

| Order | Patch | Findings | Merge risk |
|---|---|---|---|
| 1 | `01-fix-strip-utf8-bom` | F-01 | none — 3 bytes per file, 9 files |
| 2 | `02-fix-panel-cache-and-control-name` | F-08, F-10 | low; 2 commits, both in `ui/Panel.lua` |
| 3 | `03-fix-boss-slot-and-alert-hygiene` | F-02, F-03, F-07 | **medium** — this is the HP-percent backbone; replay the KA/LC logs afterwards |
| 4 | `04-fix-hardmode-measurement-aid` | F-04, F-22 | low — no behaviour change for the 9 real thresholds |
| 5 | `05-feature-live-trial-enable` | F-09, F-24 | low — reorders `core/ZoneManager.lua` in `incha.txt`, guarded by C-03 |
| 6 | `06-fix-single-version-source` | F-17 | none |
| 7 | `07-feature/ci-static-validation` | F-01, F-14 | merge **last** — see § 5 |
| 8 | `08-fix-docs-drift-corrections` | F-16 | none — documentation only |

Verified combination: all eight apply cleanly on top of each other in this order (`git am -3`, 9 commits, 25 files, +379/−49) — re-checked on a fresh clone of `master` (`af2d477`) as well as on the reviewed `66977e3`, same result.) every shipped file parses, and `tools/static_checks.py` reports 0 failures. `.review/checks.py` moves from **6 PASS / 6 WARN / 4 FAIL / 5 NOTE** to **11 PASS / 5 WARN / 1 FAIL / 4 NOTE**; the one remaining FAIL is `showBossUI`, which is a decision, not a defect:

* **F-06 needs your call, not a patch.** Either wire the header (`Trial:onBossesChanged` already knows the boss and the slot, and `AlertSink:showHeader` already exists) or delete nine checkboxes and one settings key. Nine dead controls in a user-facing panel is the worst of the three outcomes; a patch that guesses which you want is not worth a review cycle.
* **F-05, F-12, F-13, F-22 need one in-game session** (~2 h): proximity constants in world units, the Falgravn AABB, localised unit names, HM pools. `04-fix-hardmode-measurement-aid` and the probes in § 6C exist specifically to make that session productive — after it, #29/#30/#31 unblock.
* **F-11 is a 2-minute probe** (§ 6C.2) and decides whether `core/CombatHandler.lua:10-18` needs the post-Update argument list.
* **F-15, F-19, F-20** are workflow/doc hygiene: worth an issue each, not a PR.

---

## 5. The CI we drafted (patch 07)

`feature/ci-static-validation` adds two jobs plus a pre-push guard:

* `tools/static_checks.py` — stdlib-only, four gates that each map to a defect that silently kills a trial: BOM/CRLF/mojibake encoding, `incha.txt` ↔ disk sync, `require` load order, and the `Incha` control-name prefix.
* `tools/syntax_check.js` — a `luaparse` pass over every file listed in the manifest. It complements the encoding gate rather than replacing it: `luaparse` tolerates a BOM, so only the byte check catches F-01.
* `.githooks/pre-push` — keeps the existing branch-name rule and adds a BOM check, so the class of regression introduced by `a4e2942` cannot reach a remote again.

**Merge it last.** On the current `master` it reports 10 failures — the nine BOMs plus `Incha_Panel` — because those are exactly the defects patches 01/02 fix. If you would rather land CI first, add a baseline file and we will prepare that variant instead.

---

## 6. Appendix

### A. Reproduce every CONFIRMED claim
```sh
sh .review/run.sh --git          # human-readable
python3 .review/checks.py --repo . --json .review/findings.json
```
Exit status 1 while F-01, F-06 and F-08 are open. Nothing here writes to the repository outside `.review/`.

### B. Files delivered in `.review/` (gitignored)
| File | Purpose |
|---|---|
| `README.md` | index of this folder, how to re-run everything |
| `code-review-2026-09-01.md` | the review itself (26 findings) |
| `AGENT-BRIEF.md` | operating instructions for whoever works the queue — including an AI assistant |
| `HANDOFF.md` | fork → branch → PR mechanics for this repository pair, with the exact commands |
| `boss-inventory.md` | generated per-boss table: detection rule, threshold, routes, slots, lifecycle hooks |
| `checks.py` | the 22 checks above, read-only, CI-ready, exit 1 on FAIL |
| `inventory.py` | regenerates `boss-inventory.md` |
| `build-patches.py` | regenerates `patches/` from the reviewed commit (assertion-guarded, refuses to run in the reviewed tree) |
| `verify-patches.py` | apply-check / `git am` / luaparse / static-check per patch and for the whole series |
| `syntax.js` | optional `luaparse` syntax pass |
| `run.sh` | one-shot runner |
| `patches/*.patch` | 8 suggested fixes, 9 commits, `git am`-clean against `66977e3` |
| `findings.json` | machine-readable check results (issue import) |
| `patch-verification.txt` | captured verification output for the series |
| `verification-output.txt` | captured output of the run that produced this review |

### C. In-game probes referenced above
1. **Zone IDs** (the procedure is already written up at `ROADMAP.md:826-831`): `/script d(GetZoneId(GetUnitZoneIndex("player")))` inside each trial — do **not** use `GetCurrentMapZoneIndex()`.
2. **Combat-event arguments** (F-11): the `InchaProbe` snippet in F-11.
3. **Boss slot + HP** (F-03, F-04): `/script d(GetUnitName("boss1"), GetUnitMaxPower("boss1", POWERTYPE_HEALTH))` and the same for `boss2`.
4. **Proximity scale** (F-05): the `group1` snippet in F-05.
5. **AABB corners** (F-12): `GetUnitWorldPosition("player")` at each corner of the Falgravn room; record min/max x/z.

### D. Duplicate-commit pairs (F-15)
`674262a`/`1493a64` · `0123e4a`/`5ffc191` · `12aed73`/`0e2cc57` · `ad72e85`/`3b196b1` · `46e6792`/`67ad2af` · `80f3cee`/`0bfdad5` · `0d579e8`/`c7ed05a` · `b5e533c`/`5ebb397` · `9936709`/`8afa6ad` · plus 33 more pairs detected by message multiplicity (`--git`).

### E. What this review could **not** establish
* The current live signature of `EVENT_COMBAT_EVENT` / `EVENT_EFFECT_CHANGED` (F-11) — no reachable API documentation from this environment.
* Whether ESO's file loader tolerates a UTF-8 BOM (F-01) — the cleanup stands regardless; only the severity of the *current* breakage depends on the answer.
* Any in-game constant: zone IDs, world coordinates, unit names, HP pools, ability IDs. The ROADMAP's in-game confirmations were taken at face value and are listed as "trust but re-measure" in § C.
* Behaviour of `GetPlayerRoles()` return order. Five call sites unpack the third value (`trial/rg/boss/Bahsei.lua:157`, `:184`, `trial/rg/RockgroveCommon.lua:70`, `trial/oc/OsseinCageCommon.lua:118`, `trial/lc/LCCommon.lua:58`), `trial/dsr/boss/Lylanar.lua:322` and `:335` use `local _, isHeal, isTank`, and the harness stub comments `(roles, isHealer, isTank, isDropper)` (`test/harness/eso_api.lua:125-129`) — internally consistent, but the real order was not verifiable here. One probe covers it: `/script local a,b,c,d = GetPlayerRoles() d(a,b,c,d)`.

### F. Patch series — how to use it
```sh
git checkout -b fix/review-batch master          # or one branch per patch
git am -3 .review/patches/01-*.patch .review/patches/02-*.patch   # …in the § 4 order
python3 tools/static_checks.py                   # after patch 07 is applied
```
Or let the assistant work the queue instead — `AGENT-BRIEF.md` states the ground rules, and `HANDOFF.md` has the branch/PR commands for this repository pair (`sternnick/incha`, a fork of `oseias-pt/incha`).

*End of review.*
