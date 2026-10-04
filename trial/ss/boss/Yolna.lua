--- Yolnahkriin  -  Sunspire boss 2 (Fire)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-4: Yolna-specific mechanics
---   AtroSpawn (119549): BEGIN -> "Kill Atro!" banner, 4.5 s
---   LavaGeyser (124546): player or nearby group (dist < 2.8) -> Dodge! bar
---   NextFlare (121722 / 121459): fight-start +6s / BEGIN +32s / EFFECT_FADED +30s
---   Cataclysm (122598): cast duration CA bar + landing = cataEnd + 6.8 s
---   Takeoff (124910/124915/124916): HP-threshold takeoff events -> landing
---     countdown (+22.8 / +23.4 / +23.5 s), replacing pure HP-window guessing
---   AimOff (125693): re-arms the current bracket's takeoff landing (Crutch
---     OnYolFly branch: <30% -> 23.5, <55% -> 23.4, <80% -> 22.8)
---   Boss HP thresholds: 76% / 51% / 26% -> "Can Fly In X%"

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local MapUtils       = require("lib.MapUtils")
local Timer          = require("lib.Timer")
local Lang           = require("core.Lang")
local Fmt            = require("core.Fmt")
local CA             = require("external-api.CombatAlerts")
local CastDur        = require("lib.CastDur")
local Colors         = require("core.Colors")
local AlertTypes     = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")


-- -- Ability IDs ------------------------------------------------------------
local ATRO_SPAWN    = 119549   -- beginCast: Kill Atro alert
local LAVA_GEYSER   = 124546   -- beginCast: Dodge alert (player/nearby)
local NEXT_FLARE_A  = 121722   -- beginCast: nextFlareTime +32s
local NEXT_FLARE_B  = 121459   -- combatEvent.other: ACTION_RESULT_EFFECT_FADED -> nextFlareTime +30s
local CATACLYSM     = 122598   -- beginCast: caAlertCast + landing timer
local TAKEOFF_75    = 124910   -- beginCast/other: takeoff at 76% bracket -> landing +22.8 s
local TAKEOFF_50    = 124915   -- beginCast/other: takeoff at 51% bracket -> landing +23.4 s
local TAKEOFF_25    = 124916   -- beginCast/other: takeoff at 26% bracket -> landing +23.5 s
local AIM_OFF       = 125693   -- combatEvent.other EFFECT_GAINED: aim-off re-arms current-bracket takeoff


-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_GEYSER_DUR = 2500   -- LavaGeyser: empirical
local FALLBACK_CATA_DUR   = 4600   -- Cataclysm: empirical (~4.6 s)

-- Tracker-row strings built once at load; the 200 ms loop never calls
-- Fmt.c / Lang.t (see Lokke.lua for the same pattern).
local _STR_NEXT_FLARE  = Fmt.c(Fmt.CRIMSON, Lang.t("ss_yolna_next_flare"))
local _STR_CATA_ENDS   = Fmt.c(Fmt.CRIMSON, Lang.t("ss_yolna_cataclysm_ends"))
local _STR_LANDING     = Fmt.c(Fmt.LANDING, Lang.t("ss_landing"))
local _STR_CAN_FLY_PFX = Lang.t("ss_can_fly_in")

-- -- Boss definition -------------------------------------------------------
local Yolna = {}
Yolna.__index = Yolna
setmetatable(Yolna, {__index = BossBase})

Yolna.key  = "yolna"
Yolna.name = "Yolnahkriin"   -- TODO: verify via GetUnitName in-game
-- location: Sunspire arena is one shared room for all three bosses  -  a single AABB
-- would be ambiguous.  Name-based detection is intentional; name is well-established
-- EN string (same client since Elsweyr launch), non-EN risk is low.
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- To measure: enter vet HM, then /script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))
-- Set threshold between the vet and HM values, recording both in a trailing comment
-- (see AnsuulEncounter.lua for the convention).  /incha debug also prints the resolved
-- difficulty with the pool it compared, so one pull yields the numbers automatically.
Yolna.hmHealthThreshold = math.huge

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

