--- ReefGuardian  -  Dreadsail Reef boss 2
---
--- Phase DSR-4: full mechanics
---   BuildingStatic (163575 / 169688): GAINED/UPDATED/FADED -> stack tracker
---   VolatileResidue (174835 / 174932): GAINED/UPDATED/FADED -> stack tracker
---   Sheltered (163571): GAINED -> playerSheltered = true; FADED -> false
---   Heartburn (163692): BEGIN -> portal opened (reef opening begins)
---   HeartburnEffect (166036): EFFECT_GAINED -> 60 s wipe timer starts
---   AcidReflux (163702): BEGIN -> CastAlertsStart 10 s + 5 acid pool bars
---   CrabMonstrousClaw (166582): BEGIN + player -> AlertCast
---   Crush (166019) / Claw (166020): BEGIN + player -> AlertCast
---   CoralDriftBearCrackdown (166586): BEGIN + player -> AlertCast
---   KingOrnumFireDebuff (175832): EFFECT_GAINED + player -> Alert
---   AcidicVulnerability (174659): GAINED/FADED -> track for info4

local DreadsailCommon = require("trial.dsr.DreadsailCommon")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")


-- -- Ability IDs -----------------------------------------------------------
local BUILDING_STATIC_1    = 163575   -- effectRoute: EFFECT_RESULT_GAINED/UPDATED/FADED -> lightning stack tracker
local BUILDING_STATIC_2    = 169688   -- effectRoute: EFFECT_RESULT_GAINED/UPDATED/FADED -> lightning stack tracker
local VOLATILE_RESIDUE_1   = 174835   -- effectRoute: EFFECT_RESULT_GAINED/UPDATED/FADED -> poison stack tracker
local VOLATILE_RESIDUE_2   = 174932   -- effectRoute: EFFECT_RESULT_GAINED/UPDATED/FADED -> poison stack tracker
local SHELTERED            = 163571   -- effectRoute: EFFECT_RESULT_GAINED/FADED -> playerSheltered + clear stacks
local HEARTBURN            = 163692   -- combatRoute: ACTION_RESULT_BEGIN -> reef portal opens (60 s wipe timer)
local HEARTBURN_EFFECT     = 166036   -- effectRoute: EFFECT_RESULT_GAINED -> start reef wipe timer
local ACID_REFLUX          = 163702   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast 10 s + 5 pool alerts
-- 165987 (ACID_POOL)  -- reference: placed by Acid Reflux; no direct route needed
local CRAB_MONSTROUS_CLAW  = 166582   -- combatRoute: ACTION_RESULT_BEGIN -> handleHeavy (player caAlertCast)
local CRAB_SWIPE           = 166584   -- combatRoute: ACTION_RESULT_BEGIN -> handleHeavy (player caAlertCast)
local CRUSH                = 166019   -- combatRoute: ACTION_RESULT_BEGIN -> handleHeavy (player caAlertCast)
local CLAW_ATTACK          = 166020   -- combatRoute: ACTION_RESULT_BEGIN -> handleHeavy (player caAlertCast)
local CRACKDOWN            = 166586   -- combatRoute: ACTION_RESULT_BEGIN -> handleHeavy (player caAlertCast)
local KING_ORGNUM_FIRE_DBF = 175832   -- effectRoute: EFFECT_RESULT_GAINED (player) -> fire MOVE alert
local ACIDIC_VULN          = 174659   -- effectRoute: EFFECT_RESULT_GAINED/FADED (player) -> acidicVulnLast timer
local REPLICATION          = 163701   -- combatRoute: ACTION_RESULT_BEGIN -> Replication! alert

-- -- Timing constants -----------------------------------------------------
local PORTAL_WIPE_TIME     = 60       -- s: portal wipe timer after opening
local ACID_INTERVAL        = 1750     -- ms: acid pool spacing
local ACID_COUNT           = 5        -- number of acid pools per Reflux
local SHELTERED_WINDOW     = 3        -- s: keep "CLEANSED" label brief

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local Colors = require("core.Colors")

-- -- CA colour palettes ----------------------------------------------------
local ACT_ACID    = { 8000, "MOVE OUT!", 0.3, 0.9, 0.1, 0.9, nil }

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 1500   -- heavy melee (Crush/Claw/Crackdown): empirical

-- -- Boss definition -------------------------------------------------------
local ReefGuardian = {}
ReefGuardian.__index = ReefGuardian
ReefGuardian.common = DreadsailCommon   -- C3: common mechanic dispatch

ReefGuardian.key              = "reef_guardian"
ReefGuardian.name             = Lang.t("boss_reef_guardian")   -- TODO: verify via GetUnitName("boss1") in-game
-- location: arena AABB not yet captured  -  detection is name-based.
-- To add AABB: stand in arena, run /script d(GetUnitWorldPosition("boss1"))
ReefGuardian.hmHealthThreshold = 100000001         -- TODO: verify

