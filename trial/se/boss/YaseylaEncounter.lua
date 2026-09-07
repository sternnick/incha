local Timer    = require("lib.Timer")

local CA       = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur  = require("lib.CastDur")
local Lang     = require("core.Lang")
local Settings = require("core.Settings")
local Colors = require("core.Colors")

-- -- Ability IDs (from SanitysEdgeHelper / SSEA data) ------------------------------
local DEFLECT         = 184823   -- combatRoute: ACTION_RESULT_BEGIN -> Shrapnel stack counter
local SHRAPNEL        = 199131   -- combatRoute: ACTION_RESULT_BEGIN -> Shrapnel alert (stack!)
local FIRE_BOMBS      = 183660   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (targeted)
local KNIFE_BLAST_1   = 183803   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local KNIFE_BLAST_2   = 183804   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local VENGEFUL_STRIKE = 185071   -- combatRoute: ACTION_RESULT_BEGIN -> alert
local VANTONS_CLARITY = 184041   -- combatRoute: ACTION_RESULT_BEGIN -> Portal synergy alert
local SEETHE          = 162783   -- combatRoute: ACTION_RESULT_BEGIN -> Enrage alert
local CHAIN_PULL      = 184540   -- combatRoute: ACTION_RESULT_BEGIN -> Chains alert
-- Frost Bombs (Tomb mechanic)  -  10 variants
local FROST_BOMB_1    = 185403   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_2    = 183783   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_3    = 183790   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_4    = 192304   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_5    = 191049   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_6    = 188065   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_7    = 199254   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_8    = 185406   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_9    = 183768   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local FROST_BOMB_10   = 185392   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Frost bomb alert
local IGNITE          = 188188   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> Move alert (player)
-- Wamasu Charges  -  6 variants
local WAMASU_CHARGE_1 = 191133   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local WAMASU_CHARGE_2 = 191139   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local WAMASU_CHARGE_3 = 191134   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local WAMASU_CHARGE_4 = 200544   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local WAMASU_CHARGE_5 = 200558   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
local WAMASU_CHARGE_6 = 200559   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast
-- Wamasu Charged Headbutt  -  3 variants
local HEADBUTT_1      = 184999   -- combatRoute: ACTION_RESULT_BEGIN -> Headbutt alert
local HEADBUTT_2      = 185002   -- combatRoute: ACTION_RESULT_BEGIN -> Headbutt alert
local HEADBUTT_3      = 185000   -- combatRoute: ACTION_RESULT_BEGIN -> Headbutt alert
-- Wamasu Overwhelming Lightning  -  3 variants
local OVW_LIGHTNING_1 = 183598   -- combatRoute: ACTION_RESULT_BEGIN -> Lightning alert
local OVW_LIGHTNING_2 = 198510   -- combatRoute: ACTION_RESULT_BEGIN -> Lightning alert
local OVW_LIGHTNING_3 = 183599   -- combatRoute: ACTION_RESULT_BEGIN -> Lightning alert
-- 184802 (ARCHER_TRUE_SHOT)  -- deleted: no route; no mechanic planned

-- -- Timer durations (seconds) -----------------------------------------------------
-- FIREBOMB_FIRST_CD = 7.5  -- reference: first firebombs delay from combat start (proactive timer; unimplemented)
local FIREBOMB_CD        = 23.5   -- pre-execute CD
local FIREBOMB_EXEC_CD   = 11     -- execute-phase CD (after <26% HP)
local FIREBOMB_EXEC_THOLD= 26     -- % HP that marks execute phase
local CHAIN_CD           = 32     -- chain pull CD
-- FROST_FIRST_CD = 17      -- reference: first frost bomb delay (proactive timer; unimplemented)
local FROST_CD           = 25     -- subsequent frost bomb CD

-- -- CA colour palettes ------------------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 2000   -- FireBombs / WamasuCharge / KnifeBlast: empirical

local YaseylaEncounter = {}
YaseylaEncounter.__index = YaseylaEncounter

