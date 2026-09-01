local Timer    = require("lib.Timer")

local CA               = require("lib.CA")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")

-- ── Ability IDs (from OsseinCageHelper) ──────────────────────────────────
-- Chains
local CHAINS_1        = 232773   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → chain pair detection + alert
local CHAINS_2        = 232775   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → chain pair detection + alert
local TORTUOUS_CHAINS = 236338   -- combatRoute: ACTION_RESULT_EFFECT_GAINED → red border (player)
-- Vile Leap
local VILE_LEAP       = 235557   -- combatRoute: ACTION_RESULT_BEGIN → Vile Leap caAlertCast
local SEETHING_LEAP   = 245208   -- combatRoute: ACTION_RESULT_BEGIN → Seething Vile Leap caAlertCast (enrage)
-- Agonizer Bombs
local AGONIZER_BOMBS  = 237149   -- combatRoute: ACTION_RESULT_BEGIN → Agonizer Bombs alert (debounced 5s)
-- Biting Blaze (6-target fire)
local BITING_BLAZE_1  = 235354   -- combatRoute: ACTION_RESULT_BEGIN → Biting Blaze targeted alert
local BITING_BLAZE_2  = 246009   -- combatRoute: ACTION_RESULT_BEGIN → Biting Blaze targeted alert
-- Giant Sword / cones
local GIANT_PULSE_1   = 235495   -- combatRoute: ACTION_RESULT_BEGIN → Giant Sword caAlertCast
local GIANT_PULSE_2   = 244937   -- combatRoute: ACTION_RESULT_BEGIN → Giant Sword caAlertCast
local GIANT_CONES     = 232574   -- combatRoute: ACTION_RESULT_BEGIN → Dodge cones! alert
local SHOCK_SPEAR     = 235514   -- combatRoute: ACTION_RESULT_BEGIN → Dodge spear! alert
-- Molag Kena adds
local STORM_SLAM      = 235201   -- combatRoute: ACTION_RESULT_BEGIN → DODGE caAlertCast + alert
local STORM_SURGE     = 235205   -- combatRoute: ACTION_RESULT_BEGIN → Storm Surge caAlertCast
local HEAVY_SHOCK     = 235206   -- combatRoute: ACTION_RESULT_BEGIN → Heavy Shock alert (player)
-- Portal / teleport
local VILE_TELEPORT   = 232969   -- combatRoute: ACTION_RESULT_BEGIN → portal phase++ alert
-- Channelers (each EFFECT_FADED = one channeler killed)
local CHANNELER_RITUAL = 234349  -- combatRoute: ACTION_RESULT_EFFECT_FADED → channeler killed counter
-- Debuffs on player
local STRICKEN        = 235594   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → Stricken alert (player)
local FIREBOMB_DEBUF  = 245264   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → Firebomb alert (player)
local IMMOLATING_SPHERE= 237011   -- combatRoute: ACTION_RESULT_BEGIN → Immolating Sphere alert (player)

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_LEAP     = { -3, 0, false, { 0.6, 0,   0.9, 0.4 }, { 0.6, 0,   0.9, 0.8 } }
local COL_LEAP_RED = { -3, 0, false, { 1,   0.1, 0.1, 0.4 }, { 1,   0.1, 0.1, 0.8 } }
local COL_SLAM     = { -3, 0, false, { 1,   0.7, 0,   0.4 }, { 1,   0.7, 0,   0.8 } }
local COL_SURGE    = { -3, 0, false, { 0.9, 0.9, 0.1, 0.4 }, { 0.9, 0.9, 0.1, 0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- GiantPulse / VileLeap / SeethingLeap / StormSlam / StormSurge: empirical

local KazpianEncounter = {}
KazpianEncounter.__index = KazpianEncounter

KazpianEncounter.key               = "kazpian"
KazpianEncounter.nameAliases       = { "Overfiend Kazpian" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
KazpianEncounter.hmHealthThreshold = math.huge
-- location: placeholder — Oathsworn Pit arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

KazpianEncounter.stateSchema = {
    bombDebounce   = function() return Timer.new(5.0) end,
    portalPhase    = 0,
    channelersDead = 0,
    -- Chain targets: populated on first/second DOMINATORS_CHAINS event,
    -- cleared after the alert fires. nil = no chain holder tracked yet.
    chainedA       = nil,
    chainedB       = nil,
}

function KazpianEncounter.new()
    return BossBase.fromSchema(KazpianEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

-- Chains: pairs two chained players and alerts when the pair is formed.
local function handleChains(self, context, alerts, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    local name = IsUnitPlayer(unitTag) and "YOU" or (unitName or "?")
    if not self.chainedA then
        self.chainedA = name
    elseif not self.chainedB then
        self.chainedB = name
        alerts:showAction("Chains: " .. self.chainedA .. " → " .. self.chainedB)
        if self.chainedA == "YOU" or self.chainedB == "YOU" then
            CA.alert(nil, "CHAINED — pull apart!", 0xFF4444FF, SOUNDS.NONE, 4000)
        end
        self.chainedA = nil
        self.chainedB = nil
    end
end

-- Biting Blaze: shared handler for both variants.
local function handleBitingBlaze(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Biting Blaze → " .. target)
end

-- Giant Pulse: shared handler for both variants.
local function handleGiantPulse(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Giant Sword!", dur, COL_SLAM)
end

local function handleVileLeap(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Vile Leap!", dur, COL_LEAP)
    alerts:showAction("Vile Leap!")
end

local function handleSeethingLeap(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "VILE LEAP (enrage)!", dur, COL_LEAP_RED)
    alerts:showAction("Seething Vile Leap!")
end

local function handleAgonizerBombs(self, context, alerts, abilityId, ...)
    if self.bombDebounce:isExpired() then
        self.bombDebounce:reset(5.0)
        CA.alert(nil, "Agonizer Bombs!", 0xFF8844FF, SOUNDS.NONE, 3000)
        alerts:showAction("Agonizer Bombs!")
    end
end

local function handleGiantCones(self, context, alerts, abilityId, ...)
    CA.alert(nil, "Dodge cones!", 0xFFFF44FF, SOUNDS.NONE, 2500)
end

local function handleShockSpear(self, context, alerts, abilityId, ...)
    CA.alert(nil, "Dodge spear!", 0x44CCFFFF, SOUNDS.NONE, 2500)
end

local function handleStormSlam(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "DODGE — Storm Slam!", dur, COL_SLAM)
    alerts:showAction("Molag Kena Storm Slam — DODGE!")
end

local function handleStormSurge(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Storm Surge!", dur, COL_SURGE)
end

local function handleHeavyShock(self, context, alerts, abilityId,
                                 unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Heavy Shock on YOU!", 0x44CCFFFF, SOUNDS.NONE, 2500)
    alerts:showAction("Molag Kena Heavy Shock on you!")
end

local function handleImmolating(self, context, alerts, abilityId,
                                 unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Immolating Sphere!", 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction("Immolating Sphere on you!")
end

local function handleVileTeleport(self, context, alerts, abilityId, ...)
    self.portalPhase = self.portalPhase + 1
    alerts:showAction("Portal phase " .. self.portalPhase .. "!")
end

local function handleStricken(self, context, alerts, abilityId,
                               unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Stricken on YOU!", 0xFF4444FF, SOUNDS.NONE, 4000)
    alerts:showAction("Stricken — tank mechanic!")
end

local function handleFirebombDebuf(self, context, alerts, abilityId,
                                    unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Firebomb on YOU!", 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction("Firebomb — spread!")
end

local function handleTortuousChains(self, context, alerts, abilityId,
                                     unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 5000, "red")
    alerts:showAction("Tortuous Chains — run from Kazpian!")
end

local function handleChannelerRitual(self, context, alerts, abilityId, ...)
    self.channelersDead = self.channelersDead + 1
    alerts:showAction("Channeler down! (" .. self.channelersDead .. " dead)")
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Shared trash-mechanic handler.
KazpianEncounter.common = OsseinCageCommon

KazpianEncounter.combatRoutes = {
    -- Leaps
    [VILE_LEAP]     = { result = ACTION_RESULT_BEGIN,                  fn = handleVileLeap },
    [SEETHING_LEAP] = { result = ACTION_RESULT_BEGIN,                  fn = handleSeethingLeap },
    -- Agonizer Bombs (debounced)
    [AGONIZER_BOMBS]   = { result = ACTION_RESULT_BEGIN,               fn = handleAgonizerBombs },
    [BITING_BLAZE_1]   = { result = ACTION_RESULT_BEGIN,               fn = handleBitingBlaze },
    [BITING_BLAZE_2]   = { result = ACTION_RESULT_BEGIN,               fn = handleBitingBlaze },
    [GIANT_CONES]      = { result = ACTION_RESULT_BEGIN,               fn = handleGiantCones },
    [GIANT_PULSE_1]    = { result = ACTION_RESULT_BEGIN,               fn = handleGiantPulse },
    [GIANT_PULSE_2]    = { result = ACTION_RESULT_BEGIN,               fn = handleGiantPulse },
    [SHOCK_SPEAR]      = { result = ACTION_RESULT_BEGIN,               fn = handleShockSpear },
    [STORM_SLAM]       = { result = ACTION_RESULT_BEGIN,               fn = handleStormSlam },
    [STORM_SURGE]      = { result = ACTION_RESULT_BEGIN,               fn = handleStormSurge },
    [HEAVY_SHOCK]      = { result = ACTION_RESULT_BEGIN,               fn = handleHeavyShock },
    [IMMOLATING_SPHERE] = { result = ACTION_RESULT_BEGIN,               fn = handleImmolating },
    [VILE_TELEPORT]    = { result = ACTION_RESULT_BEGIN,               fn = handleVileTeleport },
    -- Chains (EFFECT_GAINED_DURATION)
    [CHAINS_1]         = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleChains },
    [CHAINS_2]         = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleChains },
    [STRICKEN]         = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleStricken },
    [FIREBOMB_DEBUF]   = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFirebombDebuf },
    -- Tortuous Chains (EFFECT_GAINED)
    [TORTUOUS_CHAINS]  = { result = ACTION_RESULT_EFFECT_GAINED,       fn = handleTortuousChains },
    -- Channeler ritual (EFFECT_FADED = channeler killed)
    [CHANNELER_RITUAL] = { result = ACTION_RESULT_EFFECT_FADED,        fn = handleChannelerRitual },
}

function KazpianEncounter:onWipe()
    OsseinCageCommon.reset()
    self.bombDebounce:clear()
    self.portalPhase    = 0; self.channelersDead = 0
    self.chainedA       = nil; self.chainedB = nil
end

function KazpianEncounter:onUpdate(context, alerts)
    -- Line 1: portal phase
    if self.portalPhase > 0 then
        alerts:showInfo(1, "Portal: phase " .. self.portalPhase)
    else
        alerts:showInfo(1, "")
    end

    -- Line 2: channelers dead
    if self.channelersDead > 0 then
        alerts:showInfo(2, "Channelers dead: " .. self.channelersDead)
    else
        alerts:showInfo(2, "")
    end

    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

package.loaded["trial.oc.boss.KazpianEncounter"] = KazpianEncounter
return KazpianEncounter
