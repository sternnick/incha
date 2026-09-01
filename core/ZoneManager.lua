local Settings     = require("core.Settings")
local ModuleLoader = require("core.ModuleLoader")

local ZoneManager = {}

local trials      = {}
local activeZoneId  = nil
local activeTrial   = nil
local activeEntry   = nil   -- the trials[] entry currently enabled

--- Register a trial module for a zone.
--- @param zoneId      number   ESO zone ID
--- @param trialModule table    Must expose enable() / disable().
--- @param trialId     string   Optional.  When provided, the trial's Settings entry
---                             is checked at zone-enter time; if .enabled == false
---                             the trial stays inactive even while the player is in zone.
--- @param unloadList  table    Optional.  List of package.loaded keys to nil on zone exit
---                             so entries do not persist across the whole session.
---                             The Trial object itself is kept alive in trials[]; only
---                             the cache entries are cleared.  Auto-derived in incha.lua
---                             via the trialModules() helper.
function ZoneManager.registerTrial(zoneId, trialModule, trialId, unloadList)
    trials[zoneId] = { module = trialModule, trialId = trialId, unloadList = unloadList }
end

local function getPlayerZoneId()
    return GetZoneId(GetUnitZoneIndex("player"))
end

local function disableCurrentTrial()
    if activeTrial and activeTrial.disable then
        activeTrial:disable()
    end

    -- Clear package.loaded entries for the outgoing trial.  The Trial object
    -- itself remains alive in trials[zoneId].module so re-entering the zone
    -- works without re-requiring anything at runtime.
    if activeEntry and activeEntry.unloadList then
        ModuleLoader.unload(activeEntry.unloadList)
    end

    activeTrial  = nil
    activeZoneId = nil
    activeEntry  = nil
end

local function enableTrialForZone(zoneId)
    local entry = trials[zoneId]
    if not entry then
        disableCurrentTrial()
        return
    end

    if activeZoneId == zoneId and activeTrial then
        return
    end

    disableCurrentTrial()

    -- Respect the per-trial Settings.enabled flag.  Called at zone-enter time,
    -- after Settings.init() has already run, so Settings.get() is always safe.
    if entry.trialId then
        local sv = Settings.get()
        local tsv = sv and sv.trials[entry.trialId]
        if tsv and tsv.enabled == false then
            return
        end
    end

    activeZoneId = zoneId
    activeEntry  = entry
    activeTrial  = entry.module
    entry.module:enable()
end

function ZoneManager.onZoneChanged()
    enableTrialForZone(getPlayerZoneId())
end

--- Re-evaluate the zone the player is standing in against current settings.
--- Called from the per-trial Enable checkboxes so a toggle takes effect
--- immediately; until now .enabled was only consulted at zone-enter time,
--- which meant the checkbox did nothing until you left and re-entered the
--- trial (or reloaded the UI).
function ZoneManager.refresh()
    local zoneId = getPlayerZoneId()
    local entry  = trials[zoneId]
    if not entry then
        return
    end

    local sv  = Settings.get()
    local tsv = sv and entry.trialId and sv.trials[entry.trialId]
    local wanted = not (tsv and tsv.enabled == false)

    if not wanted and activeTrial == entry.module then
        disableCurrentTrial()
    elseif wanted and activeTrial ~= entry.module then
        enableTrialForZone(zoneId)
    end
end

function ZoneManager.getActiveZoneId()
    return activeZoneId
end

package.loaded["core.ZoneManager"] = ZoneManager
return ZoneManager
