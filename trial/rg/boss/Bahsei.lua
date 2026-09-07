--- Bahsei (Flame-Herald Bahsei)  -  Rockgrove boss 2
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) (done)
--- Phase RG-4: Bahsei-specific mechanics
---
--- onCombatEvent:
---   CursedGround    (152475): BEGIN -> Alert; 28 s cycle
---   Salvo2/Interrupt(152463): BEGIN, tank-only -> AlertCast + "Interrupt!" Alert
---   Sickle          (150067): BEGIN -> nextSickle +15 s; if targeted -> AlertCast
---   Hemorrhage      (150008): targeted player -> "Bleeding" Alert 9 s
---   RancidHammer    (149922): BEGIN, tank-only -> AlertCast
---   MT detection: carve/slice/rendflesh (150047/150048/150065) target -> mtUnitId
---   MeteorSwarm     (155357): EFFECT_GAINED_DURATION -> CastAlertsStart 13.5 s (HM)
---   EyeCW/CCW       (153517/153518): EFFECT_GAINED -> track portal direction (HM)
---
--- onEffectChanged:
---   DeathTouch (150078): GAINED on self -> AlertBorder blue 9 s;
---                        GAINED on mtUnitId -> nextMtExplosion +9 s
---   MalignantMarrow (153421): GAINED -> nextPortal +50 s, flip portalNumber;
---                             self GAINED -> selfDoNotPortalTime +120 s;
---                             self FADED  -> clear selfDoNotPortalTime
---   BitterMarrow (153423): GAINED -> numPlayersInPortal++; FADED -> --
---
--- Note: Scalding (153175) on Fire Behemoth add is handled by RockgroveCommon.
---
--- HM detection: context.isHM (pre-computed by TrialContext from hmHealthThreshold)
---   (set by BossRegistry:detectDifficulty via hmHealthThreshold=100000001)
---   TODO: verify exact HM health pool in-game.

local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")


-- -- Ability IDs ------------------------------------------------------------
local CURSED_GROUND    = 152475   -- combatRoute: ACTION_RESULT_BEGIN -> Cursed Ground alert
local SALVO2           = 152463   -- combatRoute: ACTION_RESULT_BEGIN -> interrupt prompt (tanks)
local SICKLE           = 150067   -- combatRoute: ACTION_RESULT_BEGIN -> nextSickle +15s; player alert
local HEMORRHAGE       = 150008   -- combatRoute: ACTION_RESULT_BEGIN -> Bleeding alert (player)
local RANCID_HAMMER    = 149922   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (tanks)
-- 150047/150048/150065 (MT_ATTACK_IDS) -- reference: carve/slice/rendflesh MT detection set (unrouted)
local DEATH_TOUCH      = 150078   -- effectRoute: EFFECT_RESULT_GAINED -> blue border + MT explosion
local MALIGNANT_MARROW = 153421   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> nextPortal +50s
local BITTER_MARROW    = 153423   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> numPlayersInPortal
local METEOR_SWARM     = 155357   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> 13.5s bar (HM)
local EYE_CW           = 153517   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> CW portal direction
local EYE_CCW          = 153518   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> CCW portal direction

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")

-- -- CA colour palettes -----------------------------------------------------
local ACT_METEOR    = { 10000, "KILL SUN!", 0.8, 0.0, 0.0, 0.9, nil }

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_SALVO_DUR  = 2500   -- Salvo2 (interrupt): empirical
local FALLBACK_SICKLE_DUR = 1500   -- Sickle: empirical
local FALLBACK_HAMMER_DUR = 2000   -- RancidHammer: empirical

-- -- Boss definition -------------------------------------------------------
local Bahsei = {}
Bahsei.__index = Bahsei

Bahsei.key               = "bahsei"
Bahsei.name              = Lang.t("boss_bahsei")      -- TODO: verify; may be "Flame-Herald Bahsei"
-- location: arena AABB not yet captured  -  detection is name-based.
-- To add AABB: stand in arena, run /script d(GetUnitWorldPosition("boss1"))
Bahsei.hmHealthThreshold = 100000001     -- TODO: verify exact HM health pool in-game

Bahsei.stateSchema = {
    lastCursedGround    = 0,
    nextPortal          = 0,
    portalNumber        = 1,
    selfDoNotPortalTime = 0,
    numPlayersInPortal  = 0,
    portalTracker       = function() return {} end,
    lastDeathTouch      = 0,
    nextMtExplosion     = 0,
    nextSickle          = 0,
    lastPortalCW        = true,
    -- unitId of the last player hit by a carve/slice/rendflesh (MT detection).
    mtUnitId            = false,
    -- CA bar handle for the HM Prime Meteor (Meteor Swarm) cast (false when not active).
    sunBarId            = false,
}

function Bahsei.new()
    return BossBase.fromSchema(Bahsei)
end

-- -- Lifecycle -------------------------------------------------------------
function Bahsei:onLeave(context)
    CA.castAlertsStop(self.sunBarId)
    self.sunBarId = false
end

