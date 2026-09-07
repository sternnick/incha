local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")
local Colors = require("core.Colors")


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

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BARRAGE_DUR = 3000   -- NecroticBarrage: empirical
local FALLBACK_DUR         = 2000   -- Tempest / GlassStomp: empirical

local XorynEncounter = {}
XorynEncounter.__index = XorynEncounter

XorynEncounter.key               = "xoryn"
XorynEncounter.nameAliases       = { Lang.t("boss_xoryn") }
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
    CA.ranged(abilityId, Lang.t("lc_xoryn_barrage_bar"), dur, Colors.VOID)
end

local function handleAcceleratingCharge(self, context, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_xoryn_chain_lightning"), 0xFFFF44FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_accel_charge"))
end

local function handleTempest(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_xoryn_tempest_bar"), dur, Colors.ICE)
    alerts:showAction(Lang.t("lc_xoryn_tempest"))
end

local function handleGlassStomp(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_xoryn_atronach_bar", target), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("lc_xoryn_atronach_aoe"))
    end
end

local function handleLustrousJavelin(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_javelin_alert"), 0xFF8844FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_lustrous_javelin"))
end

local function handleArcaneKnot(self, context, alerts, result, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.holdingKnot = true
        CA.alert(nil, Lang.t("lc_xoryn_knot_alert"), 0xFFAA44FF, SOUNDS.NONE, 4000)
        alerts:showAction(Lang.t("lc_xoryn_arcane_knot"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.holdingKnot = false
    end
end

local function handleArcaneConvDebuff(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_tether_alert"), 0xFF4444FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_tether"))
end

local function handleFluctuatingCurrent(self, context, alerts, result, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.holdingCurrent = true
        self.currentTimer:reset(CURRENT_MAX_DUR)
        CA.alert(nil, Lang.t("lc_xoryn_current_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("lc_xoryn_fluctuating"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.holdingCurrent = false
        self.currentTimer:clear()
    end
end

local function handleOverloadedCurrent(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_drop_alert"), 0xFF0000FF, SOUNDS.NONE, 2000)
    alerts:showAction(Lang.t("lc_xoryn_overloaded"))
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
            alerts:setRow(1, Fmt.c(Fmt.ICE, Lang.t("lc_xoryn_current")), r)
        else
            alerts:setRow(1, Fmt.c(Fmt.RED, Lang.t("lc_xoryn_drop_now")), nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Line 2: Arcane Knot carrier indicator.
local function showKnotLine(self, alerts)
    if self.holdingKnot then
        alerts:setRow(2, Fmt.c(Fmt.AMBER, Lang.t("lc_xoryn_carrying_knot")), nil)
    else
        alerts:clearRow(2)
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
    -- Slots 3-7 are not written by this encounter.  Trial:onBossesChanged
    -- clears the panel on every boss transition, so they do not need to be
    -- blanked on each tick.
end

package.loaded["trial.lc.boss.XorynEncounter"] = XorynEncounter
return XorynEncounter
