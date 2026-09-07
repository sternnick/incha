--- Nahviintaas  -  Sunspire boss 3 (Lightning / Portal)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-5: Nahvii-specific mechanics
---   PowerfulSlam (120542): player or nearby (dist <= 7); CA countdown list
---   Stonefist (120567): player-targeted; CA countdown list
---   SweepingBreath (120188 / 118743): directional caAlert
---   Thrash (118562): CA cast bar + nudge NextMeteor -1.5 s
---   SoulTear (117526): 2 s caAlert "SOUL TEAR"
---   FireStorm (118884): skip-first; stormTime +13.7 s, landing +6.6 s
---   NextMeteor (117251/123067 EFFECT_GAINED_DURATION -> +14.5 s; 117308 BEGIN -> +10.5 s)
---   MarkForDeath (117938): nudge NextMeteor +1.5 s
---   Portal (121676): 14 s window + 98 s wipe countdown
---   PortalInterrupt (121436): interrupt countdown -> 20 s pins after bash
---   PortalEnter/Exit (121213/121254): inPortal state; suppress HP display
---   WipeFinished (121216): EFFECT_FADED clears wipe timer
---   NegateField (121411): player-targeted 2.5 s banner
---   Meteor targets (117251/123067): display targeted players for 4 s
---   Boss HP thresholds: 80% / 60% / 40% -> "Can Fly In X%" (suppressed in portal)

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local MapUtils       = require("lib.MapUtils")
local Timer          = require("lib.Timer")
local Lang           = require("core.Lang")
local Fmt            = require("core.Fmt")


-- -- Ability IDs ------------------------------------------------------------
local POWERFUL_SLAM    = 120542   -- combatRoute: ACTION_RESULT_BEGIN -> Block alert (player/nearby 7m)
local STONEFIST        = 120567   -- combatRoute: ACTION_RESULT_BEGIN -> Block alert (player only)
local SWEEP_RIGHT      = 120188   -- combatRoute: ACTION_RESULT_BEGIN -> >>> Sweep Breath alert
local SWEEP_LEFT       = 118743   -- combatRoute: ACTION_RESULT_BEGIN -> <<< Sweep Breath alert
local THRASH           = 118562   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast; nextMeteor -1.5s
local SOUL_TEAR        = 117526   -- combatRoute: ACTION_RESULT_BEGIN -> SOUL TEAR alert
local FIRE_STORM       = 118884   -- combatRoute: ACTION_RESULT_BEGIN -> stormTime + 13.7s
local NEXT_METEOR_A    = 117251   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> +14.5s
local NEXT_METEOR_B    = 123067   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> +14.5s
local NEXT_METEOR_C    = 117308   -- combatRoute: ACTION_RESULT_BEGIN -> nextMeteor +10.5s
local MARK_FOR_DEATH   = 117938   -- combatRoute: ACTION_RESULT_BEGIN -> nextMeteor +1.5s
local PORTAL           = 121676   -- combatRoute: ACTION_RESULT_BEGIN -> portal 14s + wipe 98s
local PORTAL_ENTER     = 121213   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> inPortal
local PORTAL_EXIT      = 121254   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> exit portal
local PORTAL_INTERRUPT = 121436   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> interrupt timer
local WIPE_FINISHED    = 121216   -- combatRoute: ACTION_RESULT_EFFECT_FADED -> clear wipeTime
local NEGATE_FIELD     = 121411   -- combatRoute: ACTION_RESULT_BEGIN -> Dodge alert (player only)

local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")

-- -- CA colour palettes -----------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_SLAM_DUR      = 2000   -- PowerfulSlam / Stonefist: empirical
local FALLBACK_THRASH_DUR    = 2500   -- Thrash: empirical
local FALLBACK_INTERRUPT_DUR = 6000   -- PortalInterrupt: empirical

-- -- Boss definition -------------------------------------------------------
local Nahvii = {}
Nahvii.__index = Nahvii
setmetatable(Nahvii, {__index = BossBase})

Nahvii.key  = "nahvii"
Nahvii.name = Lang.t("boss_nahviintaas")
-- location: Sunspire arena is one shared room for all three bosses  -  a single AABB
-- would be ambiguous.  Name-based detection is intentional; name is well-established
-- EN string (same client since Elsweyr launch), non-EN risk is low.

