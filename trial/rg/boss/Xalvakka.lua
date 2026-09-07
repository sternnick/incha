--- Xalvakka  -  Rockgrove boss 3
---
--- Three-floor fight:
---   Floor 1: HP 100-70%  (boss escapes at 70%)
---   Floor 2: HP  70-40%  (boss escapes at 40%)
---   Floor 3: HP   0-40%
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) (done)
--- Phase RG-5: Xalvakka-specific mechanics (done)
---   ScathingEvisceration (149180/153448/153450): targeted player -> AlertCast
---   Deadstar (149386/149075): BEGIN -> Alert("Deadstar!")
---   FlamingPortal/Jump (157390): BEGIN -> nextJump +35 s, numJumps++ (HM)
---   SoulResonance (152993): EFFECT_GAINED self -> Alert("Purge!"), start timer
---   UnstableCharge/Blob (153164): EFFECT_GAINED/FADED self -> AlertBorder green; info4
---   VolatileShell shield: EVENT_UNIT_ATTRIBUTE_VISUAL_* on "reticleover" -> shellShield
---   Run timer: HP 70-75% and 40-45% -> info4 countdown
--- Phase RG-6: ManifoldDebuff (157290) (done)
---   EFFECT_GAINED self   -> AlertBorder purple + "Manifold Curse!" caAlert
---   EFFECT_GAINED others -> name tracked in manifoldOthers[]
---   EFFECT_FADED self    -> border cleared, selfManifold = false
---   EFFECT_FADED others  -> removed from manifoldOthers[]
---   onUpdate info3       -> manifold list (priority) > shell shield value
---
--- Shield tracking (Volatile Shell):
---   Registered in onEnter (scoped to the encounter), cleaned up in onLeave().
---   CombatHandler does NOT carry EVENT_UNIT_ATTRIBUTE_VISUAL_*; registration
---   is self-contained here using key SHIELD_EVENT_KEY.
---
---   TODO: Verify ATTRIBUTE_VISUAL_POWER_SHIELDING constant and event parameter
---         order against the live ESO API before publishing.
---
--- HM detection: context.isHM (pre-computed by TrialContext from hmHealthThreshold)
---   (set by BossRegistry:detectDifficulty via hmHealthThreshold=100000001)
---   TODO: verify exact HM health pool in-game.

local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")


local SHIELD_EVENT_KEY = ADDON_PREFIX .. "RG_XalvakkaShield"

-- -- Ability IDs ------------------------------------------------------------
local SCATHING1       = 149180   -- combatRoute: ACTION_RESULT_BEGIN -> player-targeted alert
local SCATHING2       = 153448   -- combatRoute: ACTION_RESULT_BEGIN -> player-targeted alert (HM)
local SCATHING3       = 153450   -- combatRoute: ACTION_RESULT_BEGIN -> player-targeted alert (HM)
local DEADSTAR1       = 149386   -- combatRoute: ACTION_RESULT_BEGIN -> Deadstar alert
local DEADSTAR2       = 149075   -- combatRoute: ACTION_RESULT_BEGIN -> Deadstar alert
local FLAMING_PORTAL  = 157390   -- combatRoute: ACTION_RESULT_BEGIN -> nextJump +35s (HM)
local SOUL_RESONANCE  = 152993   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> purge alert
local UNSTABLE_CHARGE = 153164   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> green border (blob)
local MANIFOLD_DEBUFF = 157290   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> purple border + tracker

-- 149180/153448/153450 (SCATHING_IDS) -- reference: scathing strike detection set (unrouted)
-- 149386/149075 (DEADSTAR_IDS)        -- reference: dead star detection set (unrouted)

-- Soul resonance display window after GAINED (seconds); approximate; verify in-game.
local SOUL_WINDOW = 9

-- HP % ranges that trigger the run timer display.
local RUN1_TOP = 75    -- first transition: boss flees at 70%
local RUN1_BOT = 70
local RUN2_TOP = 45    -- second transition: boss flees at 40%
local RUN2_BOT = 40

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")

-- -- CA colour palettes -----------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_SCATHING_DUR = 1500   -- ScathingEvisceration: empirical

-- -- Shield value formatter -------------------------------------------------
local function fmtShield(v)
    if v >= 1000000 then
        return string.format("%.2fM", v / 1000000)
    elseif v >= 1000 then
        return string.format("%.1fk", v / 1000)
    else
        return tostring(math.floor(v))
    end
end

-- -- Boss definition -------------------------------------------------------
local Xalvakka = {}
Xalvakka.__index = Xalvakka
Xalvakka.common = RockgroveCommon   -- C3: common mechanic dispatch

Xalvakka.key               = "xalvakka"
Xalvakka.name              = Lang.t("boss_xalvakka")     -- TODO: verify exact unit name via GetUnitName("boss1")
-- location: arena AABB not yet captured  -  detection is name-based.
-- To add AABB: stand in arena, run /script d(GetUnitWorldPosition("boss1"))
Xalvakka.hmHealthThreshold = 100000001      -- TODO: verify exact HM health pool