ReefGuardian.stateSchema = {
    buildingStaticStacks   = 0,
    buildingStaticEndTime  = 0,
    volatileResidueStacks  = 0,
    volatileResidueEndTime = 0,
    playerSheltered        = false,
    lastShelteredTime      = 0,
    -- Reef portals: up to 3 can be open simultaneously.
    reefPortals   = function() return {} end,
    reefNum       = 0,
    acidicVulnLast  = 0,
    -- CA cast-bar handle for Acid Reflux; false = no bar active.
    acidRefluxBarId = false,
}

function ReefGuardian.new()
    return BossBase.fromSchema(ReefGuardian)
end

-- -- Lifecycle -------------------------------------------------------------
function ReefGuardian:onLeave(context)
    CA.castAlertsStop(self.acidRefluxBarId)
end

-- -- Routing tables (C3) --------------------------------------------------
-- (No onDied needed  -  ReefGuardian has no alertList.)

-- Heavy / player-targeted attacks: shared handler for 5 ability IDs.
local function handleHeavy(self, context, alerts, abilityId,
                            unitTag, sourceUnitTag, sourceUnitId, unitId,
                            sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

-- Reef portal opening
local function handleHeartburn(self, context, alerts, abilityId, ...)
    self.reefNum = self.reefNum + 1
    local idx = self.reefNum
    self.reefPortals[idx] = { openTime = GetGameTimeMilliseconds() / 1000,
                              wipeActive = false }
    CA.alert(nil, "Reef " .. idx .. ": OPEN  -  60 s!",
        0xFFD700D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

-- Acid Reflux channel + 5 pool alerts
local function handleAcidReflux(self, context, alerts, abilityId, ...)
    CA.castAlertsStop(self.acidRefluxBarId)
    self.acidRefluxBarId = CA.bar(
        abilityId, "Acid Reflux", 10000, 10000, Colors.POISON, 0.5, ACT_ACID)
    -- Scheduled through BossBase:after so a wipe part-way through the channel
    -- cancels the remaining pool alerts instead of firing them into the reset.
    for i = 1, ACID_COUNT do
        self:after(i * ACID_INTERVAL, function()
            CA.alert(nil,
                "Acid pool " .. i .. "/" .. ACID_COUNT .. "  -  MOVE!",
                0x44DD22D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 1500)
        end)
    end
end

-- Boss replication
local function handleReplication(self, context, alerts, abilityId, ...)
    CA.alert(nil, "Replication!", 0xFF8800D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

ReefGuardian.combatRoutes = {
    [HEARTBURN]           = { result = ACTION_RESULT_BEGIN, fn = handleHeartburn },
    [ACID_REFLUX]         = { result = ACTION_RESULT_BEGIN, fn = handleAcidReflux },
    [REPLICATION]         = { result = ACTION_RESULT_BEGIN, fn = handleReplication },
    -- Heavy / targeted attacks (5 IDs, shared handler)
    [CRAB_MONSTROUS_CLAW] = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRAB_SWIPE]          = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRUSH]               = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CLAW_ATTACK]         = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRACKDOWN]           = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
}

