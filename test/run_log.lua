--- test/run_log.lua  -  ESO encounter-log integration test runner (Phase 1)
---
--- Replays every event in an ESO encounter log through the live Incha boss
--- modules and prints every alert the addon would have shown.  No assertions
--- yet  -  Phase 1 proves the code runs without errors on real data.
---
--- Usage:
---   luajit test/run_log.lua  <log_file>  [zone_id]
---
---   log_file  Path to an ESO encounter log (.log).
---   zone_id   Optional: only replay this trial zone (e.g. 1196 for KA).
---             When omitted the first recognised trial zone in the log is used.
---
--- Requirements:
---   LuaJIT 2.x (installed via: winget install DEVCOM.LuaJIT)
---   Run from the repository root:
---     luajit test/run_log.lua "path/to/Encounter.log"

-- -- Resolve the addon root (two levels up from test/) --------------------
local SCRIPT_DIR  = debug.getinfo(1, "S").source:match("@?(.+[\\/])") or "./"
local ADDON_ROOT  = SCRIPT_DIR .. "../"
local HARNESS_DIR = SCRIPT_DIR

-- Make addon modules resolvable via standard require().
-- Both forward- and backslash forms are added for Windows compatibility.
package.path = ADDON_ROOT .. "?.lua;"
            .. ADDON_ROOT .. "?/init.lua;"
            .. HARNESS_DIR .. "?.lua;"
            .. package.path

-- -- Load ESO API stubs (must be first  -  sets all globals) -----------------
local EsoApi     = require("harness.eso_api")
local UnitTracker = require("harness.unit_tracker")
local LogReader  = require("harness.log_reader")

-- Pre-load the English string table so core.Lang resolves boss .name fields
-- (e.g. Lokke.name = Lang.t("boss_lokkestiiz") → "Lokkestiiz").
-- In the real game, incha.txt ensures lang/en.lua is loaded before core/Lang;
-- here we replicate that ordering by requiring it before any trial Factory.
require("lang.en")

-- -- Zone -> trial configuration --------------------------------------------
-- The boss list and its ORDER are read from the real trial/<id>/Factory.lua
-- at run time, not restated here.  BossRegistry assigns ids 1..N from array
-- position, so a restated list that drifted from the Factory would produce a
-- harness that passes while exercising a different configuration than ships.
--
-- factory: module path of the trial Factory (the single source of truth).
-- hints:   log unit-name -> boss key, for trials whose boss classes use
--          location-based detection (no .name field) and therefore cannot be
--          found by BossRegistry:findByName inside the harness, where
--          GetUnitWorldPosition is stubbed to the origin.
local TRIAL_CONFIG = {
    [1196] = {
        id      = "ka",
        factory = "trial.ka.Factory",
        hints   = {
            ["Yandir the Butcher"] = "yandir",
            ["Captain Vrol"]       = "vrol",
            ["Lord Falgravn"]      = "falgravn",
        },
    },
    [1121] = { id = "ss",  factory = "trial.ss.Factory",  hints = {} },
    [1263] = { id = "rg",  factory = "trial.rg.Factory",  hints = {} },
    [1344] = { id = "dsr", factory = "trial.dsr.Factory", hints = {} },
    [1000] = { id = "as",  factory = "trial.as.Factory",  hints = {} },
    [1051] = { id = "cr",  factory = "trial.cr.Factory",  hints = {} },
    [1427] = { id = "se",  factory = "trial.se.Factory",  hints = {} },
    [1478] = { id = "lc",  factory = "trial.lc.Factory",  hints = {} },
    [1548] = { id = "oc",  factory = "trial.oc.Factory",  hints = {} },
}

-- -- Captured alerts -------------------------------------------------------
local capturedAlerts  = {}
local currentMs = 0

local function makeAlertHandlers()
    return {
        action    = function(text)
            table.insert(capturedAlerts, { ms = currentMs, type = "action", text = text })
            print(string.format("[%9dms] ACTION  %s", currentMs, text))
        end,
        header    = function(text)
            table.insert(capturedAlerts, { ms = currentMs, type = "header", text = text })
            print(string.format("[%9dms] HEADER  %s", currentMs, text))
        end,
        -- setRow / clearRow are called by onUpdate display loops, not by
        -- combat/effect handlers, so they are no-ops here but must exist to
        -- prevent method-on-nil errors if a handler ever calls them directly.
        setRow     = function() end,
        clearRow   = function() end,
        hideAction = function() end,
        clear      = function() end,
    }
end

