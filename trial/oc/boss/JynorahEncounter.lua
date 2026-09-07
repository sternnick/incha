local Timer    = require("lib.Timer")

local CA               = require("external-api.CombatAlerts")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")
local Lang             = require("core.Lang")
local Fmt              = require("core.Fmt")
local Colors = require("core.Colors")

-- -- Ability IDs (from OsseinCageHelper) ----------------------------------------------------------
-- Dragons (Valneer = fire/orange, Myrinax = lightning/blue)
local TITANIC_CLASH   = 232375   -- combatRoute: ACTION_RESULT_BEGIN -> CLASH phase caAlertCast
local TITANIC_LEAP_1  = 233477   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
local TITANIC_LEAP_2  = 234704   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
local TITANIC_LEAP_3  = 233452   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
local TITANIC_LEAP_4  = 233489   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
local TITANIC_LEAP_5  = 234722   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
local TITANIC_LEAP_6  = 233466   -- combatRoute: ACTION_RESULT_BEGIN -> Leap alert, reset leapTimer
-- Clash hits (which dragon was hit during Titanic Clash phase)
local TITANIC_CLASH_HIT_V = 232460  -- combatRoute: ACTION_RESULT_BEGIN -> Valneer hit
local TITANIC_CLASH_HIT_M = 232465  -- combatRoute: ACTION_RESULT_BEGIN -> Myrinax hit
-- Curse casts
local SPARKING_CURSE_CAST  = 234000   -- combatRoute: ACTION_RESULT_BEGIN -> curse cast announcement (targeted)
local BLAZING_CURSE_CAST   = 234276   -- combatRoute: ACTION_RESULT_BEGIN -> curse cast announcement (targeted)
-- Curse debuffs
local SPARKING_CURSE_DEBUF = 234008   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> blue border + alert (player)
local BLAZING_CURSE_DEBUF  = 234280   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> red border + alert (player)
-- AoE on player
local COLDFLAME_SURGE  = 234321   -- combatRoute: ACTION_RESULT_BEGIN -> Coldflame on YOU! (player)
local BRIMSTONE_SURGE  = 234330   -- combatRoute: ACTION_RESULT_BEGIN -> Brimstone on YOU! (player)
local COLDFLAME_STOMP  = 234521   -- combatRoute: ACTION_RESULT_BEGIN -> Coldflame Stomp caAlertCast
local BRIMSTONE_STOMP  = 234524   -- combatRoute: ACTION_RESULT_BEGIN -> Brimstone Stomp caAlertCast
-- Dragon breath
local MYRINAX_BREATH   = 234548   -- combatRoute: ACTION_RESULT_BEGIN -> BREATH MOVE! alert (player)
local VALNEER_BREATH   = 234558   -- combatRoute: ACTION_RESULT_BEGIN -> BREATH MOVE! alert (player)
-- Heat Rays (dragon summon breath on player)
local JYN_HEAT_RAY     = 234141   -- combatRoute: ACTION_RESULT_BEGIN -> Heat Ray alert (player)
local SKOR_HEAT_RAY    = 234161   -- combatRoute: ACTION_RESULT_BEGIN -> Heat Ray alert (player)
-- Tail Slam
local TAIL_SLAM_1      = 235800   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> Tail Slam caAlertCast
local TAIL_SLAM_2      = 235803   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> Tail Slam caAlertCast
-- Reflective Scales - yellow border when dragon buff is active (stop DPS)
local REFLECTIVE_1     = 233321   -- combatRoute: EFFECT_GAINED -> border on; EFFECT_FADED -> border off
local REFLECTIVE_2     = 233330   -- combatRoute: EFFECT_GAINED -> border on; EFFECT_FADED -> border off

-- LEAP_IDS = { TITANIC_LEAP_1..6 }  -- reference: leap detection set (IDs routed individually)
-- LEAP_FIRST_CD = 5.0               -- reference: first leap delay (proactive timer; unimplemented)

-- -- Timer durations (seconds) ---------------------------------------------------------------------
local LEAP_CD       = 48.0

-- -- CA colour palettes ----------------------------------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 2000   -- Tail Slam: empirical

local JynorahEncounter = {}
JynorahEncounter.__index = JynorahEncounter

JynorahEncounter.key               = "jynorah"
JynorahEncounter.nameAliases       = { Lang.t("boss_jynorah"), Lang.t("boss_skorkhif") }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
JynorahEncounter.hmHealthThreshold = math.huge
-- location: placeholder - Oathsworn Pit arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