Xalvakka.stateSchema = {
    nextJump       = 0,
    numJumps       = 0,
    shellShield    = 0,
    onBlob         = false,
    soulStart      = 0,
    selfManifold   = false,
    manifoldOthers = function() return {} end,
}

function Xalvakka.new()
    return BossBase.fromSchema(Xalvakka)
end

-- -- Lifecycle -------------------------------------------------------------
function Xalvakka:onLeave(context)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)
end

-- -- Boss enter ------------------------------------------------------------
-- Called by Trial:onBossesChanged when Xalvakka becomes the active boss.
-- Self-registers Volatile Shell shield tracking so it is encounter-scoped.
function Xalvakka:onEnter(context, alerts)
    -- Unregister first; onEnter may fire again after a soft-reset / floor transition.
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)

    -- ESO event parameters (verify against live API):
    --   eventCode, unitTag, attributeType, powerType, value, max, shieldPoolIndex
    -- ATTRIBUTE_VISUAL_POWER_SHIELDING tracks absorb shields on a unit's health bar.
    --
    -- These three events fire for every shield tick on every unit the client
    -- knows about, which in a twelve-player raid is a lot of traffic for a
    -- handler that only ever cares about "reticleover".  REGISTER_FILTER_UNIT_TAG
    -- moves that test into the engine so the rest never reaches Lua.
    --
    -- Registration is wrapped so an error here is reported and swallowed the
    -- way EventPipeline does it: this boss registers outside the pipeline, so
    -- without the wrapper an error would escape into ESO's event system and
    -- affect other addons.
    local function onShield(setter)
        return function(eventCode, unitTag, attributeType, powerType, value, max, poolIndex)
            local ok, err = pcall(function()
                if attributeType == ATTRIBUTE_VISUAL_POWER_SHIELDING then
                    self.shellShield = setter(value)
                end
            end)
            if not ok then d(ADDON_TAG .. " " .. tostring(err)) end
        end
    end

    local function register(event, handler)
        EVENT_MANAGER:RegisterForEvent(SHIELD_EVENT_KEY, event, handler)
        EVENT_MANAGER:AddFilterForEvent(SHIELD_EVENT_KEY, event,
            REGISTER_FILTER_UNIT_TAG, "reticleover")
    end

    register(EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED,   onShield(function(v) return v or 0 end))
    register(EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED, onShield(function(v) return v or 0 end))
    register(EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED, onShield(function() return 0 end))
end

-- Soft reset on wipe: clear the CA danger border and all per-pull state
-- so the next attempt starts clean.
function Xalvakka:onWipe(context, alerts)
    CA.border(false, 0, nil)
    self.nextJump       = 0
    self.numJumps       = 0
    self.shellShield    = 0
    self.onBlob         = false
    self.soulStart      = 0
    self.selfManifold   = false
    self.manifoldOthers = {}
end

-- -- Combat state ----------------------------------------------------------
function Xalvakka:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- First jump expected ~35 s after pull in HM; same interval as subsequent jumps.
        -- TODO: verify first-jump timing in-game (may differ from subsequent 35 s interval).
        self.nextJump = GetGameTimeMilliseconds() / 1000 + 35
        self.numJumps = 0
    end
end

-- -- Routing tables (C3) --------------------------------------------------
-- (No onDied needed  -  Xalvakka has no alertList.)

-- ScathingEvisceration: player-targeted frontal heavy (3 IDs, shared handler).
local function handleScathing(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_SCATHING_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.MAGENTA)
end

