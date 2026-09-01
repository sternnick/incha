-- ADDON_NAME and friends are defined in bootstrap.lua (the first file loaded).

local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

-- Pre-load ui modules at startup so they are never captured as part of a
-- trial's dependency set  -  the panel must outlive any single trial.
local Panel = require("ui.Panel")
local Menu  = require("ui.Menu")

-- Collect all package.loaded keys whose names begin with `prefix`.
-- Called immediately after requiring a trial's Factory so that every module
-- that Factory pulled in transitively is included in the unload list.
-- Core and UI modules are excluded by the prefix convention ("trial.<id>.").
local function trialModules(prefix)
    local list = {}
    for name in pairs(package.loaded) do
        if name:sub(1, #prefix) == prefix then
            list[#list + 1] = name
        end
    end
    return list
end

ZoneManager.registerTrial(1196, require("trial.ka.Factory"),  "ka",  trialModules("trial.ka."))
ZoneManager.registerTrial(1121, require("trial.ss.Factory"),  "ss",  trialModules("trial.ss."))
ZoneManager.registerTrial(1263, require("trial.rg.Factory"),  "rg",  trialModules("trial.rg."))
ZoneManager.registerTrial(1344, require("trial.dsr.Factory"), "dsr", trialModules("trial.dsr."))
ZoneManager.registerTrial(1000, require("trial.as.Factory"),  "as",  trialModules("trial.as."))
ZoneManager.registerTrial(1051, require("trial.cr.Factory"),  "cr",  trialModules("trial.cr."))
ZoneManager.registerTrial(1427, require("trial.se.Factory"),  "se",  trialModules("trial.se."))
ZoneManager.registerTrial(1478, require("trial.lc.Factory"),  "lc",  trialModules("trial.lc."))
ZoneManager.registerTrial(1548, require("trial.oc.Factory"),  "oc",  trialModules("trial.oc."))

local function OnAddOnLoaded(event, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Settings must come first  -  other systems (Log, UI) read from it.
    Settings.init()
    Menu.init()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()

    d(ADDON_TAG .. " v" .. ADDON_VERSION .. " loaded  -  " .. ADDON_SLASH
      .. " for commands")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
