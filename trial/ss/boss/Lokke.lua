--- Lokkestiiz  -  Sunspire boss 1 (Ice)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-3: Lokke-specific mechanics
---   GlacialFist . IceTomb state machine . LokkeLaser / landing . HP fly thresholds

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local Lang           = require("core.Lang")
local Fmt            = require("core.Fmt")
local MapUtils       = require("lib.MapUtils")
local CA             = require("external-api.CombatAlerts")
local CastDur        = require("lib.CastDur")
local Colors = require("core.Colors")


-- -- Ability IDs ------------------------------------------------------------
local GLACIAL_FIST    = 120838   -- combatRoute: ACTION_RESULT_BEGIN -> Block alert (player/nearby 4.5m)
local ICE_TOMB        = 119632   -- combatRoute: ACTION_RESULT_BEGIN -> start tomb cycle
local IN_ICE          = 116044   -- combatRoute: ACTION_RESULT_EFFECT_GAINED / FADED -> player in/out tomb
local LASER_1         = 122820   -- combatRoute: ACTION_RESULT_BEGIN -> laser 40s + landing 12.8s
local LASER_2         = 122821   -- combatRoute: ACTION_RESULT_BEGIN -> laser 10s + landing 54.6s
local LASER_3         = 122822   -- combatRoute: ACTION_RESULT_BEGIN -> laser 32s + landing 32.1s
local ICE_EFFECT_CAST = 124687   -- effectRoute: EFFECT_RESULT_GAINED -> TombCast signal
local ICE_EFFECT_ARM  = 119638   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> TombArmed / TombFaded

-- -- IceTomb row prefixes (coloured at module load; structural) --
local sA = Lang.t("ss_lokke_tomb_slot_a")
local sB = Lang.t("ss_lokke_tomb_slot_b")

-- Full tomb names resolved once at load; no %s substitution at runtime.
local TOMB_NAMES = {
    [1] = Lang.t("ss_lokke_tomb_name_1"),
    [2] = Lang.t("ss_lokke_tomb_name_2"),
    [3] = Lang.t("ss_lokke_tomb_name_3"),
}

local NEXT_TOMB = { [0]=1, [1]=2, [2]=3, [3]=1 }   -- iceNumber -> next label

local function newTombSlots()
    return {
        [1] = { time=0, cast=false, armed=false, taken=false, clear=false, unit=0 },
        [2] = { time=0, cast=false, armed=false, taken=false, clear=false, unit=0 },
    }
end

-- Write one active-tomb slot to a tracker row.
-- slot: the iceTomb slot table.  prefix: "[A] " / "[B] ".  now: current time (s).
local function setTombSlotRow(alerts, n, prefix, slot, now)
    if not slot.cast then alerts:clearRow(n); return end
    if slot.clear then
        alerts:setRow(n, prefix .. Fmt.c(Fmt.GREEN,  Lang.t("ss_lokke_tomb_done")), nil)
        return
    end
    local t = slot.time - now
    if t <= 0 then alerts:clearRow(n); return end
    if slot.taken then
        alerts:setRow(n, prefix .. Fmt.c(Fmt.CYAN,  Lang.t("ss_lokke_tomb_heal")), t)
    elseif slot.armed then
        alerts:setRow(n, prefix .. Fmt.c(Fmt.CRIMSON,  Lang.t("ss_lokke_tomb_take")), t)
    else
        alerts:setRow(n, prefix .. Fmt.c(Fmt.CYAN,  Lang.t("ss_lokke_tomb_inc")), nil)
    end
end

-- -- IceTomb state-machine transitions (take self explicitly) -------------
local function clearTombs(self)
    self.tCast       = 0
    self.tArmed      = 0
    self.tFaded      = 0
    self.iGained     = 0
    self.iFaded      = 0
    self.tombsClear  = true
    self.iceDouble   = false
    self.checkDouble = true
    self.iceTomb     = newTombSlots()
end

local function tombCast(self, time)
    self.tCast = self.tCast + 1
    local slot = self.iceTomb[self.tCast]
    if not slot then return end
    slot.cast = true
    slot.time = time
end

local function tombArmed(self)
    self.tArmed = self.tArmed + 1
    local slot = self.iceTomb[self.tArmed]
    if not slot then return end
    slot.armed = true
    slot.time  = GetGameTimeMilliseconds() / 1000 + 10
end

local function tombFaded(self)
    self.tFaded = self.tFaded + 1

    -- Detect double-tomb: both arm windows closed but only 1 player entered.
    -- 100 ms delay lets iceGained settle before we read iGained.
    if self.checkDouble and self.tFaded == 2 and self.iceTomb[2].unit == 0 then
        self.checkDouble = false
        self:after(100, function()
            self.iceDouble = (self.iGained == 1)
        end)
    end

    local slot = self.iceTomb[self.tFaded]
    if not slot then return end
    slot.armed = false
