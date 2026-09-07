--- OsseinCageCommon  -  trash-add and cross-boss mechanics for all Ossein Cage arenas.
---
--- Applies regardless of which boss (Jynorah / Kazpian / Shaper of Flesh) is
--- active: tank-swap Hindered, Skullmancer Skullstorm cast bar, Spectral-Revenant
--- Toxic Ire (debounced once per 10 s), Murder Corvid and Deadraiser screen borders,
--- Soul Devourer Detonate Soul and Life Drain, and Caustic Carrion portal-debuff
--- stack tracking with colour-gradient info display.
---
--- Interface (same contract as RockgroveCommon / SunspireCommon):
---   .handle(alerts, result, abilityId, unitTag, sourceUnitName) -> bool
---       Called by CombatHandler before combatRoutes; true short-circuits routing.
---   .handleEffect(alerts, changeType, abilityId, unitTag, stackCount) -> bool
---       Called by CombatHandler before effectRoutes; true short-circuits routing.
---       stackCount is the 5th arg added to CombatHandler's handleEffect call.
---   .showCarrionInfo(alerts)
---       Write Caustic Carrion stack count to info line 3.
---       Each OC boss's onUpdate must call this instead of alerts:clearRow(3).
---
--- Hindered OSI icon: deferred  -  the unit OSI API requires in-game coordinate
--- measurement.  An alert fires for tanks instead.

local CA      = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang    = require("core.Lang")
local Fmt     = require("core.Fmt")
local Colors = require("core.Colors")

local OsseinCageCommon = {}

-- -- Ability IDs ------------------------------------------------------------
local HINDERED         = 165972   -- tank-swap debuff (Hindered)
local SKULLSTORM       = 236631   -- Skullmancer -> cast bar
local TOXIC_IRE        = 160007   -- Spectral Revenant -> debounced "you" alert
local CORVID_SWARM     = 236947   -- Murder Corvid -> purple screen border
local CURSED_TERRAIN   = 236571   -- Tormented Deadraiser -> green screen border
local DETONATE_SOUL_DB = 236778   -- Soul Devourer debuff on player -> cast bar + alert
local LIFE_DRAIN       = 236751   -- Soul Devourer combat hit on player -> alert

-- Both Caustic Carrion variants share the same stack-tracking logic.
local CAUSTIC_CARRION = { [240708] = true, [241089] = true }
--   240708: Trash / Boss 1 / Boss 3 portal debuff
--   241089: Boss 2 portal debuff

-- -- Debounce: Toxic Ire once per 10 s -------------------------------------
local _toxicIreLastMs = 0

-- -- Caustic Carrion: current player stack count ---------------------------
-- Stored at module level so showCarrionInfo can read it from boss:onUpdate.
local _carrionStacks = 0

-- -- Fallback cast durations (ms) ------------------------------------------
-- -- Registration sets -------------------------------------------------------
-- EventPipeline registers one ability-filtered handler per id here, so the
-- engine rejects everything else before it reaches Lua.  handle() and
-- handleEffect() gate on these same tables, which keeps the two in step: an
-- unlisted ability is neither registered nor dispatched.
OsseinCageCommon.combatAbilityIds = {
    [SKULLSTORM] = true,
    [LIFE_DRAIN] = true,
}
OsseinCageCommon.effectAbilityIds = {
    [HINDERED]         = true,
    [TOXIC_IRE]        = true,
    [CORVID_SWARM]     = true,
    [CURSED_TERRAIN]   = true,
    [DETONATE_SOUL_DB] = true,
}
for id in pairs(CAUSTIC_CARRION) do
    OsseinCageCommon.effectAbilityIds[id] = true
end

local FALL_SKULL    = 2500   -- Skullstorm: empirical
local FALL_DETONATE = 3000   -- Detonate Soul: empirical

-- -- CA bar colour palettes -------------------------------------------------

-- -- Caustic Carrion: colour gradient (6 / 8 / 10 thresholds) --------------
local function carrionColorCode(n)
    if     n >= 10 then return "ff2222"    -- red  -  critical
    elseif n >=  8 then return "ff8800"    -- orange  -  danger
    elseif n >=  6 then return "ffcc00"    -- yellow  -  warning
    else                 return "66cc44"   -- green  -  safe
    end
end

-- -- Public: reset on wipe ---------------------------------------------------
-- Call from every OC boss onWipe so module-level state doesn't bleed into
-- the next pull.  Clears both _carrionStacks and the Toxic Ire debounce.
function OsseinCageCommon.reset()
    _carrionStacks    = 0
    _toxicIreLastMs   = 0
end

-- -- Public: write Caustic Carrion info to panel line 3 --------------------
-- Call from each OC boss's onUpdate in place of alerts:clearRow(3).
function OsseinCageCommon.showCarrionInfo(alerts)
    if _carrionStacks > 0 then
        local col = carrionColorCode(_carrionStacks)
        alerts:setRow(3, Fmt.c(col, Lang.t("oc_carrion_label", _carrionStacks)), nil)
    else
        alerts:clearRow(3)
    end