-- -- Handlers (new-style: boss as first arg, sourceUnitName before unit args) --

local function handleAtroSpawn(boss, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ss_yolna_kill_atro"))
    CA.alert(nil, Lang.t("ss_yolna_kill_atro"), 0xFF8000FF, SOUNDS.NONE, 4500)
end

local function handleLavaGeyser(boss, context, alerts, abilityId, sourceUnitName,
                                 unitTag, unitId, sourceUnitId, unitName)
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

-- NextFlare: BEGIN -> +32 s
local function handleNextFlareA(boss, context, alerts, abilityId, ...)
    boss.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 32
end

-- NextFlare: EFFECT_FADED (via COMBAT_EVENT, combatEvent.other) -> +30 s
local function handleNextFlareB(boss, context, alerts, abilityId, ...)
    boss.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 30
end

-- Takeoff landing times (seconds) — CrutchAlerts Sunspire.lua:300/322/344
-- (DisplayDamageable(22.8 / 23.4 / 23.5) in OnYolFly75/50/25).  HYPOTHESIS_REF_ONLY:
-- one reference, no SS log lines for these ids yet; ss.log has zero takeoff events.
local TAKEOFF_LAND_75 = 22.8   -- takeoff at the 76% HP bracket
local TAKEOFF_LAND_50 = 23.4   -- takeoff at the 51% HP bracket
local TAKEOFF_LAND_25 = 23.5   -- takeoff at the 26% HP bracket

-- Takeoff events land a fixed time after the boss lifts off; the row-4
-- landing renderer (showLandingOrFlyLine) already reads landingTimer, so
-- arming it here is the whole alert.  No CA bar: Crutch shows a damageable
-- countdown, the tracker row is Incha's equivalent.
local function handleTakeoff(boss, context, alerts, abilityId, landingSec, ...)
    boss.landingTimer:reset(landingSec)
end

local function handleTakeoff75(boss, context, alerts, abilityId, ...)
    handleTakeoff(boss, context, alerts, abilityId, TAKEOFF_LAND_75)
end

local function handleTakeoff50(boss, context, alerts, abilityId, ...)
    handleTakeoff(boss, context, alerts, abilityId, TAKEOFF_LAND_50)
end

local function handleTakeoff25(boss, context, alerts, abilityId, ...)
    handleTakeoff(boss, context, alerts, abilityId, TAKEOFF_LAND_25)
end

-- AimOff (125693): Yolna re-acquires aim without a threshold-crossing event;
-- Crutch's OnYolFly (Sunspire.lua:363-372) re-arms by current HP bracket with
-- the same three landing times.  HP brackets here use Crutch's branch points
-- (30/55/80), not Incha's can-fly thresholds (26/51/76): the re-arm decides
-- which fly we are mid-, and Crutch's numbers are the only ref evidence.
local function handleAimOff(boss, context, alerts, abilityId, ...)
    local hp = context.healthPercent or 100
    if     hp < 30 then boss.landingTimer:reset(TAKEOFF_LAND_25)
    elseif hp < 55 then boss.landingTimer:reset(TAKEOFF_LAND_50)
    elseif hp < 80 then boss.landingTimer:reset(TAKEOFF_LAND_75)
    end
    -- >= 80%: no takeoff has happened yet, nothing to re-arm.
end

local function handleCataclysm(boss, context, alerts, abilityId, ...)
    local dur = CastDur.get(CATACLYSM, FALLBACK_CATA_DUR)
    boss.cataTimer:reset(dur / 1000)
    boss.landingTimer:reset(dur / 1000 + 6.8)
    CA.castAlertsStop(boss.cataBarId)
    boss.cataBarId = CA.bar(
        abilityId, "Cataclysm",
        dur, dur, Colors.FIRE, 0.5,
        { dur, "Cata Ends!", 0.9, 0.2, 0.1, 0.9, SOUNDS.NONE })
end

-- -- Events table (replaces combatRoutes) ----------------------------------
-- NEXT_FLARE_B fires via ACTION_RESULT_EFFECT_FADED on COMBAT_EVENT;
-- kept in combatEvent.other to preserve the same event path as the original.

local _beginCastEntry = {
    [ATRO_SPAWN]   = { type = AlertTypes.CUSTOM, fn = handleAtroSpawn },
    [LAVA_GEYSER]  = { type = AlertTypes.CUSTOM, fn = handleLavaGeyser },
    [NEXT_FLARE_A] = { type = AlertTypes.CUSTOM, fn = handleNextFlareA },
    [CATACLYSM]    = { type = AlertTypes.CUSTOM, fn = handleCataclysm },
    -- Takeoffs are scripted casts: Crutch registers them with result=nil
    -- (Sunspire.lua:491-493), i.e. fires on the BEGIN F/T pair — that is the
    -- beginCast path here.  instant+started both armed so the landing timer
    -- starts whether the engine reports them as instant or as a timed cast.
    [TAKEOFF_75]   = { type = AlertTypes.CUSTOM, fn = handleTakeoff75 },
    [TAKEOFF_50]   = { type = AlertTypes.CUSTOM, fn = handleTakeoff50 },
    [TAKEOFF_25]   = { type = AlertTypes.CUSTOM, fn = handleTakeoff25 },
}

for k, v in pairs(SunspireCommon.beginCastEntries) do
    _beginCastEntry[k] = v
end

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

Yolna.events = {
    beginCast = {
        instant = _beginCastInstant,
        started = _beginCastStarted,
    },
    combatEvent = {
        other = {
            [NEXT_FLARE_B] = { type = AlertTypes.CUSTOM, fn = handleNextFlareB },
            -- Crutch registers AimOff with ACTION_RESULT_EFFECT_GAINED on
            -- COMBAT_EVENT (Sunspire.lua:494); that result has no dedicated
            -- bucket, so combatEvent.other is Incha's equivalent path.
            [AIM_OFF]      = { type = AlertTypes.CUSTOM, fn = handleAimOff },
        },
    },
}

EventDispatcher.build(Yolna)

-- -- Tracker-row renderers -------------------------------------------------

-- Row 1: NextFlare countdown.
local function showFlareLine(self, alerts, now)
    if self.nextFlareTime > 0 then
        local T = self.nextFlareTime - now
        if T > 0 then
            alerts:setRow(1, _STR_NEXT_FLARE, T)
        else
            alerts:clearRow(1)   -- brief gap between flares; CombatAlerts handles the visible warning
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Cataclysm channel — time remaining until channel ends.
local function showCataLine(self, alerts, now)
    local cataLeft = self.cataTimer:remainingAt(now)
    if cataLeft > 0 then
        alerts:setRow(2, _STR_CATA_ENDS, cataLeft)
    else
        alerts:clearRow(2)
    end
end

-- Row 4: Landing countdown → HP can-fly threshold.
local function showLandingOrFlyLine(self, alerts, context, now)
    local landing = self.landingTimer:remainingAt(now)
    if landing > 0 then
        alerts:setRow(4, _STR_LANDING, landing)
    else
        local hp = context.healthPercent
        if hp and hp > 25 then
            local flyAt
            if     hp >= 76 then flyAt = 76
            elseif hp >= 51 then flyAt = 51
            elseif hp >= 26 then flyAt = 26
            end
            if flyAt and (hp - flyAt) <= 5 then
                -- hp moves in 0.1% steps; this string only exists inside a 5% window.
                alerts:setRow(4, Fmt.c(Fmt.FLYZONE, _STR_CAN_FLY_PFX .. Fmt.pct(hp - flyAt, 1)), nil)
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
    showCataLine(self, alerts, now)
    alerts:clearRow(3)
    showLandingOrFlyLine(self, alerts, context, now)
end

package.loaded["trial.ss.boss.Yolna"] = Yolna
return Yolna
