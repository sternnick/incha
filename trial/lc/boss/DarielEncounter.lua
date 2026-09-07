
local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local POWERFUL_THROW = 218971   -- combatRoute: ACTION_RESULT_BEGIN → caAlertCast; on player → explicit alert

-- ── CA colour palettes ────────────────────────────────────────────────────

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2500   -- PowerfulThrow: empirical

local DarielEncounter = {}
DarielEncounter.__index = DarielEncounter

DarielEncounter.key               = "dariel"
DarielEncounter.nameAliases       = { Lang.t("boss_dariel") }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
DarielEncounter.hmHealthThreshold = math.huge
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

DarielEncounter.stateSchema = {}

function DarielEncounter.new()
    return BossBase.fromSchema(DarielEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handlePowerfulThrow(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_dariel_throw_target", target), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("lc_dariel_throw_you"))
    else
        alerts:showAction(Lang.t("lc_dariel_throw_target", target))
    end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

DarielEncounter.combatRoutes = {
    [POWERFUL_THROW] = { result = ACTION_RESULT_BEGIN, fn = handlePowerfulThrow },
}

function DarielEncounter:onWipe()
    -- stateSchema is empty; no state to reset.
end

function DarielEncounter:onUpdate(context, alerts)
    alerts:clearRow(1)
    alerts:clearRow(2)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

package.loaded["trial.lc.boss.DarielEncounter"] = DarielEncounter
return DarielEncounter
