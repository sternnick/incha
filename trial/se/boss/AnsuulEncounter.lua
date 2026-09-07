local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")

-- -- Ability IDs --------------------------------------------------------------------
local SUNBURST         = 199344   -- combatRoute: ACTION_RESULT_BEGIN -> Dodge alert (player only)
local WRACK            = 184621   -- combatRoute: ACTION_RESULT_BEGIN -> Kite alert
local WRATHSTORM       = 198759   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local CALAMITY         = 186728   -- combatRoute: ACTION_RESULT_BEGIN -> Calamity Stack alert
local EXECUTE          = 198797   -- combatRoute: ACTION_RESULT_BEGIN -> INTERRUPT alert
-- Poisoned Mind  -  4 variants (+184710 kept for safety)
local POISONED_MIND_1  = 184707   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> green border
local POISONED_MIND_2  = 184709   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> green border
local POISONED_MIND_3  = 199644   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> green border
local POISONED_MIND_4  = 184711   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> green border
local POISONED_MIND_5  = 184710   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> green border (extra variant)
-- Manic Phobia  -  4 variants
local MANIC_PHOBIA_1   = 185117   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> fear marker alert
local MANIC_PHOBIA_2   = 185123   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> fear marker alert
local MANIC_PHOBIA_3   = 185171   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> fear marker alert
local MANIC_PHOBIA_4   = 185251   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> fear marker alert
-- Enraged Atronachs
local ENRAGED_INFERNO  = 183778   -- combatRoute: ACTION_RESULT_BEGIN -> Interrupt! alert
local ENRAGED_FLARE    = 183784   -- combatRoute: ACTION_RESULT_BEGIN -> alert
-- Phase transitions
local THE_RITUAL       = 183855   -- combatRoute: multi-result -> maze phase
local BREAKDOWN_RED    = 188766   -- combatRoute: multi-result -> split phase
local BREAKDOWN_BLUE   = 188768   -- combatRoute: multi-result -> split phase
local BREAKDOWN_GREEN  = 188769   -- combatRoute: multi-result -> split phase

-- -- Timer durations (seconds) -----------------------------------------------------
local CALAMITY_FIRST_CD = 9    -- first calamity after combat start / maze end
local CALAMITY_CD       = 25   -- subsequent calamity CD

-- -- CA colour palettes ------------------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_SUNBURST_DUR   = 2000   -- Sunburst: empirical
local FALLBACK_WRATHSTORM_DUR = 4000   -- Wrathstorm: empirical

local AnsuulEncounter = {}
AnsuulEncounter.__index = AnsuulEncounter

AnsuulEncounter.key               = "ansuul"
AnsuulEncounter.nameAliases       = { Lang.t("boss_ansuul") }
AnsuulEncounter.hmHealthThreshold = 100000000  -- vet ~69M, HM ~160.7M
-- location: placeholder - Sunken Elder arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

AnsuulEncounter.stateSchema = {
    calamityTimer  = function() return Timer.new(CALAMITY_CD) end,
    firstCalamity  = true,
    inMaze         = false,
    inTriplet      = false,
    alertList      = function() return {} end,
}

function AnsuulEncounter.new()
    return BossBase.fromSchema(AnsuulEncounter)
end

-- -- Routing tables (C3) -----------------------------------------------------------