-- -- Helper: inject an active boss directly (bypass ESO event discovery) ---
local function injectBoss(trial, bossClass)
    if trial.activeBoss and trial.activeBoss.onLeave then
        pcall(trial.activeBoss.onLeave, trial.activeBoss, trial.context)
    end

    local instance = bossClass.new()
    trial.activeBoss = instance
    trial.context:setBoss(instance)
    trial.context.inCombat = false

    if instance.onEnter then
        pcall(instance.onEnter, instance, trial.context, trial.alerts)
    end
    trial.bridge.onBossEnter(instance, trial.context)
end

local function clearBoss(trial)
    if trial.activeBoss and trial.activeBoss.onLeave then
        pcall(trial.activeBoss.onLeave, trial.activeBoss, trial.context)
    end
    trial.activeBoss = nil
    trial.context:setBoss(nil)
    trial.bridge.onBossExit()
end

-- -- Build a trial instance with test handlers -----------------------------
local function buildTrial(cfg)
    local Trial         = require("core.Trial")
    local CombatHandler = require("core.CombatHandler")

    -- Single source of truth: require the shipping Factory and read the boss
    -- list (and its order) straight off the Trial it built.  The harness then
    -- constructs its own Trial around the same classes so it can substitute
    -- print-based alert handlers without mutating the shipping instance.
    local ok, factoryTrial = pcall(require, cfg.factory)
    if not ok or not factoryTrial then
        io.stderr:write("[harness] FATAL: could not load " .. cfg.factory
            .. ": " .. tostring(factoryTrial) .. "\n")
        os.exit(1)
    end

    local bossClasses = factoryTrial.registry.bosses
    if #bossClasses == 0 then
        io.stderr:write("[harness] FATAL: " .. cfg.factory
            .. " registered no bosses\n")
        os.exit(1)
    end

    local trial = Trial.create({
        id              = cfg.id,
        zoneId          = cfg.zoneId,
        bosses          = bossClasses,
        -- No bridge  -  falls back to BridgeBase (all no-ops).
        alerts          = makeAlertHandlers(),
        onCombatEvent   = CombatHandler.onCombatEvent,
        onEffectChanged = CombatHandler.onEffectChanged,
    })
    trial.registry.zoneId = cfg.zoneId   -- not set by BossRegistry; read from cfg
    trial.zoneId = cfg.zoneId
    return trial, CombatHandler
end