-- Building Static: shared handler for both lightning stack IDs.
local function handleBuildingStatic(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.buildingStaticStacks  = stackCount or 1
            self.buildingStaticEndTime = GetGameTimeMilliseconds() / 1000 + 10
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.buildingStaticStacks  = 0
            self.buildingStaticEndTime = 0
        end
    end
end

-- Volatile Residue: shared handler for both poison stack IDs.
local function handleVolatileResidue(self, context, alerts, changeType, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.volatileResidueStacks  = stackCount or 1
            self.volatileResidueEndTime = GetGameTimeMilliseconds() / 1000 + 10
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.volatileResidueStacks  = 0
            self.volatileResidueEndTime = 0
        end
    end
end

local function handleSheltered(self, context, alerts, changeType, abilityId,
                                unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        self.playerSheltered   = true
        self.lastShelteredTime = GetGameTimeMilliseconds() / 1000
        self.buildingStaticStacks  = 0
        self.volatileResidueStacks = 0
    elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
        self.playerSheltered = false
    end
end

-- Heartburn effect: reef portal wipe timer start.
local function handleHeartburnEffect(self, context, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    for i = self.reefNum, 1, -1 do
        local reef = self.reefPortals[i]
        if reef and not reef.wipeActive and (now - reef.openTime) < 5 then
            reef.wipeActive = true
            reef.wipeStart  = now
            break
        end
    end
end

local function handleKingOrgnumFireDbf(self, context, alerts, changeType, abilityId,
                                        unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        CA.alert(nil, Fmt.c("FF5500", "King Orgnum fire  -  MOVE!"),
            0xFF5500D9, SOUNDS.DUEL_START, 5000)
    end
end

local function handleAcidicVuln(self, context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        self.acidicVulnLast = GetGameTimeMilliseconds() / 1000
    elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
        self.acidicVulnLast = 0
    end
end

ReefGuardian.effectRoutes = {
    [BUILDING_STATIC_1]    = handleBuildingStatic,
    [BUILDING_STATIC_2]    = handleBuildingStatic,
    [VOLATILE_RESIDUE_1]   = handleVolatileResidue,
    [VOLATILE_RESIDUE_2]   = handleVolatileResidue,
    [SHELTERED]            = handleSheltered,
    [HEARTBURN_EFFECT]     = { changeType = EFFECT_RESULT_GAINED, fn = handleHeartburnEffect },
    [KING_ORGNUM_FIRE_DBF] = handleKingOrgnumFireDbf,
    [ACIDIC_VULN]          = handleAcidicVuln,
}

-- -- Info-line renderers ---------------------------------------------------

-- Row 1: Building Static (lightning) stacks; shows CLEANSED during shelter window.
local function showLightningStacksLine(self, alerts, now)
    local stacks = self.buildingStaticStacks
    if stacks > 0 then
        local warn = (stacks >= 7) and (" " .. Fmt.c(Fmt.RED, "!")) or ""
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:setRow(1, Fmt.c(Fmt.GOLD, Lang.t("dsr_reef_elec_cleansed")), nil)
        else
            alerts:setRow(1,
                Fmt.c(Fmt.GOLD,
                    Lang.t("dsr_reef_elec_label")
                    .. Lang.t(stacks ~= 1 and "dsr_reef_stack_p" or "dsr_reef_stack", stacks))
                .. warn, nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Volatile Residue (poison) stacks; shows CLEANSED during shelter window.
local function showPoisonStacksLine(self, alerts, now)
    local vstacks = self.volatileResidueStacks
    if vstacks > 0 then
        local warn = (vstacks >= 7) and (" " .. Fmt.c(Fmt.RED, "!")) or ""
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:setRow(2, Fmt.c(Fmt.POISON, Lang.t("dsr_reef_poison_cleansed")), nil)
        else
            alerts:setRow(2,
                Fmt.c(Fmt.POISON,
                    Lang.t("dsr_reef_poison_label")
                    .. Lang.t(vstacks ~= 1 and "dsr_reef_stack_p" or "dsr_reef_stack", vstacks))
                .. warn, nil)
        end
    else
        alerts:clearRow(2)
    end
end

-- Rows 3+4: Active reef wipe timers (label color red when <= 15 s); row 4 falls back to Acidic Vuln.
local function showReefWipeLines(self, alerts, now)
    local timers = {}
    for i = 1, self.reefNum do
        local reef = self.reefPortals[i]
        if reef and reef.wipeActive then
            local remaining = PORTAL_WIPE_TIME - (now - reef.wipeStart)
            if remaining > 0 then
                table.insert(timers, { idx = i, t = remaining })
            else
                reef.wipeActive = false
            end
        end
    end

    if timers[1] then
        local t1   = timers[1]
        local col1 = (t1.t <= 15) and Fmt.RED or Fmt.GOLD
        alerts:setRow(3, Fmt.c(col1, Lang.t("dsr_reef_reef_timer", t1.idx)), t1.t)
    else
        alerts:clearRow(3)
    end

    if timers[2] then
        local t2   = timers[2]
        local col2 = (t2.t <= 15) and Fmt.RED or Fmt.GOLD
        alerts:setRow(4, Fmt.c(col2, Lang.t("dsr_reef_reef_timer", t2.idx)), t2.t)
    elseif self.acidicVulnLast > 0 then
        local T = 5 - (now - self.acidicVulnLast)
        if T > 0 then
            alerts:setRow(4, Fmt.c(Fmt.ORANGE, Lang.t("dsr_reef_acidic_vuln")), T)
        else
            self.acidicVulnLast = 0
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

function ReefGuardian:onWipe()
    CA.castAlertsStop(self.acidRefluxBarId)
    self.acidRefluxBarId        = nil
    self.buildingStaticStacks   = 0;    self.buildingStaticEndTime  = 0
    self.volatileResidueStacks  = 0;    self.volatileResidueEndTime = 0
    self.playerSheltered        = false; self.lastShelteredTime      = 0
    self.reefPortals            = {};   self.reefNum                = 0
    self.acidicVulnLast         = 0
end

-- -- 200 ms display loop ---------------------------------------------------
function ReefGuardian:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showLightningStacksLine(self, alerts, now)
    showPoisonStacksLine(self, alerts, now)
    showReefWipeLines(self, alerts, now)
end

package.loaded["trial.dsr.boss.ReefGuardian"] = ReefGuardian
return ReefGuardian
