--- DreadsailCommon  -  trash-add mechanics shared across all three DSR arenas.
---
--- Handles add abilities that appear regardless of which boss is active.
--- Called by CombatHandler.onCombatEvent (boss.common.handle) before route
--- lookup; returning true short-circuits routing  -  same contract as
--- RockgroveCommon and SunspireCommon.
---
--- Interface:
---   .handle(alerts, result, abilityId, unitTag, sourceUnitName) -> bool
---   .handleEffect(alerts, changeType, abilityId, unitTag) -> bool
---
--- Phase DSR-2 abilities:
---   SwashbucklerTargeted  (170523): EFFECT_GAINED -> CastAlertsStart 6 s + "BLOCK!"
---   SwashbucklerAperture  (171004): EFFECT_GAINED -> CastAlertsStart 5 s + "KITE BACK"
---   OverseerCascadingBoot (170188): BEGIN + player -> AlertCast
---   SailRiperStormCell    (169994): BEGIN + player -> AlertCast (donut)
---   HarpyWingSlice        (169991): BEGIN + player -> AlertCast
---   BowBreakerHornStrike  (169869, 169871): BEGIN + player -> AlertCast
---   BowBreakerToxicMucus  (169862): BEGIN + player -> AlertCast
---
--- NOTE: SwashbucklerTargeted and SwashbucklerAperture fire on EFFECT_GAINED,
--- not ACTION_RESULT_BEGIN, so the caller must pass them through the
--- onEffectChanged path as well. The handle() function accepts both
--- result=nil (effect path) and result=ACTION_RESULT_BEGIN (combat path).
---
--- Returns true if the event was consumed (caller should return).

local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")
local DreadsailCommon = {}

-- -- Ability IDs -----------------------------------------------------------
local SWASH_TARGETED  = 170523   -- Swashbuckler: chase target 6 s
local SWASH_APERTURE  = 171004   -- Swashbuckler: dagger kite 5 s
local CASCADE_BOOT    = 170188   -- Overseer: ice kick (player-targeted)
local STORM_CELL      = 169994   -- Sail Riper: stand-in-donut
local WING_SLICE      = 169991   -- Harpy: heavy melee
local HORN_STRIKE_1   = 169869   -- Bow Breaker: frontal charge 1
local HORN_STRIKE_2   = 169871   -- Bow Breaker: frontal charge 2
local TOXIC_MUCUS     = 169862   -- Bow Breaker: ranged spit

-- -- Fallback cast durations -----------------------------------------------
-- -- Registration sets -------------------------------------------------------
-- EventPipeline registers one ability-filtered handler per id here, so the
-- engine rejects everything else before it reaches Lua.  handle() and
-- handleEffect() gate on these same tables, which keeps the two in step: an
-- unlisted ability is neither registered nor dispatched.
DreadsailCommon.combatAbilityIds = {
    [CASCADE_BOOT]  = true,
    [STORM_CELL]    = true,
    [WING_SLICE]    = true,
    [HORN_STRIKE_1] = true,
    [HORN_STRIKE_2] = true,
    [TOXIC_MUCUS]   = true,
}
DreadsailCommon.effectAbilityIds = {
    [SWASH_TARGETED] = true,
    [SWASH_APERTURE] = true,
}

local DUR_MELEE  = 1500
local DUR_RANGED = 2000

-- -- CA colour palettes ----------------------------------------------------
local ACT_BLOCK  = { 6000, "BLOCK!",     0.9, 0.1, 0.1, 0.9, nil }
local ACT_KITE   = { 5000, "KITE BACK!", 0.9, 0.5, 0.0, 0.9, nil }
local ACT_DONUT  = { 2000, "IN DONUT",   0.9, 0.8, 0.0, 0.9, nil }

-- -- Public handler (combat path) -----------------------------------------
-- Called by CombatHandler (boss.common.handle) before the combatRoutes lookup.
-- Handles only ACTION_RESULT_BEGIN events on this path.
-- Returning true short-circuits the route dispatch for this event.
function DreadsailCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if not DreadsailCommon.combatAbilityIds[abilityId] then return false end
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- -- Overseer: Cascading Boot (player-targeted ice kick) ---------------
    if abilityId == CASCADE_BOOT then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, DUR_MELEE)
        CA.melee(abilityId, sourceUnitName, dur, Colors.ICE)
        return true
    end

    -- -- Sail Riper: Storm Cell (player-targeted donut) --------------------
    if abilityId == STORM_CELL then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, DUR_MELEE)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE, ACT_DONUT)
        return true
    end

    -- -- Harpy: Wing Slice (heavy melee) -----------------------------------
    if abilityId == WING_SLICE then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, DUR_MELEE)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        return true
    end

    -- -- Bow Breaker: Horn Strike (frontal charge) -------------------------
    if abilityId == HORN_STRIKE_1 or abilityId == HORN_STRIKE_2 then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, DUR_MELEE)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        return true
    end

    -- -- Bow Breaker: Toxic Mucus (ranged spit) ----------------------------
    if abilityId == TOXIC_MUCUS then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, DUR_RANGED)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        return true
    end

    return false
end

-- -- Effect-change path (Swashbuckler abilities use EFFECT_GAINED) ---------
-- Call from each boss's onEffectChanged with the raw changeType + abilityId.
-- Returns true if consumed.
function DreadsailCommon.handleEffect(alerts, changeType, abilityId, unitTag)
    if not DreadsailCommon.effectAbilityIds[abilityId] then return false end
    -- -- Swashbuckler: Targeted (chase for 6 s) ----------------------------
    if abilityId == SWASH_TARGETED then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.bar(abilityId, "Swashbuckler targets you!",
                6000, 6000, Colors.LIGHTNING, 0.5, ACT_BLOCK)
            PlaySound(SOUNDS.DUEL_START)
        end
        return true
    end

    -- -- Swashbuckler: Aperture (kite daggers for 5 s) ---------------------
    if abilityId == SWASH_APERTURE then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.bar(abilityId, "Swashbuckler daggers",
                5000, 5000, Colors.LIGHTNING, 0.5, ACT_KITE)
            PlaySound(SOUNDS.DUEL_START)
        end
        return true
    end

    return false
end

package.loaded["trial.dsr.DreadsailCommon"] = DreadsailCommon
return DreadsailCommon