-- Soft reset on wipe: cancel the Prime Meteor bar if it's running and clear
-- per-pull counters so the next attempt starts clean.
function Bahsei:onWipe(context, alerts)
    CA.castAlertsStop(self.sunBarId)
    self.sunBarId           = false
    self.lastCursedGround   = 0
    self.nextPortal         = 0
    self.portalNumber       = 1
    self.selfDoNotPortalTime = 0
    self.numPlayersInPortal = 0
    self.portalTracker      = {}
    self.lastDeathTouch     = 0
    self.nextMtExplosion    = 0
    self.nextSickle         = 0
    self.mtUnitId           = false
    self.lastPortalCW       = true
end

-- -- Combat state ----------------------------------------------------------
function Bahsei:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- First portal opens ~20 s into the fight.
        -- HM only  -  nextPortal is displayed only when context.difficulty == HARDMODE.
        self.nextPortal = GetGameTimeMilliseconds() / 1000 + 20
    end
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared trash mechanic handler.
Bahsei.common = RockgroveCommon

-- DIED: clean up portal tracker for the dead player.
function Bahsei:onDied(context, alerts,
                        unitTag, sourceUnitTag, sourceUnitId, unitId,
                        sourceUnitName, unitName)
    if unitId and self.portalTracker[unitId] then
        self.portalTracker[unitId] = false
        if self.numPlayersInPortal > 0 then
            self.numPlayersInPortal = self.numPlayersInPortal - 1
        end
    end
end