JynorahEncounter.stateSchema = {
    leapTimer    = function() return Timer.new(LEAP_CD) end,
    clashTimer   = function() return Timer.new(37.5) end,
    firstLeap    = true,
    clashActive  = false,
    playerCurse  = false,
}

function JynorahEncounter.new()
    return BossBase.fromSchema(JynorahEncounter)
end

-- -- Handlers --------------------------------------------------------------------------------------

-- Titanic Leap: shared handler for all 6 leap variant IDs.
local function handleLeap(self, context, alerts, abilityId, ...)
    self.firstLeap = false
    self.leapTimer:reset(LEAP_CD)
    alerts:showAction(Lang.t("oc_jynorah_titanic_leap"))
end

-- Reflective Scales: yellow border while the dragon buff is active.
-- Uses plain-function routing so it receives the result code and handles both
-- ACTION_RESULT_EFFECT_GAINED (border on) and ACTION_RESULT_EFFECT_FADED (border off).
local function handleReflective(self, context, alerts, result, abilityId,
                                  unitTag, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        CA.border(true, 6000, "yellow")
        alerts:showAction(Lang.t("oc_jynorah_reflective"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        CA.border(false, 0, "yellow")
    end
end

-- Tail Slam: shared handler for both variants.
local function handleTailSlam(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_jynorah_tail_slam_bar", target), dur, Colors.RED)
end

local function handleTitanicClash(self, context, alerts, abilityId, ...)
    self.clashActive = true
    self.clashTimer:reset(37.5)
    CA.ranged(abilityId, Lang.t("oc_jynorah_clash_bar"), 3500, Colors.RED)
    alerts:showAction(Lang.t("oc_jynorah_titanic_clash"))
end

local function handleTitanicClashHitV(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("oc_jynorah_valneer_hit"))
end

local function handleTitanicClashHitM(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("oc_jynorah_myrinax_hit"))
end

local function handleSparkingCurseCast(self, context, alerts, abilityId,
                                        unitTag, sourceUnitTag, sourceUnitId, unitId,
                                        sourceUnitName, unitName)
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("oc_jynorah_curse_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_jynorah_sparking_you"))
    else
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction(Lang.t("oc_jynorah_sparking_tgt", target))
    end
end

local function handleBlazingCurseCast(self, context, alerts, abilityId,
                                       unitTag, sourceUnitTag, sourceUnitId, unitId,
                                       sourceUnitName, unitName)
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("oc_jynorah_curse_alert"), 0xFF8844FF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_jynorah_blazing_you"))
    else
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction(Lang.t("oc_jynorah_blazing_tgt", target))
    end
end

local function handleSparkingCurseDebuf(self, context, alerts, abilityId,
                                         unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    self.playerCurse = "sparking"
    CA.border(true, 30000, "blue")
    CA.alert(nil, Lang.t("oc_jynorah_sparking_blue"), 0x44CCFFFF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_jynorah_sparking_valneer"))
end

local function handleBlazingCurseDebuf(self, context, alerts, abilityId,
                                        unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    self.playerCurse = "blazing"
    CA.border(true, 30000, "red")
    CA.alert(nil, Lang.t("oc_jynorah_blazing_red"), 0xFF8844FF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_jynorah_blazing_myrinax"))
end

local function handleColdflameSurge(self, context, alerts, abilityId,
                                     unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_surge_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_coldflame"))
end

local function handleBrimstoneSurge(self, context, alerts, abilityId,
                                     unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_surge_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_brimstone"))
end

local function handleColdflameStomp(self, context, alerts, abilityId, ...)
    CA.ranged(abilityId, Lang.t("oc_jynorah_stomp_bar"), 2000, Colors.ICE)
end

local function handleBrimstoneStomp(self, context, alerts, abilityId, ...)
    CA.ranged(abilityId, Lang.t("oc_jynorah_stomp_bar"), 2000, Colors.ORANGE)
end

local function handleHeatRay(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_heat_ray_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_heat_ray"))
end

local function handleMyrinaxBreath(self, context, alerts, abilityId,
                                    unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_breath_alert"), 0x44CCFFFF, SOUNDS.NONE, 2500)
    alerts:showAction(Lang.t("oc_jynorah_myrinax_breath"))
end

local function handleValneerBreath(self, context, alerts, abilityId,
                                    unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_breath_alert"), 0xFF8844FF, SOUNDS.NONE, 2500)
    alerts:showAction(Lang.t("oc_jynorah_valneer_breath"))
end

-- -- Routing tables (C3) ----------------------------------------------------------------------------

-- Shared trash-mechanic handler (Skullstorm, Toxic Ire, borders, Detonate Soul,
-- Life Drain, Caustic Carrion stacks).
JynorahEncounter.common = OsseinCageCommon

JynorahEncounter.combatRoutes = {
    [TITANIC_CLASH]       = { result = ACTION_RESULT_BEGIN,                  fn = handleTitanicClash },
    -- Titanic Clash hits (which dragon was struck)
    [TITANIC_CLASH_HIT_V] = { result = ACTION_RESULT_BEGIN,                  fn = handleTitanicClashHitV },
    [TITANIC_CLASH_HIT_M] = { result = ACTION_RESULT_BEGIN,                  fn = handleTitanicClashHitM },
    -- Titanic Leap (6 variants)
    [TITANIC_LEAP_1]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_2]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_3]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_4]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_5]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_6]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    -- Curse casts
    [SPARKING_CURSE_CAST]  = { result = ACTION_RESULT_BEGIN,                 fn = handleSparkingCurseCast },
    [BLAZING_CURSE_CAST]   = { result = ACTION_RESULT_BEGIN,                 fn = handleBlazingCurseCast },
    -- Curse debuffs on player (border + swap sides)
    [SPARKING_CURSE_DEBUF] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleSparkingCurseDebuf },
    [BLAZING_CURSE_DEBUF]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleBlazingCurseDebuf },
    -- AoE surges (player targeted)
    [COLDFLAME_SURGE]      = { result = ACTION_RESULT_BEGIN,                 fn = handleColdflameSurge },
    [BRIMSTONE_SURGE]      = { result = ACTION_RESULT_BEGIN,                 fn = handleBrimstoneSurge },
    [COLDFLAME_STOMP]      = { result = ACTION_RESULT_BEGIN,                 fn = handleColdflameStomp },
    [BRIMSTONE_STOMP]      = { result = ACTION_RESULT_BEGIN,                 fn = handleBrimstoneStomp },
    -- Heat Rays (dragon summon breath  -  alerts only if player is targeted)
    [JYN_HEAT_RAY]         = { result = ACTION_RESULT_BEGIN,                 fn = handleHeatRay },
    [SKOR_HEAT_RAY]        = { result = ACTION_RESULT_BEGIN,                 fn = handleHeatRay },
    -- Dragon breaths (player targeted)
    [MYRINAX_BREATH]       = { result = ACTION_RESULT_BEGIN,                 fn = handleMyrinaxBreath },
    [VALNEER_BREATH]       = { result = ACTION_RESULT_BEGIN,                 fn = handleValneerBreath },
    -- Reflective Scales: plain fn handles EFFECT_GAINED (border on) and EFFECT_FADED (border off).
    [REFLECTIVE_1]         = handleReflective,
    [REFLECTIVE_2]         = handleReflective,
    -- Tail Slam (caAlertCast)
    [TAIL_SLAM_1]          = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleTailSlam },
    [TAIL_SLAM_2]          = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleTailSlam },
}

-- -- Info-line renderers ----------------------------------------------------------------------------

-- Line 1: Titanic Clash active phase countdown; auto-clears when expired.
local function showClashLine(self, alerts)
    if self.clashActive then
        local r = self.clashTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Fmt.c("FF4444", Lang.t("oc_jynorah_clash_timer")), r)
        else
            self.clashActive = false
            alerts:clearRow(1)
        end
    else
        alerts:clearRow(1)
    end
end

-- Line 2: Titanic Leap cooldown; shows "first ~5s" before the first leap is seen.
local function showLeapLine(self, alerts)
    if self.firstLeap then
        alerts:setRow(2, Lang.t("oc_jynorah_leap_first"), nil)
    else
        local r = self.leapTimer:remaining()
        if r > 0 then
            alerts:setRow(2, Lang.t("oc_jynorah_leap_label"), r)
        else
            alerts:setRow(2, Lang.t("oc_jynorah_leap_label") .. " " .. Lang.t("common_now"), nil)
        end
    end
end

function JynorahEncounter:onWipe()
    OsseinCageCommon.reset()
    self.leapTimer:clear(); self.clashTimer:clear()
    self.firstLeap  = true; self.clashActive = false
    self.playerCurse = false
    CA.border(false, 0, "blue")
    CA.border(false, 0, "red")
    CA.border(false, 0, "yellow")
end

function JynorahEncounter:onUpdate(context, alerts)
    showClashLine(self, alerts)
    showLeapLine(self, alerts)
    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

package.loaded["trial.oc.boss.JynorahEncounter"] = JynorahEncounter
return JynorahEncounter