YaseylaEncounter.key               = "yaseyla"
YaseylaEncounter.nameAliases       = { Lang.t("boss_yaseyla") }
YaseylaEncounter.hmHealthThreshold = 80000000   -- vet ~65M, HM ~97.8M
-- location: placeholder - Sunken Elder arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

YaseylaEncounter.stateSchema = {
    firebombTimer  = function() return Timer.new(FIREBOMB_CD) end,
    chainTimer     = function() return Timer.new(CHAIN_CD) end,
    frostTimer     = function() return Timer.new(FROST_CD) end,
    executePhase   = false,
    firstFirebomb  = true,
    firstFrost     = true,
    shrapnelCount  = 0,
    alertList      = function() return {} end,
    -- HP milestone flags (Wamasu/Archers warnings at 90/70/50/30/20/10%,
    -- portal warnings at 60/35%, Shrapnel warnings at 80/55/25/20/10%)
    m90 = false, m80 = false, m70 = false, m60 = false, m55 = false,
    m50 = false, m35 = false, m30 = false, m25 = false, m20 = false, m10 = false,
}

function YaseylaEncounter.new()
    return BossBase.fromSchema(YaseylaEncounter)
end

-- -- Lifecycle ---------------------------------------------------------------------
function YaseylaEncounter:onLeave(context)
    self:cleanupAlertList()
end

function YaseylaEncounter:onWipe()
    self:cleanupAlertList()
    self.firebombTimer:clear(); self.chainTimer:clear(); self.frostTimer:clear()
    self.executePhase  = false; self.firstFirebomb = true
    self.firstFrost    = true;  self.shrapnelCount = 0
    self.m90 = false; self.m80 = false; self.m70 = false; self.m60 = false
    self.m55 = false; self.m50 = false; self.m35 = false; self.m30 = false
    self.m25 = false; self.m20 = false; self.m10 = false
end

-- -- Routing tables (C3) -----------------------------------------------------------

-- Frost Bomb: shared handler for all ability IDs.
local function handleFrostBomb(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    self.firstFrost = false
    self.frostTimer:reset(FROST_CD)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("se_yaseyla_frost_bomb_you"))
        CA.alert(nil, Lang.t("se_yaseyla_frost_bomb_alert"), 0x99CCFFFF, SOUNDS.NONE, 3000)
    elseif unitName and unitName ~= "" then
        alerts:showAction(Lang.t("se_yaseyla_frost_bomb_tgt", unitName))
    end
end

