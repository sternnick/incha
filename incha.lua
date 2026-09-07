-- ADDON_NAME and friends are defined in bootstrap.lua (the first file loaded).

local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

-- External-API gateways: inject real implementations once ESO globals are live.
-- configure() calls live in OnAddOnLoaded (below) where CombatAlerts and OSI
-- are guaranteed to be available.
local ExtCA = require("external-api.CombatAlerts")
local ExtMI = require("external-api.MechanicIcons")
local ExtPI = require("external-api.PositionIcons")

-- Pre-load ui modules at startup so they are never captured as part of a
-- trial's dependency set  -  the panel must outlive any single trial.
require("ui.Panel")
local Menu  = require("ui.Menu")

-- Every trial is resident for the whole session.  incha.txt executes each
-- file at load time and each Factory builds its Trial at file scope, so the
-- boss classes and routing tables are already reachable before this runs;
-- ZoneManager just decides which Trial is enabled for the current zone.
ZoneManager.registerTrial(1196, require("trial.ka.Factory"),  "ka")
ZoneManager.registerTrial(1121, require("trial.ss.Factory"),  "ss")
ZoneManager.registerTrial(1263, require("trial.rg.Factory"),  "rg")
ZoneManager.registerTrial(1344, require("trial.dsr.Factory"), "dsr")
ZoneManager.registerTrial(1000, require("trial.as.Factory"),  "as")
ZoneManager.registerTrial(1051, require("trial.cr.Factory"),  "cr")
ZoneManager.registerTrial(1427, require("trial.se.Factory"),  "se")
ZoneManager.registerTrial(1478, require("trial.lc.Factory"),  "lc")
ZoneManager.registerTrial(1548, require("trial.oc.Factory"),  "oc")

local function OnAddOnLoaded(event, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Settings must come first  -  other systems (Log, UI) read from it.
    Settings.init()

    -- Wire external-API gateways to real ESO globals now that they are live.
    -- CombatAlerts and OSI are optional third-party addons: passing nil here
    -- leaves the gateway configured as a no-op, which is the safe default.
    ExtCA.configure(CombatAlerts)
    ExtMI.configure(OSI)
    ExtPI.configure(OSI)

    Menu.init()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()

    d(ADDON_TAG .. " v" .. ADDON_VERSION .. " loaded  -  " .. ADDON_SLASH .. " for commands")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
