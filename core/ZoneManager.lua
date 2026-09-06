local Settings = require("core.Settings")

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
---
--- NOTE ON MEMORY: every trial is resident for the whole session, by
--- construction.  ESO executes each file listed in incha.txt at load time,
--- each Factory builds its Trial at file scope, and the Trial object is held
--- here in trials[zoneId].module so re-entering a zone needs no re-require.
--- That keeps every boss class, routing table and constant table reachable.
--- Reducing it would mean building Trials lazily on zone entry, which the
--- manifest load model does not allow without restructuring the Factories.
--- See decision A2 in docs/decisions/architecture.md.
function ZoneManager.registerTrial(zoneId, trialModule, trialId)
    trials[zoneId] = { module = trialModule, trialId = trialId }
end

local function getPlayerZoneId()
    return GetZoneId(GetUnitZoneIndex("player"))
end

local function disableCurrentTrial()
    if activeTrial and activeTrial.disable then
        activeTrial:disable()
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

function ZoneManager.getActiveZoneId()
    return activeZoneId
end

package.loaded["core.ZoneManager"] = ZoneManager
return ZoneManager
