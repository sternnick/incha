--- Yolnahkriin  -  Sunspire boss 2 (Fire)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-4: Yolna-specific mechanics
---   AtroSpawn (119549): BEGIN -> "Kill Atro!" banner, 4.5 s
---   LavaGeyser (124546): player or nearby group (dist < 2.8) -> Dodge! bar
---   NextFlare (121722 / 121459): fight-start +6s / BEGIN +32s / EFFECT_FADED +30s
---   Cataclysm (122598): cast duration CA bar + landing = cataEnd + 6.8 s
---   Boss HP thresholds: 76% / 51% / 26% -> "Can Fly In X%"

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local MapUtils       = require("lib.MapUtils")
local Timer          = require("lib.Timer")
local Lang           = require("core.Lang")
local Fmt            = require("core.Fmt")


-- -- Ability IDs ------------------------------------------------------------
local ATRO_SPAWN    = 119549   -- combatRoute: ACTION_RESULT_BEGIN -> Kill Atro alert
local LAVA_GEYSER   = 124546   -- combatRoute: ACTION_RESULT_BEGIN -> Dodge alert (player/nearby)
local NEXT_FLARE_A  = 121722   -- combatRoute: ACTION_RESULT_BEGIN -> nextFlareTime +32s
local NEXT_FLARE_B  = 121459   -- combatRoute: ACTION_RESULT_EFFECT_FADED -> nextFlareTime +30s
local CATACLYSM     = 122598   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast + landing timer

local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")


-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_GEYSER_DUR = 2500   -- LavaGeyser: empirical
local FALLBACK_CATA_DUR   = 4600   -- Cataclysm: empirical (~4.6 s)

-- -- Boss definition -------------------------------------------------------
local Yolna = {}
Yolna.__index = Yolna
setmetatable(Yolna, {__index = BossBase})

Yolna.key  = "yolna"
Yolna.name = Lang.t("boss_yolnahkriin")
-- location: Sunspire arena is one shared room for all three bosses  -  a single AABB
-- would be ambiguous.  Name-based detection is intentional; name is well-established
-- EN string (same client since Elsweyr launch), non-EN risk is low.

Yolna.stateSchema = {
    alertList     = function() return {} end,
    nextFlareTime = 0,
    cataTimer     = function() return Timer.new(FALLBACK_CATA_DUR / 1000) end,
    landingTimer  = function() return Timer.new(FALLBACK_CATA_DUR / 1000 + 6.8) end,
    -- CA bar handle for the in-flight cataclysm bar.
    cataBarId     = false,
}

function Yolna.new()
    return BossBase.fromSchema(Yolna)
end

-- -- Lifecycle -------------------------------------------------------------

local function yolna_cleanup(self)
    self:cleanupAlertList()
    CA.castAlertsStop(self.cataBarId)
    self.cataBarId = false
end

function Yolna:onLeave(context)
    yolna_cleanup(self)
end

-- Soft reset on wipe: cancel bars immediately and clear timer display so
-- the UI starts clean on the next pull.
function Yolna:onWipe(context, alerts)
    yolna_cleanup(self)
    self.nextFlareTime = 0
    self.cataTimer:clear()
    self.landingTimer:clear()
end

-- -- Combat state (fight start / wipe) -------------------------------------
-- Called when EVENT_PLAYER_COMBAT_STATE changes.
-- On fight start (inCombat=true) set the first NextFlare at +6 s (HTS empirical).
function Yolna:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 6
    end
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared cross-trial mechanic handler.
Yolna.common = SunspireCommon

-- -- Handlers ------------------------------------------------------------

local function handleAtroSpawn(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ss_yolna_kill_atro"))
    CA.alert(nil, "Kill Atro!", 0xFF8000FF, SOUNDS.NONE, 4500)
end

local function handleLavaGeyser(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    local show = false
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            show = true
        else
            show = MapUtils.isGroupMemberNearby(unitTag, 2.8)
        end
    end
    if show then
        alerts:showAction(Lang.t("ss_yolna_dodge_geyser"))
        local dur = CastDur.get(LAVA_GEYSER, FALLBACK_GEYSER_DUR)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
    end
end

-- NextFlare: BEGIN -> +32 s; EFFECT_FADED -> +30 s.
local function handleNextFlareA(self, context, alerts, abilityId, ...)
    self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 32
end

local function handleNextFlareB(self, context, alerts, abilityId, ...)
    self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 30
end

local function handleCataclysm(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(CATACLYSM, FALLBACK_CATA_DUR)
    self.cataTimer:reset(dur / 1000)
    self.landingTimer:reset(dur / 1000 + 6.8)
    CA.castAlertsStop(self.cataBarId)
    self.cataBarId = CA.bar(
        abilityId, "Cataclysm",
        dur, dur, Colors.FIRE, 0.5,
        { dur, "Cata Ends!", 0.9, 0.2, 0.1, 0.9, SOUNDS.NONE })
end

Yolna.combatRoutes = {
    [ATRO_SPAWN]   = { result = ACTION_RESULT_BEGIN,          fn = handleAtroSpawn },
    [LAVA_GEYSER]  = { result = ACTION_RESULT_BEGIN,          fn = handleLavaGeyser },
    [NEXT_FLARE_A] = { result = ACTION_RESULT_BEGIN,          fn = handleNextFlareA },
    [NEXT_FLARE_B] = { result = ACTION_RESULT_EFFECT_FADED,   fn = handleNextFlareB },
    [CATACLYSM]    = { result = ACTION_RESULT_BEGIN,          fn = handleCataclysm },
}

-- -- Tracker-row renderers -------------------------------------------------

-- Row 1: NextFlare countdown.
local function showFlareLine(self, alerts, now)
    if self.nextFlareTime > 0 then
        local T = self.nextFlareTime - now
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.CRIMSON, Lang.t("ss_yolna_next_flare")), T)
        else
            alerts:clearRow(1)   -- brief gap between flares; CombatAlerts handles the visible warning
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Cataclysm channel — time remaining until channel ends.
local function showCataLine(self, alerts)
    local cataLeft = self.cataTimer:remaining()
    if cataLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.CRIMSON, Lang.t("ss_yolna_cataclysm_ends")), cataLeft)
    else
        alerts:clearRow(2)
    end
end

-- Row 4: Landing countdown → HP can-fly threshold.
local function showLandingOrFlyLine(self, alerts, context)
    local landing = self.landingTimer:remaining()
    if landing > 0 then
        alerts:setRow(4, Fmt.c(Fmt.LANDING, Lang.t("ss_landing")), landing)
    else
        local hp = context.healthPercent
        if hp and hp > 25 then
            local flyAt
            if     hp >= 76 then flyAt = 76
            elseif hp >= 51 then flyAt = 51
            elseif hp >= 26 then flyAt = 26
            end
            if flyAt and (hp - flyAt) <= 5 then
                alerts:setRow(4, Fmt.c(Fmt.FLYZONE, Lang.t("ss_can_fly_in") .. Fmt.pct(hp - flyAt, 1)), nil)
            else
                alerts:clearRow(4)
            end
        else
            alerts:clearRow(4)
        end
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Yolna:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showFlareLine(self, alerts, now)
    showCataLine(self, alerts)
    alerts:clearRow(3)
    showLandingOrFlyLine(self, alerts, context)
end

package.loaded["trial.ss.boss.Yolna"] = Yolna
return Yolna
