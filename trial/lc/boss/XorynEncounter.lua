local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local ARCANE_KNOT         = 213477   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED → carry knot
local ARCANE_CONV_DEBUFF  = 223060   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → tether on player
local FLUCTUATING_CURRENT = 214597   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED → hold (15s max)
local OVERLOADED_CURRENT  = 214745   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → DROP current
local NECROTIC_BARRAGE    = 223198   -- combatRoute: ACTION_RESULT_BEGIN → caAlertCast
local ACCELERATING_CHARGE = 214542   -- combatRoute: ACTION_RESULT_BEGIN → chain lightning incoming
local TEMPEST             = 215107   -- combatRoute: ACTION_RESULT_BEGIN → MOVE from mirror line
local GLASS_STOMP_CAST    = 219797   -- combatRoute: ACTION_RESULT_BEGIN → Crystal Atronach AOE on tank
local LUSTROUS_JAVELIN    = 223546   -- combatRoute: ACTION_RESULT_BEGIN → javelin on player

-- ── Constants ─────────────────────────────────────────────────────────────
local CURRENT_MAX_DUR = 15.0   -- holding Fluctuating Current beyond this = death

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_NECROTIC  = { -3, 0, false, { 0.5, 0,   0.9, 0.4 }, { 0.5, 0,   0.9, 0.8 } }
local COL_TEMPEST   = { -3, 0, false, { 0.2, 0.8, 1.0, 0.4 }, { 0.2, 0.8, 1.0, 0.8 } }
local COL_ATRONACH  = { -3, 0, false, { 1,   0.4, 0,   0.4 }, { 1,   0.4, 0,   0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BARRAGE_DUR = 3000   -- NecroticBarrage: empirical
local FALLBACK_DUR         = 2000   -- Tempest / GlassStomp: empirical

local XorynEncounter = {}
XorynEncounter.__index = XorynEncounter

XorynEncounter.key               = "xoryn"
XorynEncounter.nameAliases       = { "Xoryn" }
XorynEncounter.hmHealthThreshold = 100000000
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

XorynEncounter.stateSchema = {
    currentTimer    = function() return Timer.new(CURRENT_MAX_DUR) end,
    holdingKnot     = false,
    holdingCurrent  = false,
}

function XorynEncounter.new()
    return BossBase.fromSchema(XorynEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handleNecroticBarrage(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_BARRAGE_DUR)
    CA.alertCast(abilityId, "Necrotic Barrage!", dur, COL_NECROTIC)
end

local function handleAcceleratingCharge(self, context, alerts, abilityId, ...)
    CA.alert(nil, "Chain Lightning incoming!", 0xFFFF44FF, SOUNDS.NONE, 3000)
    alerts:showAction("Accelerating Charge → Chain Lightning!")
end

local function handleTempest(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "MOVE from line!", dur, COL_TEMPEST)
    alerts:showAction("Tempest! MOVE from mirror line!")
end

local function handleGlassStomp(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Atronach AOE → " .. target, dur, COL_ATRONACH)
    if IsUnitPlayer(unitTag) then
        alerts:showAction("Atronach AOE on YOU!")
    end
end

local function handleLustrousJavelin(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Javelin on YOU!", 0xFF8844FF, SOUNDS.NONE, 3000)
    alerts:showAction("Lustrous Javelin on you!")
end

local function handleArcaneKnot(self, context, alerts, result, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.holdingKnot = true
        CA.alert(nil, "Carry knot! Pass it!", 0xFFAA44FF, SOUNDS.NONE, 4000)
        alerts:showAction("Arcane Knot — carry and pass!")
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.holdingKnot = false
    end
end

local function handleArcaneConvDebuff(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "TETHER! Move away!", 0xFF4444FF, SOUNDS.NONE, 3000)
    alerts:showAction("Tether on you! Separate from partner!")
end

local function handleFluctuatingCurrent(self, context, alerts, result, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.holdingCurrent = true
        self.currentTimer:reset(CURRENT_MAX_DUR)
        CA.alert(nil, "Hold current! Drop at edge!", 0x44CCFFFF, SOUNDS.NONE, 3000)
        alerts:showAction("Fluctuating Current — hold, then drop!")
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.holdingCurrent = false
        self.currentTimer:clear()
    end
end

local function handleOverloadedCurrent(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "DROP current!", 0xFF0000FF, SOUNDS.NONE, 2000)
    alerts:showAction("Overloaded — DROP the current!")
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
XorynEncounter.combatRoutes = {
    [NECROTIC_BARRAGE]    = { result = ACTION_RESULT_BEGIN,                    fn = handleNecroticBarrage },
    [ACCELERATING_CHARGE] = { result = ACTION_RESULT_BEGIN,                    fn = handleAcceleratingCharge },
    [TEMPEST]             = { result = ACTION_RESULT_BEGIN,                    fn = handleTempest },
    [GLASS_STOMP_CAST]    = { result = ACTION_RESULT_BEGIN,                    fn = handleGlassStomp },
    [LUSTROUS_JAVELIN]    = { result = ACTION_RESULT_BEGIN,                    fn = handleLustrousJavelin },
    [ARCANE_KNOT]         = handleArcaneKnot,
    [ARCANE_CONV_DEBUFF]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,   fn = handleArcaneConvDebuff },
    [FLUCTUATING_CURRENT] = handleFluctuatingCurrent,
    [OVERLOADED_CURRENT]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,   fn = handleOverloadedCurrent },
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Line 1: Fluctuating Current countdown; "DROP NOW!" when the 15 s window expires.
local function showCurrentLine(self, alerts)
    if self.holdingCurrent then
        local r = self.currentTimer:remaining()
        if r > 0 then
            alerts:showInfo(1, "|c44CCFFCurrent: " .. string.format("%.0f", r) .. "s|r")
        else
            alerts:showInfo(1, "|cFF0000DROP NOW!|r")
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Line 2: Arcane Knot carrier indicator.
local function showKnotLine(self, alerts)
    if self.holdingKnot then
        alerts:showInfo(2, "|cFFAA44Carrying Arcane Knot|r")
    else
        alerts:showInfo(2, "")
    end
end

function XorynEncounter:onWipe()
    self.currentTimer:clear()
    self.holdingKnot    = false
    self.holdingCurrent = false
end

function XorynEncounter:onUpdate(context, alerts)
    showCurrentLine(self, alerts)
    showKnotLine(self, alerts)
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

package.loaded["trial.lc.boss.XorynEncounter"] = XorynEncounter
return XorynEncounter
