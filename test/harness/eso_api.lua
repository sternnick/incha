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

local EsoApi = {}

-- -- Internal mutable state ------------------------------------------------
local _currentMs = 0
local _zoneId    = 0
local _tracker   = nil  -- UnitTracker; set by test runner before replay

function EsoApi.setCurrentTime(ms) _currentMs = ms end
function EsoApi.setZoneId(id)      _zoneId    = id  end
function EsoApi.setTracker(t)      _tracker   = t   end
function EsoApi.getCurrentTime()   return _currentMs end

-- -- ESO action-result constants -------------------------------------------
-- Values chosen to match ESO's actual enum so log result strings map
-- to the same integers the boss routing tables compare against.
ACTION_RESULT_BEGIN                  = 4
ACTION_RESULT_DIED                   = 38
ACTION_RESULT_EFFECT_FADED           = 5
ACTION_RESULT_EFFECT_GAINED          = 6
ACTION_RESULT_EFFECT_GAINED_DURATION = 7
ACTION_RESULT_INTERRUPT              = 65

-- -- ESO effect-change constants -------------------------------------------
EFFECT_RESULT_GAINED  = 1
EFFECT_RESULT_FADED   = 2
EFFECT_RESULT_UPDATED = 3

-- -- Power-type constants --------------------------------------------------
POWERTYPE_HEALTH  = 0
POWERTYPE_MAGICKA = 1
POWERTYPE_STAMINA = 2

-- -- LFG role constant -----------------------------------------------------
LFG_ROLE_TANK = 1

-- -- Event filter constants ------------------------------------------------
REGISTER_FILTER_POWER_TYPE      = 1
REGISTER_FILTER_UNIT_TAG_PREFIX = 2

-- -- ESO event-code constants (arbitrary unique values used as map keys) ---
EVENT_BOSSES_CHANGED        = 100
EVENT_POWER_UPDATE          = 101
EVENT_PLAYER_COMBAT_STATE   = 102
EVENT_COMBAT_EVENT          = 103
EVENT_EFFECT_CHANGED        = 104
EVENT_ADD_ON_LOADED         = 105
EVENT_PLAYER_ACTIVATED      = 106
EVENT_ZONE_CHANGED          = 107

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

function GetPlayerRoles()
    -- Returns (roles, isHealer, isTank, isDropper).
    if not _tracker then return "", false, false, false end
    return "", false, false, false
end

function GetSelectedLFGRole() return 0 end

function AreUnitsEqual(tagA, tagB)
    if tagA == tagB then return true end
    return false
end

-- -- Map utilities (used by MapUtils module) -------------------------------
function SetMapToPlayerLocation() end
function GetMapPlayerPosition(unitTag) return 0.5, 0.5 end

-- -- Ability info ----------------------------------------------------------
function GetAbilityCastInfo(abilityId) return 2000 end
function GetAbilityName(abilityId)     return "" end
function GetAbilityIcon(abilityId)     return "" end
function GetAbilityDuration(abilityId) return 2000 end

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
-- replaced by the corresponding positional argument.  For Phase 1 the
-- only production use is zo_strformat("<<1>>", name) to normalize a name,
-- so a simple indexed-token replacement covers all real cases.
function zo_strformat(fmt, ...)
    local args = { ... }
    return (fmt:gsub("<<(%d+)>>", function(n)
        return tostring(args[tonumber(n)] or "")
    end))
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
BSCHTKA      = nil

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
        }
    end,
}

-- lib.Log  -  pass-through to print(); level-gated by Log.isEnabled().
package.loaded["lib.Log"] = {
    setEnabled = function(v) end,
    isEnabled  = function()  return false end,
    debug      = function()  end,
    warn       = function()  end,
}

return EsoApi