Nahvii.stateSchema = {
    alertList           = function() return {} end,
    -- Meteor
    meteorTargets       = function() return {} end,
    meteorDisplayEnd_ms = 0,
    -- NextMeteor / Thrash
    nextMeteorTime      = 0,
    -- FireStorm / landing
    stormTime           = 0,
    landingTime         = 0,
    firstStormTrig      = true,
    -- Portal
    portalTime          = 0,
    wipeTime            = 0,
    cptPortal           = 0,
    inPortal            = false,
    -- Portal interrupt
    interruptTimer      = function() return Timer.new(FALLBACK_INTERRUPT_DUR / 1000) end,
    interruptUnitId     = false,
    pinsTime            = 0,
    -- CA bar handle for the in-flight thrash bar.
    thrashBarId         = false,
}

function Nahvii.new()
    return BossBase.fromSchema(Nahvii)
end

-- -- Lifecycle -------------------------------------------------------------

local function nahvii_cleanup(self)
    self:cleanupAlertList()
    CA.castAlertsStop(self.thrashBarId)
    self.thrashBarId = false
end

function Nahvii:onLeave(context)
    nahvii_cleanup(self)
end

-- Soft reset on wipe: cancel bars immediately and clear all countdown
-- display state so the UI starts clean on the next pull.
function Nahvii:onWipe(context, alerts)
    nahvii_cleanup(self)
    self.nextMeteorTime      = 0
    self.stormTime           = 0
    self.landingTime         = 0
    self.firstStormTrig      = true
    self.portalTime          = 0
    self.wipeTime            = 0
    self.cptPortal           = 0
    self.inPortal            = false
    self.interruptTimer:clear()
    self.interruptUnitId     = false
    self.pinsTime            = 0
    self.meteorTargets       = {}
    self.meteorDisplayEnd_ms = 0
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared cross-trial mechanic handler.
Nahvii.common = SunspireCommon

