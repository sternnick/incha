--- test/harness/eso_api.lua
--- ESO global API stubs for running addon code outside the game.
---
--- Load this module FIRST (before any addon module).  It populates the
--- global environment with every ESO constant and function that Incha's
--- boss and core modules reference, then pre-stubs the UI modules that
--- cannot run outside the game (ui.Panel, ui.Menu, core.Settings, lib.Log).
---
--- The test runner updates internal state between events via the setters:
---   EsoApi.setCurrentTime(ms)   -- advance simulated clock
---   EsoApi.setZoneId(id)        -- change the active zone
---   EsoApi.setTracker(t)        -- inject a UnitTracker instance
---   EsoApi.setRoles(dps,heal,t)  -- role returned by GetPlayerRoles
---   EsoApi.setLfgRole(r)         -- role returned by GetSelectedLFGRole
---   EsoApi.setAbilityDuration(id, ms)  -- override one ability duration

local EsoApi = {}

-- -- Addon identity ---------------------------------------------------------
-- Normally set by bootstrap.lua, which the harness does not execute (it also
-- installs the require shim, and the harness uses real file-based require).
-- Trial.create and several boss modules read ADDON_PREFIX at file scope.
ADDON_NAME   = "incha"
ADDON_TITLE  = "Incha"
ADDON_TAG    = "[Incha]"
ADDON_SLASH  = "/incha"
ADDON_SV     = "Incha_SV"
ADDON_PREFIX = "Incha_"
ADDON_LAM    = "InchaSettings"

-- -- Internal mutable state ------------------------------------------------
local _currentMs = 0
local _zoneId    = 0
local _tracker   = nil  -- UnitTracker; set by test runner before replay

function EsoApi.setCurrentTime(ms) _currentMs = ms end
function EsoApi.setZoneId(id)      _zoneId    = id  end
function EsoApi.setTracker(t)      _tracker   = t   end
function EsoApi.getCurrentTime()   return _currentMs end

-- Role of the replaying player.  ESO's GetPlayerRoles returns
-- isDPS, isHeal, isTank, so the three fields map to that order directly.
-- Default is a damage dealer, which is the common case for a replayed log.
local _roles    = { dps = true, heal = false, tank = false }
local _lfgRole  = 0                      -- see LFG_ROLE_* below
local _abilityDur = {}                   -- abilityId -> ms, overrides only

function EsoApi.setRoles(dps, heal, tank)
    _roles.dps, _roles.heal, _roles.tank = dps, heal, tank
end
function EsoApi.setLfgRole(role)              _lfgRole = role end
function EsoApi.setAbilityDuration(id, ms)    _abilityDur[id] = ms end

-- -- ESO action-result constants -------------------------------------------
-- Values chosen to match ESO's actual enum so log result strings map
-- to the same integers the boss routing tables compare against.
ACTION_RESULT_BEGIN                  = 4
ACTION_RESULT_DIED                   = 38
ACTION_RESULT_EFFECT_FADED           = 5
ACTION_RESULT_EFFECT_GAINED          = 6
ACTION_RESULT_EFFECT_GAINED_DURATION = 7
ACTION_RESULT_INTERRUPT              = 65
-- Additional constants needed by EventDispatcher.dispatchCombatEvent.
ACTION_RESULT_DAMAGE                 = 2
ACTION_RESULT_CRITICAL_DAMAGE        = 3
ACTION_RESULT_DODGED                 = 35
ACTION_RESULT_BLOCKED_DAMAGE         = 37
ACTION_RESULT_ABILITY_ON_COOLDOWN    = 17

-- -- ESO effect-change constants -------------------------------------------
EFFECT_RESULT_GAINED  = 1
EFFECT_RESULT_FADED   = 2
EFFECT_RESULT_UPDATED = 3

-- -- Power-type constants --------------------------------------------------
POWERTYPE_HEALTH  = 0
POWERTYPE_MAGICKA = 1
POWERTYPE_STAMINA = 2

-- -- Event filter constants ------------------------------------------------
REGISTER_FILTER_POWER_TYPE      = 1
REGISTER_FILTER_UNIT_TAG_PREFIX = 2
REGISTER_FILTER_ABILITY_ID      = 3
REGISTER_FILTER_COMBAT_RESULT   = 4
REGISTER_FILTER_UNIT_TAG        = 5

-- -- ESO event-code constants (arbitrary unique values used as map keys) ---
EVENT_BOSSES_CHANGED        = 100
EVENT_POWER_UPDATE          = 101
EVENT_PLAYER_COMBAT_STATE   = 102
EVENT_COMBAT_EVENT          = 103
EVENT_EFFECT_CHANGED        = 104
EVENT_ADD_ON_LOADED         = 105
EVENT_PLAYER_ACTIVATED      = 106
EVENT_ZONE_CHANGED          = 107
-- Absorb-shield tracking, registered directly by trial/rg/boss/Xalvakka.lua
-- rather than through EventPipeline.
EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED   = 108
EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED = 109
EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED = 110

ATTRIBUTE_VISUAL_POWER_SHIELDING = 1