end

local function iceGained(self, unitId)
    self.iGained = self.iGained + 1
    local slot = self.iceTomb[self.iGained]
    if not slot then return end
    slot.time   = GetGameTimeMilliseconds() / 1000 + 8
    slot.taken  = true
    if unitId and unitId ~= 0 then slot.unit = unitId end
end

local function iceFaded(self, unitId)
    self.iFaded = self.iFaded + 1
    local taken, clear = 0, 0
    for _, v in pairs(self.iceTomb) do
        if unitId and v.unit == unitId then v.clear = true end
        if v.clear then clear = clear + 1 end
        if v.taken then taken = taken + 1 end
    end
    if (clear == 2) or (self.tFaded == 2 and taken == 1) or (clear == 1 and self.iceDouble) then
        clearTombs(self)
    end
end

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_FIST_DUR = 1500   -- GlacialFist: empirical

-- -- Boss definition -------------------------------------------------------
local Lokke = {}
Lokke.__index = Lokke
setmetatable(Lokke, {__index = BossBase})

Lokke.key  = "lokke"
Lokke.name = Lang.t("boss_lokkestiiz")
-- location: Sunspire arena is one shared room for all three bosses  -  a single AABB
-- would be ambiguous.  Name-based detection is intentional; name is well-established
-- EN string (same client since Elsweyr launch), non-EN risk is low.
-- hmHealthThreshold: measure in-game

Lokke.stateSchema = {
    -- alertList: [sourceUnitId] -> CA bar ID
    alertList    = function() return {} end,
    -- IceTomb machine
    iceNumber    = 0,
    iceNext      = 0,
    tombsClear   = true,
    iceDouble    = false,
    checkDouble  = true,
    tCast        = 0,
    tArmed       = 0,
    tFaded       = 0,
    iGained      = 0,
    iFaded       = 0,
    iceTomb      = function() return newTombSlots() end,
    -- Laser / landing
    laserTime      = 0,
    landingTime    = 0,
    -- CA bar handle for the in-flight laser bar.
    laserBarId     = false,
    -- zo_callLater handle for the 10 s airborne ice-counter reset.
    -- Stored so onLeave can cancel it if the zone is exited mid-flight.
    laserResetTimer = false,
}

function Lokke.new()
    return BossBase.fromSchema(Lokke)
end

-- -- Lifecycle -------------------------------------------------------------

local function lokke_cleanup(self)
    self:cleanupAlertList()
    CA.castAlertsStop(self.laserBarId)
    self.laserBarId = false
    self:cancelAfter(self.laserResetTimer)
    self.laserResetTimer = false
end

function Lokke:onLeave(context)
    lokke_cleanup(self)
end

-- Soft reset on wipe: cancel bars immediately so they don't linger while
-- the group runs back.  Ice/laser display state resets to zero so the next
-- pull's onUpdate starts clean.
function Lokke:onWipe(context, alerts)
    lokke_cleanup(self)
    self.laserTime   = 0
    self.landingTime = 0
    self.iceNumber   = 0
    clearTombs(self)
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared cross-trial mechanic handler.
Lokke.common = SunspireCommon

-- Laser flight: closes over the per-flight timing constants.
local function makeLaserHandler(laserDelay, landingAfterLaser)
    return { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local now = GetGameTimeMilliseconds() / 1000
        CA.castAlertsStop(self.laserBarId)
        self.laserTime   = now + laserDelay
        self.landingTime = self.laserTime + landingAfterLaser
        self.laserBarId  = CA.bar(
            abilityId, "Laser",
            laserDelay * 1000, laserDelay * 1000, Colors.FLYZONE, 0.5,
            { laserDelay * 1000, "LASER!", 1, 0.5, 0, 0.9, SOUNDS.NONE })
        -- Reset iceNumber once boss is airborne (~10 s in).
        -- Store the handle so onLeave can cancel it on zone exit.
        self:cancelAfter(self.laserResetTimer)
        self.laserResetTimer = self:after(10000, function()
            self.laserResetTimer = false
            self.iceNumber = 0
        end)
    end }
end