-- Deadstar add explosion (2 IDs, shared handler).
local function handleDeadstar(self, context, alerts, abilityId, ...)
    CA.alert(nil, "Deadstar!", 0xFFCC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleFlamingPortal(self, context, alerts, abilityId, ...)
    if not context.isHM then return end
    local now = GetGameTimeMilliseconds() / 1000
    self.numJumps = self.numJumps + 1
    self.nextJump = now + 35
end

Xalvakka.combatRoutes = {
    -- ScathingEvisceration (base + two HM variants)
    [SCATHING1] = { result = ACTION_RESULT_BEGIN, fn = handleScathing },
    [SCATHING2] = { result = ACTION_RESULT_BEGIN, fn = handleScathing },
    [SCATHING3] = { result = ACTION_RESULT_BEGIN, fn = handleScathing },
    -- Deadstar add-explosion (two variants)
    [DEADSTAR1] = { result = ACTION_RESULT_BEGIN, fn = handleDeadstar },
    [DEADSTAR2] = { result = ACTION_RESULT_BEGIN, fn = handleDeadstar },
    -- Flaming Portal (repositioning jump, HM only)
    [FLAMING_PORTAL] = { result = ACTION_RESULT_BEGIN, fn = handleFlamingPortal },
}

-- Soul Resonance: personal purge alert.
local function handleSoulResonance(self, context, alerts, changeType, abilityId,
                                    unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        self.soulStart = GetGameTimeMilliseconds() / 1000
        CA.alert(nil, "Purge Soul Resonance!", 0xFF6600D9, SOUNDS.DUEL_START, 4000)
        PlaySound(SOUNDS.DUEL_START)
    elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
        self.soulStart = 0
    end
end

-- Unstable Charge / Blob: green border while standing on orb.
local function handleUnstableCharge(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        self.onBlob = true
        CA.border(true, 8000, "green")
    elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
        self.onBlob = false
        CA.border(false, 0, nil)
    end
end

-- Manifold Curse: purple border for self, name tracker for others.
local function handleManifoldDebuff(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        if AreUnitsEqual("player", unitTag) then
            self.selfManifold = true
            CA.border(true, 20000, "purple")
            CA.alert(nil, Fmt.c(Fmt.ARCANE, "Manifold Curse") .. " on YOU  -  spread!",
                0xAA44FFD9, SOUNDS.DUEL_START, 5000)
            PlaySound(SOUNDS.DUEL_START)
        elseif IsUnitPlayer(unitTag) then
            self.manifoldOthers[unitTag] =
                GetUnitDisplayName(unitTag) or unitName or "?"
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.selfManifold = false
            CA.border(false, 0, nil)
        else
            self.manifoldOthers[unitTag] = nil
        end
    end
end

Xalvakka.effectRoutes = {
    [SOUL_RESONANCE]  = handleSoulResonance,
    [UNSTABLE_CHARGE] = handleUnstableCharge,
    [MANIFOLD_DEBUFF] = handleManifoldDebuff,
}

-- -- Tracker-row renderers --------------------------------------------------

-- Row 1 (HM): Next jump timer; hidden once numJumps >= 4 (pattern established).
local function showJumpLine(self, alerts, now, isHM)
    if isHM and self.nextJump > 0 and self.numJumps < 4 then
        local T = self.nextJump - now
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.AMBER, Lang.t("rg_xalvakka_next_jump")), T)
        else
            alerts:setRow(1, Fmt.c(Fmt.AMBER, Lang.t("rg_xalvakka_next_jump")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Soul Resonance personal countdown; auto-clears when window expires.
local function showSoulLine(self, alerts, now)
    if self.soulStart > 0 then
        local T = SOUL_WINDOW - (now - self.soulStart)
        if T > 0 then
            alerts:setRow(2, Fmt.c(Fmt.ORANGE, Lang.t("rg_xalvakka_soul_res")), T)
        else
            self.soulStart = 0
            alerts:clearRow(2)
        end
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Manifold Curse holders (priority) > Volatile Shell shield value.
local function showManifoldLine(self, alerts)
    local hasManifold = self.selfManifold or (next(self.manifoldOthers) ~= nil)
    if hasManifold then
        local parts = {}
        if self.selfManifold then
            parts[#parts + 1] = Fmt.c(Fmt.ARCANE, "YOU")
        end
        for _, name in pairs(self.manifoldOthers) do
            parts[#parts + 1] = Fmt.c(Fmt.ARCANE, name)
        end
        alerts:setRow(3, Lang.t("rg_xalvakka_manifold") .. table.concat(parts, ", "), nil)
    elseif self.shellShield > 0 then
        alerts:setRow(3, Lang.t("rg_xalvakka_shield") .. fmtShield(self.shellShield), nil)
    else
        alerts:clearRow(3)
    end
end

-- Row 4: Run timer near floor-transition HP thresholds (priority) > Blob indicator.
-- Uses row 4, not showAction, to avoid clobbering reactive event alerts.
local function showRunLine(self, alerts, context)
    local hp = context.healthPercent
    if hp and hp > RUN1_BOT and hp <= RUN1_TOP then
        alerts:setRow(4, Fmt.c(Fmt.YELLOW, Lang.t("rg_xalvakka_run_in") .. Fmt.pct(hp - RUN1_BOT, 1)), nil)
    elseif hp and hp > RUN2_BOT and hp <= RUN2_TOP then
        alerts:setRow(4, Fmt.c(Fmt.YELLOW, Lang.t("rg_xalvakka_run_in") .. Fmt.pct(hp - RUN2_BOT, 1)), nil)
    elseif self.onBlob then
        alerts:setRow(4, Fmt.c(Fmt.GREEN, Lang.t("rg_xalvakka_on_blob")), nil)
    else
        alerts:clearRow(4)
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Xalvakka:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showJumpLine(self, alerts, now, isHM)
    showSoulLine(self, alerts, now)
    showManifoldLine(self, alerts)
    showRunLine(self, alerts, context)
end

package.loaded["trial.rg.boss.Xalvakka"] = Xalvakka
return Xalvakka