-- -- EVENT_MANAGER stub ----------------------------------------------------
EVENT_MANAGER = {
    RegisterForEvent   = function(self, prefix, eventType, handler) end,
    UnregisterForEvent = function(self, prefix, eventType) end,
    AddFilterForEvent  = function(self, prefix, eventType, filter, value) end,
    RegisterForUpdate  = function(self, prefix, interval, handler) end,
    UnregisterForUpdate = function(self, prefix) end,
}

-- -- Time ------------------------------------------------------------------
function GetGameTimeMilliseconds() return _currentMs end

-- -- Zone / position -------------------------------------------------------
function GetUnitZoneIndex(unitTag)  return 1 end
function GetZoneId(zoneIndex)       return _zoneId end

function GetUnitWorldPosition(unitTag)
    -- Returns mapId, x, y, z (local game coords).
    -- Position-based boss detection (Location:contains) uses x,y,z.
    -- Return (0,0,0,0)  -  name-based detection takes over in the harness.
    return 0, 0, 0, 0
end

-- -- Role / ability / sound stubs ------------------------------------------
-- Referenced by boss modules but never stubbed, so every replay that reached
-- one of them threw inside the runner's pcall and was counted as an error
-- instead of as coverage.  Six call sites read `local _, _, isTank`
-- (Bahsei, RockgroveCommon, OsseinCageCommon, LCCommon) and two read
-- `local _, isHeal, isTank` (Lylanar) - both are correct, because the game
-- returns isDPS, isHeal, isTank.

function GetPlayerRoles()
    return _roles.dps, _roles.heal, _roles.tank
end

function GetSelectedLFGRole()
    return _lfgRole
end

-- The numeric values here are placeholders, not the game's enum: nothing in
-- Incha compares them arithmetically (Falgravn only tests
-- GetSelectedLFGRole() == LFG_ROLE_TANK), so what matters is that the stub and
-- the constant both come from this file.  Override with EsoApi.setLfgRole().
LFG_ROLE_NONE   = 0
LFG_ROLE_DPS    = 1
LFG_ROLE_TANK   = 2
LFG_ROLE_HEALER = 3
_lfgRole = LFG_ROLE_NONE

-- Called at *module load* by trial/rg/RockgroveCommon.lua (DODGE_DUR), so it
-- has to exist before any trial module is required.  ESO durations are
-- milliseconds; RockgroveCommon falls back to 650 when this yields <= 0.
function GetAbilityDuration(abilityId)
    return _abilityDur[abilityId] or 1500
end

-- Two tags can name the same unit ("group2" and "pet2" resolve to one log
-- unit id), which is what the real function answers about.  Comparing tags
-- textually would be wrong for exactly the case the boss modules care about.
function AreUnitsEqual(unitTag, secondUnitTag)
    if unitTag == secondUnitTag then return true end
    if not _tracker then return false end
    local a = _tracker:getByTag(unitTag)
    local b = _tracker:getByTag(secondUnitTag)
    if not a or not b then return false end
    return a.id == b.id
end

-- Audibility is not under test; the call sites are what matter.
function PlaySound(soundName) end

-- -- Unit queries ----------------------------------------------------------
function DoesUnitExist(unitTag)
    if not _tracker then return false end
    return _tracker:getByTag(unitTag) ~= nil
end

function GetUnitName(unitTag)
    if not _tracker then return "" end
    local u = _tracker:getByTag(unitTag)
    return u and (u.name or "") or ""
end

function GetUnitDisplayName(unitTag)
    if not _tracker then return "" end
    local u = _tracker:getByTag(unitTag)
    return u and (u.displayName or u.name or "") or ""
end

function GetUnitPower(unitTag, powerType)
    -- Returns (current, max, effectiveMax).
    if not _tracker then return 0, 0, 0 end
    local u = _tracker:getByTag(unitTag)
    if u and u.health then
        return u.health.cur, u.health.max, u.health.max
    end
    return 0, 0, 0
end

function IsUnitInCombat(unitTag)    return false end

function IsUnitPlayer(unitTag)
    if unitTag == "player" then return true end
    return type(unitTag) == "string"
        and unitTag:sub(1, 5) == "group"
        and tonumber(unitTag:sub(6)) ~= nil
end

function GetLocalPlayerGroupUnitTag() return "player" end

-- -- Map utilities (used by MapUtils module) -------------------------------
function SetMapToPlayerLocation() end
function GetMapPlayerPosition(unitTag) return 0.5, 0.5 end

-- -- Ability info ----------------------------------------------------------
-- why: mirrors the official arity (channeled bool, durationValue ms) — a
-- single-return stub hides any code that reads the wrong return position
-- (see core/EventDispatcher.lua onCombatEventFiltered, verified against
-- ESOUIDocumentation.txt via esodecoded.com 2026-09-16).
function GetAbilityCastInfo(abilityId) return false, 2000 end
function GetAbilityName(abilityId)     return "" end
function GetAbilityIcon(abilityId)     return "" end
-- GetAbilityDuration is defined above, alongside the other role/duration
-- stubs, and is settable via EsoApi.setAbilityDuration.

