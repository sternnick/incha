local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local THUNDER_THRALL  = 214383   -- combatRoute: ACTION_RESULT_BEGIN → Xoryn jump; timer 25.5s / 8s first
local LIGHTNING_FLOOD = 214355   -- combatRoute: ACTION_RESULT_BEGIN → Xoryn cone; timer 21.5s / 3s first
local COLOR_CHANGE    = 213913   -- combatRoute: ACTION_RESULT_EFFECT_GAINED → mirror switch alert
local BREAKOUT        = 220185   -- combatRoute: ACTION_RESULT_BEGIN → crystal prison on player
local SHIELD_THROW    = 221945   -- combatRoute: ACTION_RESULT_BEGIN → Crystal Sentinel caAlertCast
local XORYN_IMMUNE_1  = 217987   -- combatRoute: ACTION_RESULT_EFFECT_GAINED / FADED → Xoryn away / returned
local XORYN_IMMUNE_2  = 219545   -- combatRoute: ACTION_RESULT_EFFECT_GAINED / FADED → Xoryn away variant

-- ── Timer durations (seconds) ─────────────────────────────────────────────
-- THRALL_FIRST_CD = 8.0  -- reference: first Thrall delay after Xoryn returns (proactive timer; unimplemented)
local THRALL_CD       = 25.5   -- steady-state Thrall CD
-- FLOOD_FIRST_CD = 3.0   -- reference: first Flood delay after Xoryn returns (proactive timer; unimplemented)
local FLOOD_CD        = 21.5   -- steady-state Flood CD

-- ── CA colour palettes ────────────────────────────────────────────────────

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- Shield Throw: empirical

local OrphicEncounter = {}
OrphicEncounter.__index = OrphicEncounter

OrphicEncounter.key               = "orphic"
OrphicEncounter.nameAliases       = { Lang.t("boss_orphic") }
OrphicEncounter.hmHealthThreshold = 80000000
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

OrphicEncounter.stateSchema = {
    thunderThrallTimer  = function() return Timer.new(THRALL_CD) end,
    lightningFloodTimer = function() return Timer.new(FLOOD_CD) end,
    xorynActive         = false,
    firstThrall         = true,
    firstFlood          = true,
}

function OrphicEncounter.new()
    return BossBase.fromSchema(OrphicEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

-- Xoryn immune: shared handler for both variants (GAINED = away, FADED = returned).
local function handleXorynImmune(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        self.xorynActive = false
        self.thunderThrallTimer:clear()
        self.lightningFloodTimer:clear()
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.xorynActive = true
        self.firstThrall = true
        self.firstFlood  = true
    end
end

local function handleThunderThrall(self, context, alerts, abilityId, ...)
    self.xorynActive = true
    self.firstThrall = false
    self.thunderThrallTimer:reset(THRALL_CD)
    alerts:showAction(Lang.t("lc_orphic_thunder_thrall"))
end

local function handleLightningFlood(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    self.xorynActive = true
    self.firstFlood  = false
    self.lightningFloodTimer:reset(FLOOD_CD)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("lc_orphic_lightning_flood", target))
end

local function handleBreakout(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.ranged(abilityId, Lang.t("lc_orphic_break_out_bar"), 3000, Colors.ARCANE)
    alerts:showAction(Lang.t("lc_orphic_break_crystal"))
end

local function handleShieldThrow(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_orphic_shield_throw", target), dur, Colors.LIGHTNING)
end

local function handleColorChange(self, context, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_orphic_color_change_alert"), 0xFFFF44FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_orphic_color_change"))
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

OrphicEncounter.combatRoutes = {
    [THUNDER_THRALL]  = { result = ACTION_RESULT_BEGIN,         fn = handleThunderThrall },
    [LIGHTNING_FLOOD] = { result = ACTION_RESULT_BEGIN,         fn = handleLightningFlood },
    [BREAKOUT]        = { result = ACTION_RESULT_BEGIN,         fn = handleBreakout },
    [SHIELD_THROW]    = { result = ACTION_RESULT_BEGIN,         fn = handleShieldThrow },
    [COLOR_CHANGE]    = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleColorChange },
    [XORYN_IMMUNE_1]  = handleXorynImmune,
    [XORYN_IMMUNE_2]  = handleXorynImmune,
}

function OrphicEncounter:onWipe()
    self.thunderThrallTimer:clear(); self.lightningFloodTimer:clear()
    self.xorynActive = false; self.firstThrall = true; self.firstFlood = true
end

function OrphicEncounter:onUpdate(context, alerts)
    if self.xorynActive then
        if self.firstThrall then
            alerts:setRow(1, Lang.t("lc_orphic_thrall_first"), nil)
        else
            local r = self.thunderThrallTimer:remaining()
            if r > 0 then
                alerts:setRow(1, Lang.t("lc_orphic_thrall_label"), r)
            else
                alerts:setRow(1, Lang.t("lc_orphic_thrall_label") .. " " .. Lang.t("common_now"), nil)
            end
        end
        if self.firstFlood then
            alerts:setRow(2, Lang.t("lc_orphic_flood_first"), nil)
        else
            local r = self.lightningFloodTimer:remaining()
            if r > 0 then
                alerts:setRow(2, Lang.t("lc_orphic_flood_label"), r)
            else
                alerts:setRow(2, Lang.t("lc_orphic_flood_label") .. " " .. Lang.t("common_now"), nil)
            end
        end
    else
        alerts:clearRow(1)
        alerts:clearRow(2)
    end
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

package.loaded["trial.lc.boss.OrphicEncounter"] = OrphicEncounter
return OrphicEncounter