local function handleGlacialFist(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local show = false
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            show = true
        else
            show = MapUtils.isGroupMemberNearby(unitTag, 4.5)
        end
    end
    if show then
        alerts:showAction(Lang.t("ss_lokke_block_glacial"))
        local dur = CastDur.get(GLACIAL_FIST, FALLBACK_FIST_DUR)
        local cid = CA.melee(abilityId, sourceUnitName, dur, Colors.ICE)
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    end
end

local function handleIceTomb(self, context, alerts, abilityId, ...)
    -- Reset any unresolved state from the previous cycle before starting
    -- this one.  Normally iceFaded calls clearTombs() to clean up, but if
    -- the tomb resolved abnormally (player died inside, no IN_ICE FADED)
    -- the counters would otherwise carry over and corrupt the new cycle.
    clearTombs(self)
    self.iceNext    = GetGameTimeMilliseconds() / 1000 + 23
    self.iceNumber  = self.iceNumber % 3 + 1
    self.tombsClear = false
end

-- InIce: player enters (EFFECT_GAINED) / exits (EFFECT_FADED) a tomb.
local function handleInIce(self, context, alerts, result, abilityId,
                            unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        iceGained(self, unitId)
    elseif result == ACTION_RESULT_EFFECT_FADED then
        iceFaded(self, unitId)
    end
end

-- 124687: cast signal (GAINED = tomb is being cast)
local function handleIceEffectCast(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        tombCast(self, GetGameTimeMilliseconds() / 1000)
    end
end

-- 119638: arm/disarm signal (GAINED = tomb ready to enter, FADED = window closed)
local function handleIceEffectArm(self, context, alerts, changeType, abilityId, ...)
    if     changeType == EFFECT_RESULT_GAINED then tombArmed(self)
    elseif changeType == EFFECT_RESULT_FADED  then tombFaded(self)
    end
end

Lokke.combatRoutes = {
    [GLACIAL_FIST] = { result = ACTION_RESULT_BEGIN, fn = handleGlacialFist },
    [ICE_TOMB]     = { result = ACTION_RESULT_BEGIN, fn = handleIceTomb },
    [IN_ICE]       = handleInIce,
    [LASER_1]      = makeLaserHandler(40,   12.8),
    [LASER_2]      = makeLaserHandler(10,   54.6),
    [LASER_3]      = makeLaserHandler(32,   32.1),
}

Lokke.effectRoutes = {
    [ICE_EFFECT_CAST] = handleIceEffectCast,
    [ICE_EFFECT_ARM]  = handleIceEffectArm,
}

-- -- Info-line renderers ---------------------------------------------------

-- Row 4: Laser → Landing → HP can-fly threshold.
local function showLaserLandingLine(self, alerts, now, context)
    local laser   = self.laserTime   - now
    local landing = self.landingTime - now
    if laser > 0 then
        alerts:setRow(4, Fmt.c(Fmt.AQUA,   Lang.t("ss_lokke_laser")), laser)
    elseif landing > 0 then
        alerts:setRow(4, Fmt.c(Fmt.LANDING, Lang.t("ss_landing")),     landing)
    else
        local hp = context.healthPercent
        if hp and hp > 20 then
            local flyAt
            if     hp >= 81 then flyAt = 81
            elseif hp >= 51 then flyAt = 51
            elseif hp >= 21 then flyAt = 21
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

-- Rows 1–3: Ice Tomb — upcoming countdown, then active slot states.
local function showIceTombLines(self, alerts, now)
    local isFlying = (self.iceNumber == 0)
        or (self.laserTime   > 0 and now < self.laserTime)
        or (self.landingTime > 0 and now < self.landingTime)

    if self.tombsClear then
        if isFlying or not IsUnitInCombat("player") then
            alerts:clearRow(1); alerts:clearRow(2); alerts:clearRow(3)
        else
            local T2 = self.iceNext - now
            local iN = NEXT_TOMB[self.iceNumber]
            local label = Fmt.c(Fmt.CYAN, TOMB_NAMES[iN] or "")
            if T2 <= 0 then
                -- Tomb cast window is here.  Row stays with no ETA (INC tag).
                alerts:setRow(1, label .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
            else
                alerts:setRow(1, label, T2)
            end
            alerts:clearRow(2); alerts:clearRow(3)
        end
    else
        -- Active tomb: header + one or two slot rows.
        local header = Fmt.c(Fmt.CYAN, TOMB_NAMES[self.iceNumber] or "")
        alerts:setRow(1, header, nil)
        setTombSlotRow(alerts, 2, sA, self.iceTomb[1], now)
        if self.iceDouble then
            alerts:setRow(3, sB .. Fmt.c(Fmt.GREEN, Lang.t("ss_lokke_tomb_double")), nil)
        else
            setTombSlotRow(alerts, 3, sB, self.iceTomb[2], now)
        end
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Lokke:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showLaserLandingLine(self, alerts, now, context)
    showIceTombLines(self, alerts, now)
end

package.loaded["trial.ss.boss.Lokke"] = Lokke
return Lokke