-- -- Deferred calls --------------------------------------------------------
-- zo_callLater returns a handle; Phase 1 does not execute the callback
-- (the callback fires long after the event that schedules it, and the
-- boss guards inside it  -  IsUnitInCombat, poisonTotemId checks  -  would
-- produce misleading output when executed out-of-sequence).
local _nextHandle = 1
function zo_callLater(fn, ms)
    local h = _nextHandle
    _nextHandle = _nextHandle + 1
    return h
end
function zo_removeCallLater(handle) end

-- -- Formatting ------------------------------------------------------------
-- zo_strformat  -  ESO's format-string helper.  Tokens <<1>>..<<N>> are
-- replaced by the corresponding positional argument.  The only production
-- use is zo_strformat("<<1>>", name) to normalize a unit name, so indexed
-- token replacement plus grammar-markup stripping covers all real cases.
--
-- Unit names from GetUnitName can carry ESO's gender / declension markup as
-- a trailing directive: "Kynmarcher^Fx", "Skeevaton^n". The real zo_strformat
-- renders these away; stripping them here keeps the harness faithful, so a
-- test that feeds a marked-up name exercises the same code path the game
-- does. Anchored to the end so it cannot eat a following word.
local function stripGrammarMarkup(s)
    return (s:gsub("%^%a+$", ""))
end

function zo_strformat(fmt, ...)
    local args = { ... }
    local out = fmt:gsub("<<(%d+)>>", function(n)
        return tostring(args[tonumber(n)] or "")
    end)
    return (stripGrammarMarkup(out))
end

function ZO_FormatCountdownTimer(seconds)
    local s = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- -- Sound stubs -----------------------------------------------------------
SOUNDS = setmetatable({}, { __index = function() return 0 end })

-- -- Optional external addons  -  keep nil so guard expressions fire cleanly -
CombatAlerts = nil
OSI          = nil

-- -- ESO debug print -------------------------------------------------------
function d(msg) io.stderr:write("[ESO-d] " .. tostring(msg) .. "\n") end

-- -- ZO_SavedVars stub (used by core.Settings) ----------------------------
ZO_SavedVars = {
    NewAccountWide = function(self, name, version, displayName, defaults)
        -- Return the defaults table directly; Settings.get() will return it.
        local copy = {}
        for k, v in pairs(defaults or {}) do copy[k] = v end
        return copy
    end,
}

-- -- Pre-stub modules that require ESO UI globals -------------------------
-- These are set in package.loaded so require() returns the stub without
-- executing the real file (which references CreateControl, WINDOW_MANAGER, ...).

-- ui.Panel  -  Trial factories access Panel.bridge and Panel.alerts.
-- Provide no-op stubs; run_log.lua overrides the alerts after building the trial.
local _panelBridge = {
    onEnable      = function() end,
    onDisable     = function() end,
    onBossEnter   = function(boss, ctx) end,
    onBossExit    = function() end,
    checkHardmode = function(ctx) end,
}
local _panelAlerts = {
    action     = function(text) end,
    header     = function(text) end,
    info       = function(n, text) end,
    hideAction = function() end,
    clear      = function() end,
}
package.loaded["ui.Panel"] = { bridge = _panelBridge, alerts = _panelAlerts }

-- ui.Menu  -  only init() is called; it is a no-op outside the game.
package.loaded["ui.Menu"] = { init = function() end }

-- core.Settings  -  return all options enabled so boss handlers that read
-- Settings.trial("ka").showPercent etc. get sensible defaults.
package.loaded["core.Settings"] = {
    init  = function() end,
    get   = function() return {} end,
    trial = function(id)
        return {
            enabled          = true,
            showBossUI       = true,
            showPercent      = true,
            portalIconVrol   = true,   -- Vrol portal icon  -  OSI nil so creation is a no-op
            posIconsFalgravn = true,   -- Falgravn nodes    -  OSI nil so creation is a no-op
            posIconsZmaja    = true,   -- Z'Maja Frost/Gale -  OSI nil so creation is a no-op
            -- Per-boss enable gate read by Trial:onBossesChanged; every boss on.
            bosses           = setmetatable({}, { __index = function() return true end }),
        }
    end,
}

-- lib.Log  -  pass-through to print(); level-gated by Log.isEnabled().
package.loaded["lib.Log"] = {
    setEnabled          = function(v) end,
    isEnabled           = function()  return false end,
    debug               = function()  end,
    warn                = function()  end,
    -- always() / print() are the two un-gated channels; surface them on
    -- stderr so a replay that hits an unknown ability or a debug-tool
    -- message is visible rather than a nil-call error.
    always              = function(fmt, ...) io.stderr:write("[Incha][warn] " .. string.format(fmt, ...) .. "\n") end,
    print               = function(fmt, ...) io.stderr:write("[Incha] " .. string.format(fmt, ...) .. "\n") end,
    -- Verbose alert tracing — no-ops in tests.
    setVerbose          = function(v) end,
    isVerbose           = function()  return false end,
    setDispatchContext  = function(id, bucket) end,
    verboseAlert        = function(id, durMs, msg) end,
}

return EsoApi
