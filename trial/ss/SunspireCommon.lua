--- SunspireCommon  -  mechanics shared across all three Sunspire boss arenas.
---
--- These abilities appear regardless of which boss (Lokke/Yolna/Nahvii) is
--- active: boss heavy attacks, cat and 2H-add interrupts, shield charge,
--- dragon breaths, and fire spit.
---
--- Called by CombatHandler.onCombatEvent (boss.common.handle) before route
--- lookup; returning true short-circuits routing  -  same contract as
--- RockgroveCommon and DreadsailCommon.
---
--- Interface:
---   .handle(alerts, result, abilityId, unitTag, sourceUnitName) -> bool
---   handleEffect: not needed (all Sunspire adds use combat events only)
---
--- hitValue unavailability note (old API -> modern):
---   HTS used hitValue for cast-duration timers.  Modern API lacks it; we use
---   GetAbilityCastInfo(abilityId) with a per-ability fallback constant instead.

local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")
local SunspireCommon = {}

-- -- Ability ID sets --------------------------------------------------------
-- Heavy Attacks: all bosses + shared adds (iron servant, 1H&Shield add, cone)
local HA_IDS = {
    [115723] = true,   -- Lokkestiiz HA
    [123026] = true,   -- Lokkestiiz Wing Thrash
    [122124] = true,   -- Yolnahkriin HA
    [121833] = true,   -- Yolnahkriin Wing Thrash
    [121849] = true,   -- Yolnahkriin Wing Thrash (alt)
    [115443] = true,   -- Nahviintaas HA
    [119796] = true,   -- Nahviintaas Wing Thrash
    [121422] = true,   -- Cone-portal HA
    [117071] = true,   -- 1H & Shield add HA
    [119817] = true,   -- Iron Servant Anvil Cracker
}

-- Cat (Senche) jump attacks  -  all three arenas
local BLOCK_IDS = {
    [120890] = true,   -- red cat jump
    [122012] = true,   -- white cat jump
}

-- Dragonbreath types across all three bosses
local BREATH_IDS = {
    [119283] = true,   -- Frost Breath  (Lokke)
    [121723] = true,   -- Fire Breath   (Yolna)
    [121980] = true,   -- Searing Breath (Nahvii)
}

-- Fire Spit -> incoming atronach; value = post-cast travel offset in ms
local SPIT_IDS = {
    [118860] = 900,    -- spit during Lokke/Yolna phases
    [115592] = 700,    -- spit during Nahvii phase
}

local SHIELD_CHARGE = 117075   -- 1H & Shield add charge
local LEAP          = 116836   -- 2H add leap

-- -- Registration set --------------------------------------------------------
-- EventPipeline registers one ability-filtered handler per id here, so the
-- engine rejects everything else before it reaches Lua.  handle() gates on
-- this same table, which keeps the two in step: an unlisted ability is
-- neither registered nor dispatched, so a missing entry can never present as
-- "registered but ignored" or "dispatched but unregistered".
--
-- Built from the id tables above rather than restated, so the sets cannot
-- disagree.  A new single-id mechanic must be added to the explicit list.
local combatAbilityIds = {
    [SHIELD_CHARGE] = true,
    [LEAP]          = true,
}
for _, set in ipairs({ HA_IDS, BLOCK_IDS, BREATH_IDS, SPIT_IDS }) do
    for id in pairs(set) do combatAbilityIds[id] = true end
end
SunspireCommon.combatAbilityIds = combatAbilityIds

-- -- Fallback cast durations (ms) ------------------------------------------
-- Used when GetAbilityCastInfo returns 0 (instant / unknown).
local HA_FALLBACK     = 1400
local BLOCK_FALLBACK  =  800   -- cat / 2H-add jump travel
local BREATH_FALLBACK = 3000
local SPIT_FALLBACK   = 1200
local CHARGE_FALLBACK = 1200


-- -- Public handler ---------------------------------------------------------
-- Called by CombatHandler (boss.common.handle) before the combatRoutes lookup.
-- Returns true if the event was handled (caller returns immediately); false otherwise.
function SunspireCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if not combatAbilityIds[abilityId] then return false end
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- -- Heavy Attack (player-targeted) ---------------------------------
    if HA_IDS[abilityId] then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, HA_FALLBACK)
        alerts:showAction(Lang.t("ss_block_heavy_attack"))
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        return true
    end

    -- -- Cat jump (Block) ----------------------------------------------
    -- HTS delayed the alert by hitValue (jump travel time).  Without that value
    -- we show immediately; the CA bar covers the remaining travel window.
    if BLOCK_IDS[abilityId] then
        local dur = CastDur.get(abilityId, BLOCK_FALLBACK)
        alerts:showAction(Lang.t("ss_block_jump"))
        CA.melee(abilityId, sourceUnitName, dur, Colors.LIGHTNING)
        return true
    end

    -- -- 2H add Leap (Dodge) -------------------------------------------
    if abilityId == LEAP then
        local dur = CastDur.get(LEAP, BLOCK_FALLBACK)
        alerts:showAction(Lang.t("ss_dodge_leap"))
        CA.melee(abilityId, sourceUnitName, dur, Colors.LIGHTNING)
        return true
    end

    -- -- Shield Charge (player-targeted) ------------------------------
    if abilityId == SHIELD_CHARGE then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(SHIELD_CHARGE, CHARGE_FALLBACK)
        alerts:showAction(Lang.t("ss_block_shield_charge"))
        CA.melee(abilityId, sourceUnitName, dur, Colors.ICE)
        return true
    end

    -- -- Dragon Breath (player-targeted) ------------------------------
    if BREATH_IDS[abilityId] then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, BREATH_FALLBACK)
        alerts:showAction(Lang.t("ss_dodge_breath"))
        CA.ranged(abilityId, sourceUnitName, dur, Colors.ICE)
        return true
    end

    -- -- Fire Spit -> atronach incoming (player-targeted) --------------
    -- HTS added a post-cast travel offset (+900 ms / +700 ms) to hitValue.
    -- We replicate that by extending the CA bar beyond the cast time.
    local spitOffset = SPIT_IDS[abilityId]
    if spitOffset then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = CastDur.get(abilityId, SPIT_FALLBACK)
        alerts:showAction(Lang.t("ss_atro_incoming"))
        CA.ranged(abilityId, sourceUnitName, dur + spitOffset, Colors.ORANGE)
        return true
    end

    return false
end

package.loaded["trial.ss.SunspireCommon"] = SunspireCommon
return SunspireCommon
