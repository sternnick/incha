--- Oaxiltso  -  Rockgrove boss 1
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) (done)
--- Phase RG-3: Oaxiltso-specific mechanics
---   SavageBlitz  (149414 / 157932 HM): BEGIN -> CastAlertsStart 2750 ms; 36 s cycle
---   NoxiousSludge (149190):  BEGIN -> Alert; 28 s cycle
---   PoisonedPlayers (157860): EFFECT_GAINED -> track 2 players, assign side via
---                             distance to exit-left pool; alert "<< L || R >>"
---   AnnihilatorSunburst (153181): BEGIN -> zo_callLater 2500 ms -> "Meteor. BLOCK!"
---   CinderCleave (152688): targeted player -> AlertCast 2000 ms (hardcoded; QRH note)
---   EmberChains  (152699): targeted player -> AlertCast 750 ms, projectile-adjusted
---   AddSpawn     (152365): EFFECT_GAINED -> showAction "ADD SPAWNING!"
---   BossEnrage   (152502) / MiniEnrage (152503): EFFECT_GAINED/FADED flags

local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")


-- -- Ability IDs ------------------------------------------------------------
local SAVAGE_BLITZ    = 149414   -- combatRoute: ACTION_RESULT_BEGIN -> Savage Blitz caAlertCast
local SAVAGE_BLITZ_HM = 157932   -- combatRoute: ACTION_RESULT_BEGIN -> Savage Blitz HM (< 50% HP)
local NOXIOUS_SLUDGE  = 149190   -- combatRoute: ACTION_RESULT_BEGIN -> Noxious Sludge alert
local SLUDGE_DEBUFF   = 157860   -- effectRoute: EFFECT_RESULT_GAINED -> left/right side assignment
local SUNBURST        = 153181   -- combatRoute: ACTION_RESULT_BEGIN -> meteor Block alert 2.5s later
local CINDER_CLEAVE   = 152688   -- combatRoute: ACTION_RESULT_BEGIN -> Dodge alert (player-targeted)
local EMBER_CHAINS    = 152699   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (player-targeted)
local ADD_SPAWN       = 152365   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> ADD SPAWNING alert
local BOSS_ENRAGE     = 152502   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> bossEnraged flag
local MINI_ENRAGE     = 152503   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> miniEnraged flag

-- -- Pool reference position (world coords) --------------------------------
-- Exit-left pool  -  used to assign left/right side to poisoned players.
-- Closer to this point -> left cleanse; farther -> right cleanse.
local POOL_EX_LEFT = { 91973, 35751, 81764 }

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local Colors = require("core.Colors")

-- -- CA colour palettes -----------------------------------------------------

-- -- Distance helper (squared, world coords  -  no sqrt needed for comparison) -
local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx*dx + dy*dy + dz*dz
end

-- -- Boss definition -------------------------------------------------------
local Oaxiltso = {}
Oaxiltso.__index = Oaxiltso

Oaxiltso.key  = "oaxiltso"
Oaxiltso.name = Lang.t("boss_oaxiltso")   -- TODO: verify exact unit name via GetUnitName("boss1") in-game
-- location: arena AABB not yet captured  -  detection is name-based.
-- To add AABB: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

Oaxiltso.stateSchema = {
    lastBlitz          = 0,
    lastSludge         = 0,
    lastPoisonTracker  = 0,
    sludgeTracker1     = 0,
    sludgeTracker1Tag  = false, -- unitTag of the first sludge target (false = none)
    sludgeTracker1Name = false, -- display name cache for sludge alert text
    bossEnraged        = false,
    miniEnraged        = false,
    -- zo_callLater handle for the 2.5 s Sunburst delayed meteor alert.
    -- Stored so onWipe can cancel it if the group wipes in that window.
    sunburstTimer      = false,
}

function Oaxiltso.new()
    return BossBase.fromSchema(Oaxiltso)
end

-- -- Lifecycle -------------------------------------------------------------
function Oaxiltso:onLeave(context)
    self:cancelAfter(self.sunburstTimer)
    self.sunburstTimer = false
end

-- Soft reset on wipe: cancel the pending Sunburst alert and clear
-- per-pull counters so the next attempt starts clean.
function Oaxiltso:onWipe(context, alerts)
    self:cancelAfter(self.sunburstTimer)
    self.sunburstTimer = false
    self.lastBlitz         = 0
    self.lastSludge        = 0
    self.lastPoisonTracker = 0
    self.sludgeTracker1    = 0
    self.sludgeTracker1Tag  = false
    self.sludgeTracker1Name = false
    self.bossEnraged       = false
    self.miniEnraged       = false
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared trash mechanic handler (interrupt, execute, HA, etc.).
Oaxiltso.common = RockgroveCommon

local function handleSavageBlitz(self, context, alerts, abilityId, ...)
    self.lastBlitz = GetGameTimeMilliseconds() / 1000
    CA.bar(abilityId, "Savage Blitz", 2750, 2750, Colors.RED, 0.4)
end

local function handleNoxiousSludge(self, context, alerts, abilityId, ...)
    self.lastSludge = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "Noxious Sludge", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

