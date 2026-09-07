local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")

-- -- Ability IDs --------------------------------------------------------------------
local VIVIFY           = 186000   -- combatRoute: ACTION_RESULT_EFFECT_FADED -> Chimera spawned, reset timers
local PETRIFY          = 185039   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> despawning, clear timers
-- Chain Lightning  -  14 variants
local CHAIN_LIGHTNING_1  = 183858  -- combatRoute: ACTION_RESULT_BEGIN -> Chain Lightning alert, reset chainTimer
local CHAIN_LIGHTNING_2  = 183898
local CHAIN_LIGHTNING_3  = 183911
local CHAIN_LIGHTNING_4  = 183913
local CHAIN_LIGHTNING_5  = 184033
local CHAIN_LIGHTNING_6  = 184028
local CHAIN_LIGHTNING_7  = 184036
local CHAIN_LIGHTNING_8  = 184032
local CHAIN_LIGHTNING_9  = 184029
local CHAIN_LIGHTNING_10 = 184030
local CHAIN_LIGHTNING_11 = 183915
local CHAIN_LIGHTNING_12 = 183917
local CHAIN_LIGHTNING_13 = 183885
-- Chain Circuit debuffs on players  -  4 variants
local CHAIN_CIRCUIT_1  = 184063   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> player alert
local CHAIN_CIRCUIT_2  = 184068   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> player alert
local CHAIN_CIRCUIT_3  = 184066   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> player alert
local CHAIN_CIRCUIT_4  = 184067   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION -> player alert
-- Arctic Shred (~5.5 s cooldown)
local ARCTIC_SHRED     = 184275   -- combatRoute: ACTION_RESULT_BEGIN -> alert
-- Sub-boss abilities
local LION_DOUBLE_STRIKE = 186969  -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (Ascendant Lion)
local GRYPHON_PECK       = 187002  -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (Ascendant Gryphon)
local CHIMERA_BOLT     = 186960   -- combatRoute: ACTION_RESULT_BEGIN -> Bolt caAlertCast (targeted)
local GRYPHON_WIND_LANCE = 199132 -- combatRoute: ACTION_RESULT_BEGIN -> Wind Lance alert
-- Portal mantle buffs (assigned portal type on player)
local MANTLE_WAMASU    = 184984   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> Wamasu portal (makePortalHandler)
local MANTLE_LION      = 184983   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> Lion portal (makePortalHandler)
local MANTLE_GRYPHON   = 183640   -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> Gryphon portal (makePortalHandler)

-- -- Timer durations (seconds) -----------------------------------------------------
local DESPAWN_CD           = 92   -- Chimera despawns ~92s after spawn
local CHAIN_FIRST_CD       =  5   -- first chain lightning after spawn
local CHAIN_CD             = 20   -- subsequent chain lightning CD

-- -- CA colour palettes ------------------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR      = 2000   -- Lightning Bolt / Lion / Gryphon: empirical
local FALLBACK_SHRED_DUR = 1500  -- Arctic Shred: empirical

local ChimeraEncounter = {}
ChimeraEncounter.__index = ChimeraEncounter

ChimeraEncounter.key               = "chimera"
ChimeraEncounter.nameAliases       = { Lang.t("boss_chimera") }
ChimeraEncounter.hmHealthThreshold = 70000000   -- vet ~46.5M, HM ~93.1M
-- location: placeholder - Sunken Elder arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

ChimeraEncounter.stateSchema = {
    despawnTimer   = function() return Timer.new(DESPAWN_CD) end,
    chainTimer     = function() return Timer.new(CHAIN_CD) end,
    chimeraActive  = false,
    firstChain     = true,
    alertList      = function() return {} end,
}

function ChimeraEncounter.new()
    return BossBase.fromSchema(ChimeraEncounter)
end

-- -- Lifecycle ---------------------------------------------------------------------
function ChimeraEncounter:onLeave(context)
    self:cleanupAlertList()
end

function ChimeraEncounter:onWipe()
    self:cleanupAlertList()
    self.despawnTimer:clear(); self.chainTimer:clear()
    self.chimeraActive = false; self.firstChain = true
end

-- -- Handlers ----------------------------------------------------------------------

-- Portal mantle: personal alert when assigned to a portal.
local function makePortalHandler(labelKey, colorHex)
    return { result = ACTION_RESULT_EFFECT_GAINED,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        local label = Lang.t(labelKey)
        alerts:showAction(label .. "!")
        CA.alert(nil, label, colorHex, SOUNDS.NONE, 4000)
    end }
end

local function handleVivify(self, context, alerts, abilityId, ...)
    self.chimeraActive = true
    self.firstChain    = true
    self.despawnTimer:reset(DESPAWN_CD)
    self.chainTimer:reset(CHAIN_FIRST_CD)
    alerts:showHeader(Lang.t("se_chimera_header"))
end

local function handlePetrify(self, context, alerts, abilityId, ...)
    self.chimeraActive = false
    self.despawnTimer:clear()
    self.chainTimer:clear()
    alerts:showAction(Lang.t("se_chimera_despawning"))