-- -- Replay loop -----------------------------------------------------------
local function replayTrial(cfg, entries, tracker)
    local trial, CombatHandler = buildTrial(cfg)
    local hints = cfg.hints or {}

    -- Stats
    local stats = {
        combat  = 0,
        effect  = 0,
        alerts  = 0,
        errors  = 0,
        bosses  = 0,
    }

    -- Per-ability coverage tracking.
    -- bossSeen[bossClass] = { combat = {[id]=true}, effect = {[id]=true} }
    -- bossOrder preserves the order bosses were first activated (for report).
    local bossSeen  = {}
    local bossOrder = {}
    local activeClass = nil   -- currently active boss CLASS (not instance)

    -- Wire ESO stubs
    EsoApi.setZoneId(cfg.zoneId)
    EsoApi.setTracker(tracker)

    -- Enable the trial infrastructure (registers no real ESO events because
    -- EVENT_MANAGER is stubbed, but sets up internal state).
    trial.pipeline:enable()

    print(string.format("\n=== Trial: %s (zone %d) ===", cfg.id:upper(), cfg.zoneId))

    for _, e in ipairs(entries) do
        currentMs = e.ms
        EsoApi.setCurrentTime(e.ms)

        local et = e.type

        -- -- Zone bookkeeping --------------------------------------------
        if et == "BEGIN_LOG" then
            -- New log session: reset tracker and boss state.
            tracker:clear()
            clearBoss(trial)
            EsoApi.setZoneId(0)

        elseif et == "ZONE_CHANGED" then
            EsoApi.setZoneId(e.zoneId)
            if e.zoneId ~= cfg.zoneId then
                -- Leaving the trial zone: clear boss state and the unit table.
                if trial.activeBoss then
                    clearBoss(trial)
                end
                tracker:clear()
            end

        -- -- Unit tracking -----------------------------------------------
        elseif et == "UNIT_ADDED" and e.unitId then
            tracker:addUnit(e)

            -- Only try to activate a boss while we're inside the trial zone.
            if e.isBoss and EsoApi.getCurrentTime() > 0 then
                local key = hints[e.name]
                local bossClass

                if key then
                    bossClass = trial.registry:getByKey(key)
                elseif e.name ~= "" then
                    -- Fallback: name-based lookup (for bosses with .name field).
                    bossClass = trial.registry:findByName(e.name)
                end

                -- Boss units not in this trial's registry are skipped silently
                -- (Sea Adder, companion mobs, etc. are boss-flagged adds).
                if bossClass then
                    injectBoss(trial, bossClass)
                    activeClass = bossClass
                    if not bossSeen[bossClass] then
                        bossSeen[bossClass] = { combat = {}, effect = {} }
                        bossOrder[#bossOrder + 1] = bossClass
                    end
                    stats.bosses = stats.bosses + 1
                    print(string.format("[%9dms] BOSS    %s activated (key=%s)",
                        e.ms, e.name, bossClass.key or "?"))
                end
            end

        elseif et == "UNIT_REMOVED" and e.unitId then
            local info = tracker:getById(e.unitId)
            if info and info.isBoss and trial.activeBoss then
                -- If the removed unit is the currently active boss, clear it.
                local activeKey = trial.activeBoss and
                    (getmetatable(trial.activeBoss) or trial.activeBoss).key
                local removedClass = trial.registry:getByKey(
                    info.isBoss and (hints[info.name] or ""))
                if removedClass and removedClass.key == activeKey then
                    clearBoss(trial)
                    activeClass = nil
                    print(string.format("[%9dms] BOSS    %s removed", e.ms, info.name))
                end
            end
            tracker:removeUnit(e.unitId)

        -- -- Combat events -----------------------------------------------
        elseif et == "COMBAT_EVENT" and trial.activeBoss then
            if e.abilityId then
                -- Update source unit health in tracker (for GetUnitPower stubs).
                if e.sourceUnitId and e.srcHealthMax > 0 then
                    tracker:updateHealth(e.sourceUnitId, e.srcHealthCur, e.srcHealthMax)
                end

                -- Resolve unit tags from the tracker.
                local srcTag  = tracker:tagById(e.sourceUnitId)
                local srcName = tracker:nameById(e.sourceUnitId)
                local tgtTag  = tracker:tagById(e.targetUnitId)
                local tgtName = tracker:nameById(e.targetUnitId)

                local alertsBefore = #capturedAlerts
                local ok, err = pcall(
                    CombatHandler.onCombatEvent,
                    trial, EVENT_COMBAT_EVENT,
                    e.result, false, "", "", 0,
                    tgtTag, tgtName,        -- unitTag, unitName (target)
                    srcTag, srcName,        -- sourceUnitTag, sourceUnitName
                    e.sourceUnitId, e.targetUnitId, e.abilityId
                )
                if not ok then
                    stats.errors = stats.errors + 1
                    io.stderr:write(string.format(
                        "[%9dms] ERROR in COMBAT_EVENT abilityId=%s: %s\n",
                        e.ms, tostring(e.abilityId), tostring(err)))
                else
                    stats.combat = stats.combat + 1
                    stats.alerts = stats.alerts + (#capturedAlerts - alertsBefore)
                    if activeClass then
                        bossSeen[activeClass].combat[e.abilityId] = true
                    end
                end
            end

        -- -- Effect events ------------------------------------------------
        elseif et == "EFFECT_CHANGED" and trial.activeBoss then
            if e.abilityId and e.changeType ~= 0 then
                local unitTag  = tracker:tagById(e.unitId)
                local unitName = tracker:nameById(e.unitId)

                local alertsBefore = #capturedAlerts
                local ok, err = pcall(
                    CombatHandler.onEffectChanged,
                    trial, EVENT_EFFECT_CHANGED,
                    e.changeType, 0, "", unitTag,
                    0, 0, e.stackCount, "", 0, 0, 0, 0,
                    unitName, e.unitId, e.abilityId
                )
                if not ok then
                    stats.errors = stats.errors + 1
                    io.stderr:write(string.format(
                        "[%9dms] ERROR in EFFECT_CHANGED abilityId=%s: %s\n",
                        e.ms, tostring(e.abilityId), tostring(err)))
                else
                    stats.effect = stats.effect + 1
                    stats.alerts = stats.alerts + (#capturedAlerts - alertsBefore)
                    if activeClass then
                        bossSeen[activeClass].effect[e.abilityId] = true
                    end
                end
            end
        end
    end

    -- Cleanup
    trial.pipeline:disable()

    -- -- Per-ability coverage report -----------------------------------------
    -- For each boss that appeared, compare every combatRoutes / effectRoutes
    -- entry against the ability IDs that actually fired during that boss's
    -- tenure.  NEVER SEEN entries are the candidates for the F2 / F4 mechanic
    -- gaps review (abilities declared but never wired to a real event in the
    -- log).  A NEVER SEEN result is not necessarily a bug in the boss code:
    -- it may just mean the fixture log does not contain that mechanic.
    local neverSeen = 0
    if #bossOrder > 0 then
        print("\n-- Per-ability coverage -------------------------------------")
        for _, bossClass in ipairs(bossOrder) do
            local seen = bossSeen[bossClass]
            local key  = bossClass.key or "?"
            local missC, missE = 0, 0

            if bossClass.combatRoutes then
                for id in pairs(bossClass.combatRoutes) do
                    if not seen.combat[id] then missC = missC + 1 end
                end
            end
            if bossClass.effectRoutes then
                for id in pairs(bossClass.effectRoutes) do
                    if not seen.effect[id] then missE = missE + 1 end
                end
            end

            local totalC = bossClass.combatRoutes and
                (function() local n=0; for _ in pairs(bossClass.combatRoutes) do n=n+1 end; return n end)() or 0
            local totalE = bossClass.effectRoutes and
                (function() local n=0; for _ in pairs(bossClass.effectRoutes) do n=n+1 end; return n end)() or 0

            print(string.format("  %-16s  combat %d/%d  effect %d/%d",
                key,
                totalC - missC, totalC,
                totalE - missE, totalE))

            if missC + missE > 0 then
                if bossClass.combatRoutes then
                    for id in pairs(bossClass.combatRoutes) do
                        if not seen.combat[id] then
                            print(string.format("    NEVER SEEN  COMBAT  %d", id))
                        end
                    end
                end
                if bossClass.effectRoutes then
                    for id in pairs(bossClass.effectRoutes) do
                        if not seen.effect[id] then
                            print(string.format("    NEVER SEEN  EFFECT  %d", id))
                        end
                    end
                end
            end

            neverSeen = neverSeen + missC + missE
        end
    end
    stats.neverSeen = neverSeen

    return stats
end

-- -- Entry point -----------------------------------------------------------
local function main(args)
    local logPath    = args[1]
    local forceZone  = args[2] and tonumber(args[2])

    if not logPath then
        io.stderr:write("Usage: luajit test/run_log.lua <log_file> [zone_id]\n")
        os.exit(1)
    end

    print("Reading log: " .. logPath)
    local entries, parseErrors = LogReader.readFile(logPath)
    print(string.format("Parsed %d entries (%d parse errors)", #entries, parseErrors))

    -- Collect every zone ID that appears in this log (for diagnostics).
    local zonesInLog = {}
    local zonesSeen  = {}
    for _, e in ipairs(entries) do
        if e.type == "ZONE_CHANGED" and e.zoneId and not zonesSeen[e.zoneId] then
            zonesSeen[e.zoneId] = true
            zonesInLog[#zonesInLog + 1] = e.zoneId
        end
    end

    -- Find the target zone: explicit arg, or first recognised trial zone.
    local targetZone = forceZone
    if not targetZone then
        for _, zid in ipairs(zonesInLog) do
            if TRIAL_CONFIG[zid] then
                targetZone = zid
                break
            end
        end
    end

    if not targetZone then
        local known = "1196 1121 1263 1344 1000 1051 1427 1478 1548"
        local found = #zonesInLog > 0
            and table.concat(zonesInLog, ", ")
            or  "(none)"
        io.stderr:write("No recognised trial zone found in log.\n"
            .. "  Zones in log : " .. found .. "\n"
            .. "  Known zones  : " .. known .. "\n")
        os.exit(1)
    end

    local cfg = TRIAL_CONFIG[targetZone]
    if not cfg then
        -- Explicit zone arg that isn't in config  -  show what's actually in the log.
        local found = #zonesInLog > 0
            and table.concat(zonesInLog, ", ")
            or  "(none)"
        local known = "1196 1121 1263 1344 1000 1051 1427 1478 1548"
        io.stderr:write(string.format(
            "No trial config for zone %d.\n"
            .. "  Zones in log : %s\n"
            .. "  Known zones  : %s\n"
            .. "Tip: run without a zone argument to auto-detect.\n",
            targetZone, found, known))
        os.exit(1)
    end
    cfg.zoneId = targetZone

    print(string.format("Target trial: %s (zone %d)", cfg.id:upper(), targetZone))

    local tracker = UnitTracker.new()
    -- Pre-seed the tracker with zone so isActiveZone() is true from the start.
    EsoApi.setZoneId(targetZone)
    EsoApi.setTracker(tracker)

    local stats = replayTrial(cfg, entries, tracker)

    print(string.format(
        "\n-- Summary --------------------------------------------------\n"
        .. "  COMBAT_EVENT entries processed : %d\n"
        .. "  EFFECT_CHANGED entries processed: %d\n"
        .. "  Bosses activated                : %d\n"
        .. "  Alerts fired                    : %d\n"
        .. "  Handler errors                  : %d\n"
        .. "  Route entries never seen        : %d\n",
        stats.combat, stats.effect, stats.bosses, stats.alerts, stats.errors,
        stats.neverSeen or 0))

    os.exit(stats.errors > 0 and 1 or 0)
end

main(arg)