-- Sunburst casts, then ~2.5 s later a meteor hits; alert fires at impact.
-- Store the handle so onWipe can cancel it if the group wipes in the window.
local function handleSunburst(self, context, alerts, abilityId, ...)
    self:cancelAfter(self.sunburstTimer)
    self.sunburstTimer = self:after(2500, function()
        self.sunburstTimer = false
        if not IsUnitInCombat("player") then return end
        CA.alert(nil, "Meteor. BLOCK!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
    end)
end

-- QRH: hitValue returns ~4 s but actual dodge window is ~2 s; hardcode 2000.
local function handleCinderCleave(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("rg_oaxiltso_dodge_cone"))
    CA.melee(abilityId, sourceUnitName, 2000, Colors.ORANGE)
end

local function handleEmberChains(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    CA.ranged(abilityId, sourceUnitName, 750, Colors.PURPLE)
end

local function handleAddSpawn(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("rg_oaxiltso_add_spawning"))
end

Oaxiltso.combatRoutes = {
    [SAVAGE_BLITZ]    = { result = ACTION_RESULT_BEGIN,         fn = handleSavageBlitz },
    [SAVAGE_BLITZ_HM] = { result = ACTION_RESULT_BEGIN,         fn = handleSavageBlitz },
    [NOXIOUS_SLUDGE]  = { result = ACTION_RESULT_BEGIN,         fn = handleNoxiousSludge },
    [SUNBURST]        = { result = ACTION_RESULT_BEGIN,         fn = handleSunburst },
    [CINDER_CLEAVE]   = { result = ACTION_RESULT_BEGIN,         fn = handleCinderCleave },
    [EMBER_CHAINS]    = { result = ACTION_RESULT_BEGIN,         fn = handleEmberChains },
    [ADD_SPAWN]       = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleAddSpawn },
}

-- Track first poisoned player; alert with left/right side assignment when pair is complete.
-- The EFFECT_RESULT_GAINED event fires up to 3x per cast when the local player is hit,
-- so a 10 s dedup gate collapses those duplicates into a single slot-1 registration.
local function handleSludgeDebuff(self, context, alerts, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    local now = GetGameTimeMilliseconds() / 1000

    if self.sludgeTracker1 == 0 then
        if now - self.lastPoisonTracker > 10 then
            self.lastPoisonTracker  = now
            self.sludgeTracker1     = unitId
            self.sludgeTracker1Tag  = unitTag
            self.sludgeTracker1Name = GetUnitDisplayName(unitTag) or unitName or "?"
        end

    elseif unitId ~= self.sludgeTracker1 then
        local name1 = self.sludgeTracker1Name
        local name2 = GetUnitDisplayName(unitTag) or unitName or "?"

        local _, x1, y1, z1 = GetUnitWorldPosition(self.sludgeTracker1Tag)
        local _, x2, y2, z2 = GetUnitWorldPosition(unitTag)

        -- Whichever player is closer to the exit-left pool goes left.
        local d1 = (x1 ~= nil) and distSq(x1, y1, z1,
            POOL_EX_LEFT[1], POOL_EX_LEFT[2], POOL_EX_LEFT[3]) or math.huge
        local d2 = (x2 ~= nil) and distSq(x2, y2, z2,
            POOL_EX_LEFT[1], POOL_EX_LEFT[2], POOL_EX_LEFT[3]) or math.huge

        local leftName, rightName
        if d1 <= d2 then
            leftName, rightName = name1, name2
        else
            leftName, rightName = name2, name1
        end

        CA.alert(nil,
            "<< " .. leftName .. " << || >> " .. rightName .. " >>",
            0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 5000)

        self.sludgeTracker1     = 0
        self.sludgeTracker1Tag  = nil
        self.sludgeTracker1Name = nil
    end
end

local function handleBossEnrage(self, context, alerts, changeType, abilityId, ...)
    self.bossEnraged = (changeType == EFFECT_RESULT_GAINED)
end

local function handleMiniEnrage(self, context, alerts, changeType, abilityId, ...)
    self.miniEnraged = (changeType == EFFECT_RESULT_GAINED)
end

Oaxiltso.effectRoutes = {
    [SLUDGE_DEBUFF] = { changeType = EFFECT_RESULT_GAINED, fn = handleSludgeDebuff },
    [BOSS_ENRAGE]   = handleBossEnrage,
    [MINI_ENRAGE]   = handleMiniEnrage,
}

-- -- Tracker-row renderers --------------------------------------------------

-- Row 1: Next Savage Blitz (36 s cycle).
local function showBlitzLine(self, alerts, now)
    if self.lastBlitz > 0 then
        local T = 36 - (now - self.lastBlitz)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.FIRE, Lang.t("rg_oaxiltso_next_blitz")), T)
        else
            alerts:setRow(1, Fmt.c(Fmt.FIRE, Lang.t("rg_oaxiltso_next_blitz")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Next Noxious Sludge (28 s cycle).
local function showSludgeLine(self, alerts, now)
    if self.lastSludge > 0 then
        local T = 28 - (now - self.lastSludge)
        if T > 0 then
            alerts:setRow(2, Fmt.c(Fmt.POISON, Lang.t("rg_oaxiltso_next_sludge")), T)
        else
            alerts:setRow(2, Fmt.c(Fmt.POISON, Lang.t("rg_oaxiltso_next_sludge")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Enrage state  -  boss enraged, add enraged, or both.
local function showEnrageLine(self, alerts)
    if self.bossEnraged and self.miniEnraged then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_oaxiltso_boss_add_enrage")), nil)
    elseif self.bossEnraged then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_oaxiltso_boss_enraged")), nil)
    elseif self.miniEnraged then
        alerts:setRow(3, Fmt.c(Fmt.ORANGE, Lang.t("rg_oaxiltso_add_enraged")), nil)
    else
        alerts:clearRow(3)
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Oaxiltso:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showBlitzLine(self, alerts, now)
    showSludgeLine(self, alerts, now)
    showEnrageLine(self, alerts)
    alerts:clearRow(4)
end

package.loaded["trial.rg.boss.Oaxiltso"] = Oaxiltso
return Oaxiltso