end

local function handleChainLightning(self, context, alerts, abilityId, ...)
    self.firstChain = false
    self.chainTimer:reset(CHAIN_CD)
    alerts:showAction(Lang.t("se_chimera_chain_lightning"))
    CA.alert(nil, Lang.t("se_chimera_chain_lightning_alert"), 0xFFD666FF, SOUNDS.NONE, 2500)
end

local function handleChainCircuit(self, context, alerts, abilityId,
                                   unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_chimera_chain_circuit"))
    CA.alert(nil, Lang.t("se_chimera_chain_circuit_alert"), 0xFFD666FF, SOUNDS.NONE, 3000)
end

local function handleArcticShred(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_chimera_arctic_shred", target))
    local dur = CastDur.get(abilityId, FALLBACK_SHRED_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_arctic_shred_bar"), dur, Colors.ICE)
end

local function handleLionDoubleStrike(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_lion_double_bar"), dur, Colors.ORANGE)
    alerts:showAction(Lang.t("se_chimera_lion_double"))
end

local function handleGryphonPeck(self, context, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_gryphon_peck_bar"), dur, Colors.ICE)
    alerts:showAction(Lang.t("se_chimera_gryphon_peck"))
end

local function handleChimeraBolt(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_chimera_lightning_bolt", target))
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, Lang.t("se_chimera_bolt_bar"), dur, Colors.GOLD)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleGryphonWindLance(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_chimera_wind_lance"))
    CA.alert(nil, Lang.t("se_chimera_wind_lance_alert"), 0xD1F1F9FF, SOUNDS.NONE, 2000)
end

-- -- Routing tables (C3) -----------------------------------------------------------

ChimeraEncounter.combatRoutes = {
    [VIVIFY]             = { result = ACTION_RESULT_EFFECT_FADED,           fn = handleVivify },
    [PETRIFY]            = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,  fn = handlePetrify },
    -- Chain Lightning (14 variants)
    [CHAIN_LIGHTNING_1]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_2]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_3]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_4]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_5]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_6]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_7]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_8]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_9]  = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_10] = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_11] = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_12] = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    [CHAIN_LIGHTNING_13] = { result = ACTION_RESULT_BEGIN,                   fn = handleChainLightning },
    -- Chain Circuit debuffs (4 variants, player-targeted)
    [CHAIN_CIRCUIT_1]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,  fn = handleChainCircuit },
    [CHAIN_CIRCUIT_2]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,  fn = handleChainCircuit },
    [CHAIN_CIRCUIT_3]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,  fn = handleChainCircuit },
    [CHAIN_CIRCUIT_4]    = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,  fn = handleChainCircuit },
    -- Sub-boss abilities
    [ARCTIC_SHRED]         = { result = ACTION_RESULT_BEGIN,                 fn = handleArcticShred },
    [LION_DOUBLE_STRIKE]   = { result = ACTION_RESULT_BEGIN,                 fn = handleLionDoubleStrike },
    [GRYPHON_PECK]         = { result = ACTION_RESULT_BEGIN,                 fn = handleGryphonPeck },
    [CHIMERA_BOLT]         = { result = ACTION_RESULT_BEGIN,                 fn = handleChimeraBolt },
    [GRYPHON_WIND_LANCE]   = { result = ACTION_RESULT_BEGIN,                 fn = handleGryphonWindLance },
    -- Portal mantle buffs (factory entries - EXEMPT from D7)
    [MANTLE_WAMASU]  = makePortalHandler("se_chimera_portal_wamasu",  0x02FF00FF),
    [MANTLE_LION]    = makePortalHandler("se_chimera_portal_lion",    0xFF0000FF),
    [MANTLE_GRYPHON] = makePortalHandler("se_chimera_portal_gryphon", 0x0044FFFF),
}

-- -- Info-line renderers -----------------------------------------------------------

-- Lines 1-2: Chimera despawn countdown and Chain Lightning CD; cleared when inactive.
local function showChimeraLines(self, alerts)
    if self.chimeraActive then
        local rd = self.despawnTimer:remaining()
        local rc = self.chainTimer:remaining()
        if rd > 0 then
            alerts:setRow(1, Lang.t("se_chimera_despawn_label"), rd)
        else
            alerts:setRow(1, Lang.t("se_chimera_despawn_label") .. " " .. Lang.t("common_imminent"), nil)
        end
        if rc > 0 then
            alerts:setRow(2, Lang.t("se_chimera_chain_label"), rc)
        else
            alerts:setRow(2, Lang.t("se_chimera_chain_label") .. " " .. Lang.t("common_ready"), nil)
        end
    else
        alerts:clearRow(1)
        alerts:clearRow(2)
    end
end

function ChimeraEncounter:onUpdate(context, alerts)
    showChimeraLines(self, alerts)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function ChimeraEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Chimera.
end

package.loaded["trial.se.boss.ChimeraEncounter"] = ChimeraEncounter
return ChimeraEncounter
