local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local PIERCING_BEAM = 219165   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD 14s first / 32s steady
local VITRIFY       = 219083   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD  9s first / 20s steady

-- ── Timer durations (seconds) ─────────────────────────────────────────────
-- BEAM_FIRST_CD = 14.0    -- reference: first beam delay (proactive timer; unimplemented)
local BEAM_CD          = 32.0
-- VITRIFY_FIRST_CD = 9.0  -- reference: first vitrify delay (proactive timer; unimplemented)
local VITRIFY_CD       = 20.0

-- ── CA colour palettes ────────────────────────────────────────────────────

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BEAM_DUR    = 2500   -- PiercingBeam: empirical
local FALLBACK_VITRIFY_DUR = 2000   -- Vitrify: empirical

local XynizataEncounter = {}
XynizataEncounter.__index = XynizataEncounter

XynizataEncounter.key               = "xynizata"
XynizataEncounter.nameAliases       = { Lang.t("boss_xynizata") }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
XynizataEncounter.hmHealthThreshold = math.huge
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

XynizataEncounter.stateSchema = {
    piercingBeamTimer = function() return Timer.new(BEAM_CD) end,
    vitrifyTimer      = function() return Timer.new(VITRIFY_CD) end,
    firstBeam         = true,
    firstVitrify      = true,
}

function XynizataEncounter.new()
    return BossBase.fromSchema(XynizataEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handlePiercingBeam(self, context, alerts, abilityId, ...)
    self.firstBeam = false
    self.piercingBeamTimer:reset(BEAM_CD)
    local dur = CastDur.get(abilityId, FALLBACK_BEAM_DUR)
    CA.ranged(abilityId, Lang.t("lc_xynizata_beam_bar"), dur, Colors.RED)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_beam"))
end

local function handleVitrify(self, context, alerts, abilityId, ...)
    self.firstVitrify = false
    self.vitrifyTimer:reset(VITRIFY_CD)
    local dur = CastDur.get(abilityId, FALLBACK_VITRIFY_DUR)
    CA.ranged(abilityId, Lang.t("lc_xynizata_interrupt_vitr"), dur, Colors.RED)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_vitr"))
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

XynizataEncounter.combatRoutes = {
    [PIERCING_BEAM] = { result = ACTION_RESULT_BEGIN, fn = handlePiercingBeam },
    [VITRIFY]       = { result = ACTION_RESULT_BEGIN, fn = handleVitrify },
}

function XynizataEncounter:onWipe()
    self.piercingBeamTimer:clear(); self.vitrifyTimer:clear()
    self.firstBeam = true; self.firstVitrify = true
end

function XynizataEncounter:onUpdate(context, alerts)
    -- Line 1: Piercing Beam CD
    if self.firstBeam then
        alerts:setRow(1, Lang.t("lc_xynizata_beam_first"), nil)
    else
        local r = self.piercingBeamTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("lc_xynizata_beam_label"), r)
        else
            alerts:setRow(1, Lang.t("lc_xynizata_beam_label") .. " " .. Lang.t("common_interrupt"), nil)
        end
    end

    -- Line 2: Vitrify CD
    if self.firstVitrify then
        alerts:setRow(2, Lang.t("lc_xynizata_vitr_first"), nil)
    else
        local r = self.vitrifyTimer:remaining()
        if r > 0 then
            alerts:setRow(2, Lang.t("lc_xynizata_vitr_label"), r)
        else
            alerts:setRow(2, Lang.t("lc_xynizata_vitr_label") .. " " .. Lang.t("common_interrupt"), nil)
        end
    end

    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

package.loaded["trial.lc.boss.XynizataEncounter"] = XynizataEncounter
return XynizataEncounter
