
local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")
local Colors = require("core.Colors")


-- ── Ability IDs ───────────────────────────────────────────────────────────
local BRILLIANT_ANNIHILATION = 214187   -- combatRoute: ACTION_RESULT_BEGIN → light side room wipe; STACK
local BLEAK_ANNIHILATION     = 214203   -- combatRoute: ACTION_RESULT_BEGIN → dark side room wipe; STACK
local PORCIN_LIGHT           = 219329   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED → player on Ryelaz (dark) side
local PORCIN_DARK            = 219330   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED → player on Zilyesset (light) side

-- ── CA colour palettes ────────────────────────────────────────────────────

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 3000   -- Annihilation channel: empirical

local RyelazEncounter = {}
RyelazEncounter.__index = RyelazEncounter

RyelazEncounter.key               = "ryelaz"
RyelazEncounter.nameAliases       = { Lang.t("boss_count_ryelaz"), Lang.t("boss_zilyesset") }
RyelazEncounter.hmHealthThreshold = 40000000
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

-- ── State ─────────────────────────────────────────────────────────────────
-- "ryelaz"    = player on Ryelaz dark side
-- "zilyesset" = player on Zilyesset light side
-- nil         = assignment unknown (split hasn't happened or effect not yet seen)
RyelazEncounter.stateSchema = {}

function RyelazEncounter.new()
    return BossBase.fromSchema(RyelazEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Annihilation: shared alertCast, different showAction label.
local function makeAnnihilHandler(label)
    return { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local dur = CastDur.get(abilityId, FALLBACK_DUR)
        CA.ranged(abilityId, Lang.t("lc_ryelaz_annihil_action"), dur, Colors.FLYZONE)
        alerts:showAction(label)
    end }
end

local function handlePorcinLight(self, context, alerts, result, abilityId, unitTag, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        self.playerSide = "ryelaz"
    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        self.playerSide = nil
    end
end

local function handlePorcinDark(self, context, alerts, result, abilityId, unitTag, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        self.playerSide = "zilyesset"
    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        self.playerSide = nil
    end
end

RyelazEncounter.combatRoutes = {
    [BRILLIANT_ANNIHILATION] = makeAnnihilHandler(Lang.t("lc_ryelaz_brilliant")),
    [BLEAK_ANNIHILATION]     = makeAnnihilHandler(Lang.t("lc_ryelaz_bleak")),
    [PORCIN_LIGHT]           = handlePorcinLight,
    [PORCIN_DARK]            = handlePorcinDark,
}

function RyelazEncounter:onWipe()
    self.playerSide = nil
end

function RyelazEncounter:onUpdate(context, alerts)
    if self.playerSide == "ryelaz" then
        alerts:setRow(1, Fmt.c(Fmt.AMBER,  Lang.t("lc_ryelaz_side_dark")), nil)
    elseif self.playerSide == "zilyesset" then
        alerts:setRow(1, Fmt.c(Fmt.FROST, Lang.t("lc_ryelaz_side_light")), nil)
    else
        alerts:clearRow(1)
    end
    -- Slots 2-7 are not written by this encounter.  Trial:onBossesChanged
    -- clears the panel on every boss transition, so they do not need to be
    -- blanked on each tick.
end

package.loaded["trial.lc.boss.RyelazEncounter"] = RyelazEncounter
return RyelazEncounter