-- NextMeteor A+B share: EFFECT_GAINED_DURATION -> timer + target tracking;
-- EFFECT_FADED -> remove target entry.
local function handleNextMeteor(self, context, alerts, result, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 14.5
        if IsUnitPlayer(unitTag) and unitTag and unitTag ~= "" then
            local name
            if AreUnitsEqual("player", unitTag)
            then name = Fmt.c(Fmt.AMBER, "== YOU ==")
            else name = Fmt.c(Fmt.AMBER, GetUnitDisplayName(unitTag) or unitName or "?")
            end
            self.meteorTargets[unitTag] = name
            self.meteorDisplayEnd_ms = GetGameTimeMilliseconds() + 4000
            if AreUnitsEqual("player", unitTag) then
                alerts:showAction(Lang.t("ss_nahvii_you_meteor"))
                CA.alert(nil, "Meteor on YOU!", 0xFF2200FF, SOUNDS.NONE, 4000)
            end
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        if unitTag then self.meteorTargets[unitTag] = nil end
    end
end

local function handleNextMeteorC(self, context, alerts, abilityId, ...)
    self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 10.5
end

local function handleMarkForDeath(self, context, alerts, abilityId, ...)
    self.nextMeteorTime = self.nextMeteorTime + 1.5
end

local function handlePowerfulSlam(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local show = false
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            show = true
        else
            show = MapUtils.isGroupMemberNearby(unitTag, 7)
        end
    end
    if show then
        alerts:showAction(Lang.t("ss_nahvii_block_slam"))
        local dur = CastDur.get(POWERFUL_SLAM, FALLBACK_SLAM_DUR)
        local cid = CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    end
end

local function handleStonefist(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if not (IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag)) then return end
    alerts:showAction(Lang.t("ss_nahvii_block_stonefist"))
    local dur = CastDur.get(STONEFIST, FALLBACK_SLAM_DUR)
    local cid = CA.melee(abilityId, sourceUnitName, dur, Colors.AMBER)
    if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
end

local function handleSweepRight(self, context, alerts, abilityId, ...)
    local dir = Lang.t("ss_nahvii_sweep_right")
    alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
end

local function handleSweepLeft(self, context, alerts, abilityId, ...)
    local dir = Lang.t("ss_nahvii_sweep_left")
    alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
end

local function handleThrash(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(THRASH, FALLBACK_THRASH_DUR)
    CA.castAlertsStop(self.thrashBarId)
    self.thrashBarId = CA.bar(
        abilityId, "Thrash",
        dur, dur, Colors.RED, 0.5,
        { dur, "THRASH!", 0.9, 0.1, 0.1, 0.9, SOUNDS.NONE })
    if self.nextMeteorTime > 0 then
        self.nextMeteorTime = self.nextMeteorTime - 1.5
    end
end

local function handleSoulTear(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ss_nahvii_soul_tear"))
    CA.alert(nil, "SOUL TEAR!", 0x9966FFFF, SOUNDS.NONE, 2000)
end

local function handleFireStorm(self, context, alerts, abilityId, ...)
    if not self.firstStormTrig then
        self.firstStormTrig = true
        return
    end
    self.firstStormTrig = false
    local now        = GetGameTimeMilliseconds() / 1000
    self.stormTime   = now + 13.7
    self.landingTime = self.stormTime + 6.6
end

local function handlePortal(self, context, alerts, abilityId, ...)
    local now       = GetGameTimeMilliseconds() / 1000
    self.portalTime = now + 14
    self.wipeTime   = now + 98
    self.cptPortal  = 0
end

local function handlePortalEnter(self, context, alerts, abilityId, unitTag, ...)
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            self.inPortal  = true
            self.cptPortal = 0
        else
            self.cptPortal = self.cptPortal + 1
            if self.cptPortal >= 3 then
                self.inPortal  = true
                self.cptPortal = 0
            end
        end
    end
end

local function handlePortalExit(self, context, alerts, abilityId, unitTag, ...)
    if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
        self.inPortal        = false
        self.interruptTimer:clear()
        self.interruptUnitId = false
        self.pinsTime        = 0
    end
end

local function handlePortalInterrupt(self, context, alerts, abilityId,
                                     unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    local dur = CastDur.get(PORTAL_INTERRUPT, FALLBACK_INTERRUPT_DUR)
    self.interruptTimer:reset(dur / 1000)
    self.interruptUnitId = unitId
    self.pinsTime        = 0
end

local function handleWipeFinished(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_FADED then self.wipeTime = 0 end
end

local function handleNegateField(self, context, alerts, abilityId, unitTag, ...)
    if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
        alerts:showAction(Lang.t("ss_nahvii_dodge_negate"))
        CA.alert(nil, "Dodge Negate!", 0x9966FFFF, SOUNDS.NONE, 2500)
    end
end

Nahvii.combatRoutes = {
    [NEXT_METEOR_A]    = handleNextMeteor,
    [NEXT_METEOR_B]    = handleNextMeteor,
    [NEXT_METEOR_C]    = { result = ACTION_RESULT_BEGIN,                  fn = handleNextMeteorC },
    [MARK_FOR_DEATH]   = { result = ACTION_RESULT_BEGIN,                  fn = handleMarkForDeath },
    [POWERFUL_SLAM]    = { result = ACTION_RESULT_BEGIN,                  fn = handlePowerfulSlam },
    [STONEFIST]        = { result = ACTION_RESULT_BEGIN,                  fn = handleStonefist },
    [SWEEP_RIGHT]      = { result = ACTION_RESULT_BEGIN,                  fn = handleSweepRight },
    [SWEEP_LEFT]       = { result = ACTION_RESULT_BEGIN,                  fn = handleSweepLeft },
    [THRASH]           = { result = ACTION_RESULT_BEGIN,                  fn = handleThrash },
    [SOUL_TEAR]        = { result = ACTION_RESULT_BEGIN,                  fn = handleSoulTear },
    [FIRE_STORM]       = { result = ACTION_RESULT_BEGIN,                  fn = handleFireStorm },
    [PORTAL]           = { result = ACTION_RESULT_BEGIN,                  fn = handlePortal },
    [PORTAL_ENTER]     = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePortalEnter },
    [PORTAL_EXIT]      = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePortalExit },
    [PORTAL_INTERRUPT] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePortalInterrupt },
    [WIPE_FINISHED]    = handleWipeFinished,
    [NEGATE_FIELD]     = { result = ACTION_RESULT_BEGIN,                  fn = handleNegateField },
}

-- Catch-all fallback: bash detection has no abilityId filter and cannot be routed.
-- CombatHandler invokes this ONLY when abilityId is not in combatRoutes.
-- Catch-all guarded on a combat RESULT rather than an ability id, so it
-- cannot be reached through an ability-filtered registration.  Declaring the
-- results here lets EventPipeline give it a REGISTER_FILTER_COMBAT_RESULT
-- registration instead of forcing an unfiltered one for the whole trial.
Nahvii.combatResults = { ACTION_RESULT_INTERRUPT }

function Nahvii:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if result == ACTION_RESULT_INTERRUPT and unitId and unitId == self.interruptUnitId then
        self.interruptTimer:clear()
        self.interruptUnitId = false
        self.pinsTime        = GetGameTimeMilliseconds() / 1000 + 20
    end
end

-- -- Tracker-row renderers -------------------------------------------------

-- Row 1: NextMeteor countdown.
local function showNextMeteorLine(self, alerts, now)
    if self.nextMeteorTime > 0 then
        local T = self.nextMeteorTime - now
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.RED, Lang.t("ss_nahvii_next_meteor")), T)
        else
            alerts:clearRow(1)   -- meteor has hit; CombatAlerts handles the alert bar
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Portal window → Interrupt countdown → Pins countdown.
local function showPortalInterruptLine(self, alerts, now)
    local portalLeft = self.portalTime - now
    local interLeft  = self.interruptTimer:remaining()
    local pinsLeft   = self.pinsTime - now

    if interLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_interrupt_in")), interLeft)
    elseif pinsLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_next_pins")),    pinsLeft)
    elseif portalLeft >= 11 then
        -- Enough time has passed that the group should already be inside.
        alerts:setRow(2, Fmt.c(Fmt.RED,    Lang.t("ss_nahvii_portal_urgent")), portalLeft)
    elseif portalLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_portal")),        portalLeft)
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Meteor target names while display window is open; otherwise FireStorm countdown.
local function showMeteorOrStormLine(self, alerts, now, now_ms)
    if now_ms < self.meteorDisplayEnd_ms then
        local names = {}
        for _, name in pairs(self.meteorTargets) do
            names[#names + 1] = name
            if #names >= 3 then break end
        end
        -- Static name-column display: no ETA (targets, not a timer).
        alerts:setRow(3, #names > 0 and table.concat(names, "  ") or "", nil)
    else
        local storm = self.stormTime - now
        if storm >= 5.2 then
            alerts:setRow(3, Fmt.c(Fmt.CRIMSON, Lang.t("ss_nahvii_fire_storm_begin")), storm - 5.2)
        elseif storm >= 0 then
            alerts:setRow(3, Fmt.c(Fmt.CRIMSON, Lang.t("ss_nahvii_fire_storm_end")),   storm)
        else
            alerts:clearRow(3)
        end
    end
end

-- Row 4: Landing → Portal Wipe → HP can-fly threshold.
local function showLandingWipeLine(self, alerts, now, context)
    local landing  = self.landingTime - now
    local wipeLeft = self.wipeTime    - now

    if landing > 0 then
        alerts:setRow(4, Fmt.c(Fmt.LANDING, Lang.t("ss_landing")),          landing)
    elseif wipeLeft > 0 then
        alerts:setRow(4, Fmt.c(Fmt.VOID,    Lang.t("ss_nahvii_portal_wipe")), wipeLeft)
    elseif not self.inPortal then
        local hp = context.healthPercent
        if hp and hp > 39 then
            local flyAt
            if     hp >= 80 then flyAt = 80
            elseif hp >= 60 then flyAt = 60
            elseif hp >= 40 then flyAt = 40
            end
            if flyAt and (hp - flyAt) <= 5 then
                alerts:setRow(4, Fmt.c(Fmt.FLYZONE, Lang.t("ss_can_fly_in") .. Fmt.pct(hp - flyAt, 1)), nil)
            else
                alerts:clearRow(4)
            end
        else
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Nahvii:onUpdate(context, alerts)
    local now_ms = GetGameTimeMilliseconds()
    local now    = now_ms / 1000
    showNextMeteorLine(self, alerts, now)
    showPortalInterruptLine(self, alerts, now)
    showMeteorOrStormLine(self, alerts, now, now_ms)
    showLandingWipeLine(self, alerts, now, context)
end

package.loaded["trial.ss.boss.Nahvii"] = Nahvii
return Nahvii
