local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local PIERCING_BEAM = 219165   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD 14s first / 32s steady
local VITRIFY       = 219083   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD  9s first / 20s steady

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local BEAM_FIRST_CD    = 14.0
local BEAM_CD          = 32.0
local VITRIFY_FIRST_CD =  9.0
local VITRIFY_CD       = 20.0

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_INTERRUPT = { -3, 0, false, { 1, 0.1, 0.1, 0.4 }, { 1, 0.1, 0.1, 0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BEAM_DUR    = 2500   -- PiercingBeam: empirical
local FALLBACK_VITRIFY_DUR = 2000   -- Vitrify: empirical

local XynizataEncounter = {}
XynizataEncounter.__index = XynizataEncounter

XynizataEncounter.key               = "xynizata"
XynizataEncounter.nameAliases       = { "Xynizata" }
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
    CA.alertCast(abilityId, "INTERRUPT — Beam!", dur, COL_INTERRUPT)
    alerts:showAction("INTERRUPT — Piercing Beam!")
end

local function handleVitrify(self, context, alerts, abilityId, ...)
    self.firstVitrify = false
    self.vitrifyTimer:reset(VITRIFY_CD)
    local dur = CastDur.get(abilityId, FALLBACK_VITRIFY_DUR)
    CA.alertCast(abilityId, "INTERRUPT — Vitrify!", dur, COL_INTERRUPT)
    alerts:showAction("INTERRUPT — Vitrify!")
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
        alerts:showInfo(1, "Beam: first ~14s")
    else
        local r = self.piercingBeamTimer:remaining()
        alerts:showInfo(1, "Beam: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "INTERRUPT!"))
    end

    -- Line 2: Vitrify CD
    if self.firstVitrify then
        alerts:showInfo(2, "Vitrify: first ~9s")
    else
        local r = self.vitrifyTimer:remaining()
        alerts:showInfo(2, "Vitrify: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "INTERRUPT!"))
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

package.loaded["trial.lc.boss.XynizataEncounter"] = XynizataEncounter
return XynizataEncounter