-- Breakdown (split phase): shared handler for red/blue/green clones.
local function handleBreakdown(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        if not self.inTriplet then
            self.inTriplet = true
            self.firstCalamity = true
            self.calamityTimer:reset(CALAMITY_FIRST_CD)
            alerts:showHeader(Lang.t("se_ansuul_triplet_header"))
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.inTriplet = false
        self.firstCalamity = true
        self.calamityTimer:reset(CALAMITY_CD)
        alerts:showAction(Lang.t("se_ansuul_triplet_ended"))
    end
end

local function handleCalamity(self, context, alerts, abilityId, ...)
    self.firstCalamity = false
    self.calamityTimer:reset(CALAMITY_CD)
    alerts:showAction(Lang.t("se_ansuul_calamity_stack"))
end

local function handleWrack(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_kite_wrack"))
    CA.alert(nil, Lang.t("se_ansuul_kite_alert"), 0xFFD666FF, SOUNDS.NONE, 3000)
end

local function handleExecute(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_interrupt_exec"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0033FF, SOUNDS.NONE, 2500)
end

local function handleSunburst(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_ansuul_sunburst"))
    local dur = CastDur.get(SUNBURST, FALLBACK_SUNBURST_DUR)
    CA.ranged(SUNBURST, Lang.t("se_ansuul_sunburst_bar"), dur, Colors.VOID)
end

local function handleWrathstorm(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(WRATHSTORM, FALLBACK_WRATHSTORM_DUR)
    CA.ranged(WRATHSTORM, Lang.t("se_ansuul_wrathstorm_bar"), dur, Colors.VOID)
end

local function handlePoisonedMind(self, context, alerts, abilityId,
                                   unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_ansuul_poisoned_mind"))
    CA.border(true, 8000, "green")
end

local function handleManicPhobia(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local name = IsUnitPlayer(unitTag) and Lang.t("common_you") or (unitName or "?")
    alerts:showAction(Lang.t("se_ansuul_manic_phobia", name))
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("se_ansuul_manic_alert"), 0xFF44FFFF, SOUNDS.NONE, 5000)
    end
end

local function handleEnragedInferno(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_interrupt_inf"))
    CA.alert(nil, Lang.t("se_ansuul_inferno_alert"), 0xFF0033FF, SOUNDS.NONE, 2500)
end

local function handleEnragedFlare(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_ansuul_enraged_flare", target))
    CA.alert(nil, Lang.t("se_ansuul_flare_alert"), 0xFF6600FF, SOUNDS.NONE, 2500)
end

local function handleTheRitual(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.inMaze = true
        alerts:showHeader(Lang.t("se_ansuul_maze_header"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.inMaze = false
        self.firstCalamity = true
        self.calamityTimer:reset(CALAMITY_FIRST_CD)
        alerts:showAction(Lang.t("se_ansuul_maze_cleared"))
    end
end

AnsuulEncounter.combatRoutes = {
    [CALAMITY]        = { result = ACTION_RESULT_BEGIN,                  fn = handleCalamity },
    [WRACK]           = { result = ACTION_RESULT_BEGIN,                  fn = handleWrack },
    [EXECUTE]         = { result = ACTION_RESULT_BEGIN,                  fn = handleExecute },
    [SUNBURST]        = { result = ACTION_RESULT_BEGIN,                  fn = handleSunburst },
    [WRATHSTORM]      = { result = ACTION_RESULT_BEGIN,                  fn = handleWrathstorm },
    -- Enraged Atronach abilities
    [ENRAGED_INFERNO] = { result = ACTION_RESULT_BEGIN,                  fn = handleEnragedInferno },
    [ENRAGED_FLARE]   = { result = ACTION_RESULT_BEGIN,                  fn = handleEnragedFlare },
    -- Poisoned Mind (5 variants, player-only green border)
    [POISONED_MIND_1] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePoisonedMind },
    [POISONED_MIND_2] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePoisonedMind },
    [POISONED_MIND_3] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePoisonedMind },
    [POISONED_MIND_4] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePoisonedMind },
    [POISONED_MIND_5] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePoisonedMind },
    -- Manic Phobia (4 variants, fear marker alert)
    [MANIC_PHOBIA_1]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleManicPhobia },
    [MANIC_PHOBIA_2]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleManicPhobia },
    [MANIC_PHOBIA_3]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleManicPhobia },
    [MANIC_PHOBIA_4]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleManicPhobia },
    -- Phase transitions (multi-result routes)
    [THE_RITUAL]       = handleTheRitual,
    [BREAKDOWN_RED]    = handleBreakdown,
    [BREAKDOWN_BLUE]   = handleBreakdown,
    [BREAKDOWN_GREEN]  = handleBreakdown,
}

-- -- Info-line renderers -----------------------------------------------------------

-- Line 1: Calamity countdown - context-aware: maze suppression, triplet urgency, or normal CD.
local function showCalamityLine(self, alerts)
    if self.inMaze then
        alerts:setRow(1, Lang.t("se_ansuul_maze_no_cal"), nil)
    elseif self.inTriplet then
        local r = self.calamityTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("se_ansuul_triplet_cal"), r)
        else
            alerts:setRow(1, Lang.t("se_ansuul_triplet_cal") .. " " .. Lang.t("se_ansuul_now"), nil)
        end
    elseif self.firstCalamity then
        alerts:setRow(1, Lang.t("se_ansuul_calamity_first"), nil)
    else
        local r = self.calamityTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("se_ansuul_calamity_label"), r)
        else
            alerts:setRow(1, Lang.t("se_ansuul_calamity_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

-- Line 2: Current phase label (triplet split or maze navigation).
local function showPhaseLine(self, alerts)
    if self.inTriplet then
        alerts:setRow(2, Lang.t("se_ansuul_split_phase"), nil)
    elseif self.inMaze then
        alerts:setRow(2, Lang.t("se_ansuul_navigate_maze"), nil)
    else
        alerts:clearRow(2)
    end
end

function AnsuulEncounter:onLeave(context)
    self:cleanupAlertList()
end

function AnsuulEncounter:onWipe()
    self:cleanupAlertList()
    self.calamityTimer:clear()
    self.firstCalamity = true
    self.inMaze        = false
    self.inTriplet     = false
end

function AnsuulEncounter:onUpdate(context, alerts)
    showCalamityLine(self, alerts)
    showPhaseLine(self, alerts)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function AnsuulEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Ansuul.
end

package.loaded["trial.se.boss.AnsuulEncounter"] = AnsuulEncounter
return AnsuulEncounter