local function handleFireBombs(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    self.firstFirebomb = false
    local cd = self.executePhase and FIREBOMB_EXEC_CD or FIREBOMB_CD
    self.firebombTimer:reset(cd)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_yaseyla_fire_bombs_tgt", target))
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, Lang.t("se_yaseyla_fire_bombs_bar"), dur, Colors.FIRE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleChainPull(self, context, alerts, abilityId, ...)
    self.chainTimer:reset(CHAIN_CD)
    alerts:showAction(Lang.t("se_yaseyla_chains"))
end

local function handleIgnite(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_yaseyla_ignite"))
end

local function handleDeflect(self, context, alerts, abilityId, ...)
    self.shrapnelCount = self.shrapnelCount + 1
    alerts:showAction(Lang.t("se_yaseyla_shrapnel_you", self.shrapnelCount))
    CA.alert(nil, Lang.t("se_yaseyla_deflect_alert"), 0xFF0033FF, SOUNDS.NONE, 3000)
end

local function handleShrapnel(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_shrapnel"))
    CA.alert(nil, Lang.t("se_yaseyla_shrapnel_alert"), 0xFF0033FF, SOUNDS.NONE, 3000)
end

local function handleKnifeBlast(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_yaseyla_knife_blast_bar", target), dur, Colors.AMBER)
    alerts:showAction(Lang.t("se_yaseyla_knife_blast", target))
end

local function handleVengefulStrike(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_vengeful_strike"))
    CA.alert(nil, Lang.t("se_yaseyla_vengeful_alert"), 0xFF4400FF, SOUNDS.NONE, 2500)
end

local function handleVantonsClarity(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_portal"))
    CA.alert(nil, Lang.t("se_yaseyla_portal_alert"), 0xAAFFAAFF, SOUNDS.NONE, 4000)
end

local function handleSeethe(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_enrage"))
    CA.alert(nil, Lang.t("se_yaseyla_enrage_alert"), 0xFF0000FF, SOUNDS.NONE, 5000)
end

local function handleWamasuCharge(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_yaseyla_charge_bar", target), dur, Colors.FIRE)
end

local function handleHeadbutt(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_yaseyla_headbutt", target))
    CA.alert(nil, Lang.t("se_yaseyla_headbutt_alert"), 0xFF6600FF, SOUNDS.NONE, 2500)
end

local function handleOvwLightning(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_yaseyla_overwhelming"))
    CA.alert(nil, Lang.t("se_yaseyla_ovw_lightning"), 0xFFDD44FF, SOUNDS.NONE, 3000)
end

YaseylaEncounter.combatRoutes = {
    [FIRE_BOMBS]      = { result = ACTION_RESULT_BEGIN,                  fn = handleFireBombs },
    [KNIFE_BLAST_1]   = { result = ACTION_RESULT_BEGIN,                  fn = handleKnifeBlast },
    [KNIFE_BLAST_2]   = { result = ACTION_RESULT_BEGIN,                  fn = handleKnifeBlast },
    [VENGEFUL_STRIKE] = { result = ACTION_RESULT_BEGIN,                  fn = handleVengefulStrike },
    [VANTONS_CLARITY] = { result = ACTION_RESULT_BEGIN,                  fn = handleVantonsClarity },
    [SEETHE]          = { result = ACTION_RESULT_BEGIN,                  fn = handleSeethe },
    [CHAIN_PULL]      = { result = ACTION_RESULT_BEGIN,                  fn = handleChainPull },
    [DEFLECT]         = { result = ACTION_RESULT_BEGIN,                  fn = handleDeflect },
    [SHRAPNEL]        = { result = ACTION_RESULT_BEGIN,                  fn = handleShrapnel },
    -- Wamasu Charges (all 6 variants)
    [WAMASU_CHARGE_1] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    [WAMASU_CHARGE_2] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    [WAMASU_CHARGE_3] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    [WAMASU_CHARGE_4] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    [WAMASU_CHARGE_5] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    [WAMASU_CHARGE_6] = { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
    -- Wamasu Headbutts (3 variants)
    [HEADBUTT_1]      = { result = ACTION_RESULT_BEGIN,                  fn = handleHeadbutt },
    [HEADBUTT_2]      = { result = ACTION_RESULT_BEGIN,                  fn = handleHeadbutt },
    [HEADBUTT_3]      = { result = ACTION_RESULT_BEGIN,                  fn = handleHeadbutt },
    -- Overwhelming Lightning (3 variants, player-targeted)
    [OVW_LIGHTNING_1] = { result = ACTION_RESULT_BEGIN,                  fn = handleOvwLightning },
    [OVW_LIGHTNING_2] = { result = ACTION_RESULT_BEGIN,                  fn = handleOvwLightning },
    [OVW_LIGHTNING_3] = { result = ACTION_RESULT_BEGIN,                  fn = handleOvwLightning },
    -- Frost Bombs (10 variants)
    [FROST_BOMB_1]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_2]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_3]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_4]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_5]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_6]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_7]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_8]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_9]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_10]   = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [IGNITE]          = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleIgnite },
}

-- -- Info-line renderers -----------------------------------------------------------

-- Line 1: Fire Bombs CD; label switches to "Bombs (exec)" once execute phase begins.
local function showFireBombLine(self, alerts)
    if self.firstFirebomb then
        alerts:setRow(1, Lang.t("se_yaseyla_fire_bombs_first"), nil)
    else
        local r     = self.firebombTimer:remaining()
        local label = self.executePhase
            and Lang.t("se_yaseyla_bombs_exec_name")
            or  Lang.t("se_yaseyla_fire_bombs_name")
        if r > 0 then
            alerts:setRow(1, label, r)
        else
            alerts:setRow(1, label .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

-- Line 3: Frost Bomb CD; shows estimated first-cast window before the ability is seen.
local function showFrostBombLine(self, alerts)
    if self.firstFrost then
        alerts:setRow(3, Lang.t("se_yaseyla_frost_first"), nil)
    else
        local r = self.frostTimer:remaining()
        if r > 0 then
            alerts:setRow(3, Lang.t("se_yaseyla_frost_bomb_label"), r)
        else
            alerts:setRow(3, Lang.t("se_yaseyla_frost_bomb_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

function YaseylaEncounter:onUpdate(context, alerts)
    showFireBombLine(self, alerts)
    local rc = self.chainTimer:remaining()
    if rc > 0 then
        alerts:setRow(2, Lang.t("se_yaseyla_chains_label"), rc)
    else
        alerts:setRow(2, Lang.t("se_yaseyla_chains_label") .. " " .. Lang.t("common_ready"), nil)
    end
    showFrostBombLine(self, alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function YaseylaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- Enter execute phase when HP drops below 26%
    if not self.executePhase and healthPercent > 0 and healthPercent < FIREBOMB_EXEC_THOLD then
        self.executePhase = true
        alerts:showAction(Lang.t("se_yaseyla_execute"))
    end

    -- HP milestone pre-warnings (Wamasu+Archers at 90/70/50/30/20/10%;
    -- portal at 60/35%; Shrapnel at 80/55/25/20/10%; gated by showPercent toggle)
    if not Settings.trial("se").showPercent then return end
    if not self.m90 and healthPercent < 90 then
        self.m90 = true
        alerts:showAction(Lang.t("se_yaseyla_90pct"))
    elseif not self.m80 and healthPercent < 80 then
        self.m80 = true
        alerts:showAction(Lang.t("se_yaseyla_80pct"))
    elseif not self.m70 and healthPercent < 70 then
        self.m70 = true
        alerts:showAction(Lang.t("se_yaseyla_70pct"))
    elseif not self.m60 and healthPercent < 60 then
        self.m60 = true
        alerts:showAction(Lang.t("se_yaseyla_60pct"))
        CA.alert(nil, Lang.t("se_yaseyla_portal_pct_alert", 60), 0xAAFFAAFF, SOUNDS.NONE, 4000)
    elseif not self.m55 and healthPercent < 55 then
        self.m55 = true
        alerts:showAction(Lang.t("se_yaseyla_55pct"))
    elseif not self.m50 and healthPercent < 50 then
        self.m50 = true
        alerts:showAction(Lang.t("se_yaseyla_50pct"))
    elseif not self.m35 and healthPercent < 35 then
        self.m35 = true
        alerts:showAction(Lang.t("se_yaseyla_35pct"))
        CA.alert(nil, Lang.t("se_yaseyla_portal_pct_alert", 35), 0xAAFFAAFF, SOUNDS.NONE, 4000)
    elseif not self.m30 and healthPercent < 30 then
        self.m30 = true
        alerts:showAction(Lang.t("se_yaseyla_30pct"))
    elseif not self.m25 and healthPercent < 25 then
        self.m25 = true
        alerts:showAction(Lang.t("se_yaseyla_25pct"))
    elseif not self.m20 and healthPercent < 20 then
        self.m20 = true
        alerts:showAction(Lang.t("se_yaseyla_20pct"))
    elseif not self.m10 and healthPercent < 10 then
        self.m10 = true
        alerts:showAction(Lang.t("se_yaseyla_10pct"))
    end
end

package.loaded["trial.se.boss.YaseylaEncounter"] = YaseylaEncounter
return YaseylaEncounter