-- MT_ATTACK_IDS (carve/slice/rendflesh): player hit -> update mtUnitId.
local function handleMtDetect(self, context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if IsUnitPlayer(unitTag) then self.mtUnitId = unitId end
end

local function handleCursedGround(self, context, alerts, abilityId, ...)
    self.lastCursedGround = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "Cursed Ground", 0xEE82EED9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
end

local function handleSalvo(self, context, alerts, abilityId,
                            unitTag, sourceUnitTag, sourceUnitId, unitId,
                            sourceUnitName, unitName)
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        local dur = CastDur.get(SALVO2, FALLBACK_SALVO_DUR)
        CA.interrupt_melee(abilityId, sourceUnitName, dur, Colors.ICE)
        CA.alert(nil, "Interrupt!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
    end
end

local function handleSickle(self, context, alerts, abilityId,
                             unitTag, sourceUnitTag, sourceUnitId, unitId,
                             sourceUnitName, unitName)
    self.nextSickle = GetGameTimeMilliseconds() / 1000 + 15
    if IsUnitPlayer(unitTag) then
        local dur = CastDur.get(SICKLE, FALLBACK_SICKLE_DUR)
        CA.melee(abilityId, sourceUnitName, dur, Colors.VOID)
    end
end

local function handleHemorrhage(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    PlaySound(SOUNDS.DUEL_START)
    CA.alert(nil, "Bleeding", 0xCC0000D9, SOUNDS.DUEL_START, 9000)
end

local function handleRancidHammer(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        local dur = CastDur.get(RANCID_HAMMER, FALLBACK_HAMMER_DUR)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
    end
end

-- Prime Meteor (HM, < ~31% HP): starts a 13.5 s cast bar.
local function handleMeteorSwarm(self, context, alerts, abilityId, ...)
    if not context.isHM then return end
    self.nextSickle = 0   -- sickle irrelevant from here; free the slot
    CA.castAlertsStop(self.sunBarId)
    self.sunBarId = CA.bar(
        abilityId, "Prime Meteor",
        13500, 13500, Colors.FLYZONE, 0.4, ACT_METEOR)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleEyeCw(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then self.lastPortalCW = true end
end

local function handleEyeCcw(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then self.lastPortalCW = false end
end

Bahsei.combatRoutes = {
    [150047]        = handleMtDetect,   -- carve
    [150048]        = handleMtDetect,   -- slice
    [150065]        = handleMtDetect,   -- rendflesh
    [CURSED_GROUND] = { result = ACTION_RESULT_BEGIN,                  fn = handleCursedGround },
    [SALVO2]        = { result = ACTION_RESULT_BEGIN,                  fn = handleSalvo },
    [SICKLE]        = { result = ACTION_RESULT_BEGIN,                  fn = handleSickle },
    [HEMORRHAGE]    = { result = ACTION_RESULT_BEGIN,                  fn = handleHemorrhage },
    [RANCID_HAMMER] = { result = ACTION_RESULT_BEGIN,                  fn = handleRancidHammer },
    [METEOR_SWARM]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleMeteorSwarm },
    [EYE_CW]        = handleEyeCw,
    [EYE_CCW]       = handleEyeCcw,
}

local function handleDeathTouch(self, context, alerts, abilityId,
                                 unitTag, unitId, unitName, stackCount)
    -- Personal border: player received the curse
    if AreUnitsEqual("player", unitTag) then
        self.lastDeathTouch = GetGameTimeMilliseconds() / 1000
        CA.border(true, 9000, "blue")
    end
    -- MT explosion: track whose curse will detonate first
    if unitId and unitId == self.mtUnitId then
        self.nextMtExplosion = GetGameTimeMilliseconds() / 1000 + 9
    end
end

local function handleMalignantMarrow(self, context, alerts, changeType, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        -- Event fires up to 3 times  -  accept only once per 5 s window.
        local now = GetGameTimeMilliseconds() / 1000
        local newPortalTime = now + 50
        if newPortalTime > self.nextPortal + 5 then
            self.nextPortal         = newPortalTime
            self.portalNumber       = 3 - self.portalNumber   -- 1<->2
            self.numPlayersInPortal = 0
            self.portalTracker      = {}
        end
        if AreUnitsEqual("player", unitTag) then
            self.selfDoNotPortalTime = now + 120
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.selfDoNotPortalTime = 0
        end
    end
end

local function handleBitterMarrow(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        self.numPlayersInPortal = self.numPlayersInPortal + 1
        if unitId then self.portalTracker[unitId] = true end
    elseif changeType == EFFECT_RESULT_FADED then
        if self.numPlayersInPortal > 0 then
            self.numPlayersInPortal = self.numPlayersInPortal - 1
        end
        if unitId then self.portalTracker[unitId] = false end
    end
end

Bahsei.effectRoutes = {
    [DEATH_TOUCH]      = { changeType = EFFECT_RESULT_GAINED, fn = handleDeathTouch },
    [MALIGNANT_MARROW] = handleMalignantMarrow,
    [BITTER_MARROW]    = handleBitterMarrow,
}

-- -- Tracker-row renderers --------------------------------------------------

-- Row 1: Next Cursed Ground (28 s cycle).
local function showCursedGroundLine(self, alerts, now)
    if self.lastCursedGround > 0 then
        local T = 28 - (now - self.lastCursedGround)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.ARCANE, Lang.t("rg_bahsei_next_curse")), T)
        else
            alerts:setRow(1, Fmt.c(Fmt.ARCANE, Lang.t("rg_bahsei_next_curse")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2 (HM): Next Portal countdown, or direction + in-progress count.
local function showPortalLine(self, alerts, now, isHM)
    if isHM then
        local delta = self.nextPortal - now
        if delta > 0 then
            alerts:setRow(2,
                Fmt.c(Fmt.SKY, "Portal") .. " " ..
                Fmt.c(Fmt.SMOKE, "(" .. self.portalNumber .. ")"),
                delta)
        else
            local dir = self.lastPortalCW
                and Fmt.c("00cc00", Lang.t("rg_bahsei_portal_cw"))
                or  Fmt.c("ff8040", Lang.t("rg_bahsei_portal_ccw"))
            local cnt = self.numPlayersInPortal
            alerts:setRow(2,
                Fmt.c(Fmt.SKY, "Portal") .. " " .. dir ..
                " " .. Fmt.c(Fmt.SMOKE, Lang.t("rg_bahsei_portal_progress")) ..
                (cnt > 0 and (" " .. Fmt.c(Fmt.GRAY, "(" .. cnt .. ")")) or ""),
                nil)
        end
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Tank Exploding (<= 3 s) > Death Touch personal > No Portal cooldown.
-- Kept on row 3 (not showAction) so reactive event alerts keep their slot.
local function showDeathTouchLine(self, alerts, now, isHM)
    local explodeDelta = (self.nextMtExplosion > 0) and (self.nextMtExplosion - now) or -1
    local dtDelta      = (self.lastDeathTouch  > 0) and (9 - (now - self.lastDeathTouch)) or -1
    if explodeDelta >= 0 and explodeDelta <= 3 then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_bahsei_tank_exploding")), explodeDelta)
    elseif dtDelta > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FROST, Lang.t("rg_bahsei_death_touch")), dtDelta)
    elseif isHM and self.selfDoNotPortalTime > 0 then
        local noPortalDelta = self.selfDoNotPortalTime - now
        if noPortalDelta > 0 then
            alerts:setRow(3, Fmt.c(Fmt.FIRE, Lang.t("rg_bahsei_no_portal")), noPortalDelta)
        else
            alerts:clearRow(3)
        end
    else
        alerts:clearRow(3)
    end
end

-- Row 4 (HM): Next Sickle  -  displayed only within the 15 s window before the cast.
local function showSickleLine(self, alerts, now, isHM)
    if isHM and self.nextSickle > 0 then
        local T = self.nextSickle - now
        if T > 0 and T <= 15 then
            alerts:setRow(4, Fmt.c(Fmt.PURPLE, Lang.t("rg_bahsei_next_sickle")), T)
        elseif T <= 0 then
            alerts:setRow(4, Fmt.c(Fmt.PURPLE, Lang.t("rg_bahsei_next_sickle")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        else
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Bahsei:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showCursedGroundLine(self, alerts, now)
    showPortalLine(self, alerts, now, isHM)
    showDeathTouchLine(self, alerts, now, isHM)
    showSickleLine(self, alerts, now, isHM)
end

package.loaded["trial.rg.boss.Bahsei"] = Bahsei
return Bahsei