end

-- -- Combat-event handler ---------------------------------------------------
-- Handles ACTION_RESULT_BEGIN events shared across all OC bosses.
-- Returning true short-circuits the boss combatRoutes lookup.
function OsseinCageCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if not OsseinCageCommon.combatAbilityIds[abilityId] then return false end
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- Skullmancer: Skullstorm (cast bar) -----------------------------------
    if abilityId == SKULLSTORM then
        local dur = CastDur.get(SKULLSTORM, FALL_SKULL)
        CA.melee(abilityId, sourceUnitName or "Skullstorm", dur, Colors.VOID)
        return true
    end

    -- Soul Devourer: Life Drain (player targeted) --------------------------
    if abilityId == LIFE_DRAIN then
        if not IsUnitPlayer(unitTag) then return false end
        alerts:showAction(Lang.t("oc_move_life_drain"))
        CA.alert(nil, Lang.t("oc_life_drain_alert"), 0xCC44FFD9, SOUNDS.NONE, 3000)
        return true
    end

    return false
end

-- -- Effect-changed handler -------------------------------------------------
-- Handles EVENT_EFFECT_CHANGED events shared across all OC bosses.
-- stackCount is passed by the extended CombatHandler.onEffectChanged call.
-- Returning true short-circuits the boss effectRoutes lookup.
function OsseinCageCommon.handleEffect(alerts, changeType, abilityId, unitTag, stackCount)
    if not OsseinCageCommon.effectAbilityIds[abilityId] then return false end
    -- Hindered: tank-swap debuff (tank player only) ------------------------
    -- OSI mechanic icon is deferred; alert fires for the tank instead.
    if abilityId == HINDERED then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType ~= EFFECT_RESULT_FADED then
            local _, _, isTank = GetPlayerRoles()
            if isTank then
                alerts:showAction(Lang.t("oc_swap_hindered"))
                CA.alert(nil, Lang.t("oc_hindered_swap_alert"), 0x4488FFD9, SOUNDS.NONE, 5000)
            end
        end
        return true
    end

    -- Toxic Ire: alert at most once per 10 s (player only) ----------------
    if abilityId == TOXIC_IRE then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType ~= EFFECT_RESULT_FADED then
            local now = GetGameTimeMilliseconds()
            if now - _toxicIreLastMs >= 10000 then
                _toxicIreLastMs = now
                alerts:showAction(Lang.t("oc_toxic_ire"))
                CA.alert(nil, Lang.t("oc_toxic_ire_alert"), 0x44CC44D9, SOUNDS.NONE, 4000)
            end
        end
        return true
    end

    -- Corvid Swarm: purple screen border (player only) --------------------
    if abilityId == CORVID_SWARM then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType == EFFECT_RESULT_FADED then
            CA.border(false, 0, "purple")
        else
            CA.border(true, 8000, "purple")
        end
        return true
    end

    -- Cursed Terrain: green screen border (player only) -------------------
    if abilityId == CURSED_TERRAIN then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType == EFFECT_RESULT_FADED then
            CA.border(false, 0, "green")
        else
            CA.border(true, 8000, "green")
        end
        return true
    end

    -- Detonate Soul: cast bar + alert (debuff on player) ------------------
    if abilityId == DETONATE_SOUL_DB then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType ~= EFFECT_RESULT_FADED then
            local dur = CastDur.get(DETONATE_SOUL_DB, FALL_DETONATE)
            alerts:showAction(Lang.t("oc_detonate_soul"))
            CA.ranged(DETONATE_SOUL_DB, Lang.t("oc_detonate_soul_bar"), dur, Colors.FIRE)
            CA.alert(nil, Lang.t("oc_detonate_soul_bar"), 0xFF4400D9, SOUNDS.NONE, dur)
        end
        return true
    end

    -- Caustic Carrion: stack tracking + colour-graduated info (player only) -
    if CAUSTIC_CARRION[abilityId] then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType == EFFECT_RESULT_FADED then
            _carrionStacks = 0
        else
            -- stackCount is the authoritative value when present; fall back to
            -- incrementing the local counter for events that don't include it.
            _carrionStacks = stackCount or (_carrionStacks + 1)
        end
        -- Immediate info-line update (boss:onUpdate will refresh every 200 ms).
        OsseinCageCommon.showCarrionInfo(alerts)
        -- Flash alert when the count crosses a danger threshold.
        local s = _carrionStacks
        if s == 6 or s == 8 or s == 10 then
            local hex = s >= 10 and 0xFF2222D9 or s >= 8 and 0xFF8800D9 or 0xFFCC00D9
            CA.alert(nil, Lang.t("oc_carrion_alert", s), hex, SOUNDS.NONE, 3000)
        end
        return true
    end

    return false
end

package.loaded["trial.oc.OsseinCageCommon"] = OsseinCageCommon
return OsseinCageCommon
