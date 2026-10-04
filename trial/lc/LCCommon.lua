--- LCCommon — cross-encounter mechanics shared across all Lucent Citadel arenas.
---
--- Phase 2 (EventDispatcher):
---   Exposes LCCommon.beginCastEntries and LCCommon.effectChangedEntries
---   which each boss merges into its own event buckets.
---
--- Hindered OSI icon: deferred — unit OSI API requires in-game coordinate
--- measurement.  An alert fires for the tank instead.

local AlertTypes = require("core.AlertTypes")
local CA      = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang    = require("core.Lang")
local Colors = require("core.Colors")

local LCCommon = {}

-- ── Ability IDs ────────────────────────────────────────────────────────────
local HINDERED        = 165972   -- tank-swap debuff
local RADIANCE_DEBUFF = 214675   -- red screen border on player
local SOLAR_FLARE     = 222475   -- Dremora Spellcaster cast bar
local CONVEY_INIT_1   = 223028   -- effectRoutes.gained: Arcane Conveyance initial debuff, partner 1 → early tether warning
local CONVEY_INIT_2   = 223029   -- effectRoutes.gained: Arcane Conveyance initial debuff, partner 2 → early tether warning
local WEAKENING_CHARGE = 222613  -- effectRoutes.gained: Weakening Charge debuff on a player → tank-swap-relevant callout

-- ── Fallback cast duration (ms) ───────────────────────────────────────────
local FALL_SOLAR = 2500   -- Solar Flare: empirical

-- ── Handlers ──────────────────────────────────────────────────────────────

local function handleSolarFlare(boss, ctx, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(SOLAR_FLARE, FALL_SOLAR)
    CA.melee(abilityId, sourceUnitName or "Solar Flare", dur, Colors.AMBER)
end

local function handleHindered(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        alerts:showAction(Lang.t("lc_swap_hindered"))
        CA.alert(nil, Lang.t("lc_hindered_alert"), 0x4488FFD9, SOUNDS.NONE, 5000)
    end
end

local function handleRadianceGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 8000, "red")
end

local function handleRadianceFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(false, 0, "red")
end

-- Arcane Conveyance starts ~4s before the real tether (223060) with an
-- initial mark debuff on the two tethered players. Warning at the initial
-- debuff gives the pair 4 extra seconds to separate — CrutchAlerts does the
-- same (zones/trials/LucentCitadel.lua:9,317-318).
local function handleConveyanceInitial(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("lc_conv_tether_soon"))
    CA.alert(nil, Lang.t("lc_conv_tether_soon"), 0xFF4444FF, SOUNDS.NONE, 3000)
end

-- Weakening Charge: debuff on a player that reduces their damage taken
-- contribution for the tether mechanic — Crutch registers it on "group"
-- and alerts everyone (LucentCitadel.lua:92-93,324).
local function handleWeakeningCharge(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("lc_conv_weakening_charge",
        (unitName and unitName ~= "") and unitName or Lang.t("lc_conv_weakening_you")))
end

-- ── Shared entries ────────────────────────────────────────────────────────

LCCommon.beginCastEntries = {
    [SOLAR_FLARE] = { type = AlertTypes.CUSTOM, fn = handleSolarFlare },
}

LCCommon.effectChangedEntries = {
    gained = {
        [HINDERED]        = { type = AlertTypes.CUSTOM, fn = handleHindered },
        [RADIANCE_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleRadianceGained },
        [CONVEY_INIT_1]   = { type = AlertTypes.CUSTOM, fn = handleConveyanceInitial },
        [CONVEY_INIT_2]   = { type = AlertTypes.CUSTOM, fn = handleConveyanceInitial },
        [WEAKENING_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleWeakeningCharge },
    },
    faded = {
        [RADIANCE_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleRadianceFaded },
    },
}

package.loaded["trial.lc.LCCommon"] = LCCommon
return LCCommon
