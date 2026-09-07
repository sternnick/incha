
local CA               = require("external-api.CombatAlerts")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")
local Lang             = require("core.Lang")
local Fmt              = require("core.Fmt")
local Colors = require("core.Colors")

-- ── Ability IDs (from OsseinCageHelper) ──────────────────────────────────
local OGRIM_CHARGE     = 236496   -- combatRoute: ACTION_RESULT_BEGIN → MOVE caAlertCast (player)
local SHAPER_SHIELD    = 232511   -- combatRoute: (plain) EFFECT_RESULT_GAINED/FADED → shield state
local CHANNELER_SHIELD = 232510   -- combatRoute: ACTION_RESULT_EFFECT_GAINED → channelers alert

-- ── CA colour palettes ────────────────────────────────────────────────────

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- Ogrim Charge: empirical

local ShaperEncounter = {}
ShaperEncounter.__index = ShaperEncounter

ShaperEncounter.key               = "shaper"
ShaperEncounter.nameAliases       = { Lang.t("boss_shaper") }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
ShaperEncounter.hmHealthThreshold = math.huge
-- location: placeholder — Oathsworn Pit arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

ShaperEncounter.stateSchema = {
    shaperShielded = false,
}

function ShaperEncounter.new()
    return BossBase.fromSchema(ShaperEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handleOgrimCharge(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_shaper_ogrim_bar"), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("oc_shaper_ogrim_you"))
    else
        alerts:showAction(Lang.t("oc_shaper_ogrim_tgt", target))
    end
end

local function handleShaperShield(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        self.shaperShielded = true
        CA.alert(nil, Lang.t("oc_shaper_shielded_alert"), 0xAA44FFFF, SOUNDS.NONE, 4000)
        alerts:showAction(Lang.t("oc_shaper_shielded_kill"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.shaperShielded = false
        CA.alert(nil, Lang.t("oc_shaper_vulnerable_alert"), 0x44FF88FF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_shaper_vulnerable"))
    end
end

local function handleChannelerShield(self, context, alerts, abilityId, ...)
    self.shaperShielded = true
    alerts:showAction(Lang.t("oc_shaper_channelers_shld"))
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Shared trash-mechanic handler.
ShaperEncounter.common = OsseinCageCommon

ShaperEncounter.combatRoutes = {
    [OGRIM_CHARGE]     = { result = ACTION_RESULT_BEGIN,         fn = handleOgrimCharge },
    [SHAPER_SHIELD]    = handleShaperShield,
    [CHANNELER_SHIELD] = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleChannelerShield },
}

function ShaperEncounter:onWipe()
    OsseinCageCommon.reset()
    self.shaperShielded = false
end

function ShaperEncounter:onUpdate(context, alerts)
    -- Line 1: Shaper shield status
    if self.shaperShielded then
        alerts:setRow(1, Fmt.c("AA44FF", Lang.t("oc_shaper_shielded_info")), nil)
    else
        alerts:clearRow(1)
    end
    alerts:clearRow(2)
    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

package.loaded["trial.oc.boss.ShaperEncounter"] = ShaperEncounter
return ShaperEncounter
