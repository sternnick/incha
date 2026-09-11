-- test/harness/coverage.lua - per-ability route coverage for the log replay.
--
-- Answers the one question the smoke replay could not: after a log runs
-- clean, which declared routes actually fired?  A handler whose ability id
-- is never seen in the log is dead code that looks alive, and "0 handler
-- errors" says nothing either way.  This module is the Priority-1 capability
-- from test/README.md Phase 2 and agents/workflow-code-review.md §9.1.
--
-- HOW IT COUNTS (and why this cannot drift from shipping behaviour):
--
--   dispatched  -  incremented by wrappers placed AROUND the shipping
--                  routing entries (Boss.combatRoutes / .effectRoutes, the
--                  common module's handle / handleEffect, the legacy
--                  onCombatEvent / onEffectChanged / onDied).  The dispatch
--                  decision itself stays 100% in core/CombatHandler.lua:
--                  the counter runs only when the real code calls the real
--                  handler, so a route whose result/change filter never
--                  matches counts as seen-but-not-dispatched, not dispatched.
--                  Nothing here re-implements route lookup or filtering.
--
--   logged      -  incremented by the replay loop for every parsed
--                  COMBAT_EVENT / EFFECT_CHANGED on that ability while a
--                  boss was active, routed or not.  Distinguishes "never
--                  happened in this log" from "happened but never reached a
--                  handler" - the two failures that need opposite fixes.
--
-- Instrumenting a class mutates its route tables in this process only (the
-- replay is a throwaway interpreter).  Wrapping is idempotent per class and
-- per common module so shared modules are never double-counted.
--
-- Known blind spots (reported, not hidden):
--   - legacy catch-alls guard on a RESULT, not an id, so their hits are
--     attributed per abilityId as seen, but an ability they acted on with no
--     id match cannot be attributed; bosses with combatResults are flagged.
--   - zo_callLater does not execute under the harness (eso_api stub), so
--     deferred work inside a handler is invisible to these counts - the
--     handler itself is still counted.

local Coverage = {}

-- class/common module -> true, so wrapping is done once per process.
local seenClasses = setmetatable({}, { __mode = "k" })

local active = nil        -- current boss key (string) or nil
local report = {}         -- bossKey -> { name, logged={}, dispatched={}, kinds={} }
local order  = {}         -- bossKeys in first-activation order

local function bucket(bossKey, name)
    local b = report[bossKey]
    if not b then
        b = { name = name, logged = {}, dispatched = {}, kinds = {} }
        report[bossKey] = b
        order[#order + 1] = bossKey
    end
    return b
end

Coverage.setActive = function(bossKey, name)
    active = bossKey
    if bossKey then bucket(bossKey, name) end
end

--- Log-side counters: what the log contained while `active` was set.
function Coverage.onCombatSeen(abilityId)
    if active and abilityId then
        local b = report[active]
        b.logged[abilityId] = (b.logged[abilityId] or 0) + 1
    end
end
Coverage.onEffectSeen = Coverage.onCombatSeen

--- Dispatch-side counters, driven by the wrappers below.
local function dispatched(abilityId, kind)
    if active and abilityId then
        local b = report[active]
        b.dispatched[abilityId] = (b.dispatched[abilityId] or 0) + 1
        b.kinds[abilityId] = kind
    end
end

-- -- Wrappers ---------------------------------------------------------------
-- Each preserves the exact call convention of the entry it replaces, so the
-- handler cannot tell it is being watched.
--
-- Arg shapes (fixed by core/CombatHandler.lua dispatchCombatEntry /
-- dispatchEffectEntry, after the shared boss/context/alerts prefix):
--   plain route entry   (result | changeType, abilityId, ...)   -> id is arg 2
--   shorthand entry.fn  (abilityId, ...)                        -> id is arg 1
-- Args pass through as (a1, a2, ...): naming the two leading args still
-- forwards every trailing arg and its exact count, and table.pack/unpack
-- cannot be used because ESO's Lua 5.1 and LuaJIT 2.0 lack them.

local function wrapRouteFn(fn, idArg, kind)
    return function(boss, context, alerts, a1, a2, ...)
        dispatched(idArg == 1 and a1 or a2, kind)
        return fn(boss, context, alerts, a1, a2, ...)
    end
end

local function wrapLegacyCombat(fn)
    -- boss:onCombatEvent(ctx, alerts, result, abilityId, ...)
    return function(boss, context, alerts, result, abilityId, ...)
        dispatched(abilityId, "legacy")
        return fn(boss, context, alerts, result, abilityId, ...)
    end
end

local function wrapLegacyEffect(fn)
    -- boss:onEffectChanged(ctx, alerts, changeType, abilityId, ...)
    return function(boss, context, alerts, changeType, abilityId, ...)
        dispatched(abilityId, "legacy")
        return fn(boss, context, alerts, changeType, abilityId, ...)
    end
end

local function wrapDied(fn)
    return function(boss, context, alerts, ...)
        dispatched(nil, "died")
        return fn(boss, context, alerts, ...)
    end
end

local function wrapCommonHandle(fn)
    -- handle(alerts, result, abilityId, unitTag, sourceUnitName)
    return function(alerts, result, abilityId, unitTag, sourceUnitName)
        local handled = fn(alerts, result, abilityId, unitTag, sourceUnitName)
        if handled then dispatched(abilityId, "common") end
        return handled
    end
end

local function wrapCommonEffect(fn)
    -- handleEffect(alerts, changeType, abilityId, unitTag, stackCount)
    return function(alerts, changeType, abilityId, unitTag, stackCount)
        local handled = fn(alerts, changeType, abilityId, unitTag, stackCount)
        if handled then dispatched(abilityId, "commonEffect") end
        return handled
    end
end

--- Instrument one boss CLASS (not an instance: instances read the tables
--- through the metatable, so wrapping the class observes every instance).
function Coverage.instrument(class)
    if not class or seenClasses[class] then return end
    seenClasses[class] = true

    for _, kind in ipairs({ "combat", "effect" }) do
        local routes = class[kind .. "Routes"]
        if routes then
            for id, entry in pairs(routes) do
                if type(entry) == "function" then
                    -- Plain shape: fn receives (result|changeType, abilityId, ...)
                    routes[id] = wrapRouteFn(entry, 2, kind)
                elseif type(entry) == "table" and type(entry.fn) == "function"
                       and not entry.__inchaCovered then
                    -- Shorthand: entry.fn runs only when the filter matches,
                    -- and receives abilityId first.
                    entry.fn = wrapRouteFn(entry.fn, 1, kind)
                    entry.__inchaCovered = true
                end
            end
        end
    end

    if type(class.onCombatEvent) == "function" then
        class.onCombatEvent = wrapLegacyCombat(class.onCombatEvent)
    end
    if type(class.onEffectChanged) == "function" then
        class.onEffectChanged = wrapLegacyEffect(class.onEffectChanged)
    end
    if type(class.onDied) == "function" then
        class.onDied = wrapDied(class.onDied)
    end

    local common = class.common
    if common and not seenClasses[common] then
        seenClasses[common] = true
        if type(common.handle) == "function" then
            common.handle = wrapCommonHandle(common.handle)
        end
        if type(common.handleEffect) == "function" then
            common.handleEffect = wrapCommonEffect(common.handleEffect)
        end
    end
end

-- -- Report -----------------------------------------------------------------

local function sortedIds(t)
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- Aggregate counters from the most recent print(), exposed via Coverage.totals().
local totals = { routes = 0, neverLogged = 0, loggedNeverDispatched = 0 }

--- Print the coverage block.  `expectedByBoss` maps bossKey -> { [id] = kind }
--- built from the shipping routing tables so an id that was never logged
--- still appears (that is the case this whole module exists for).
function Coverage.print(expectedByBoss)
    -- Nothing activated means nothing attributable: stay quiet, and let the
    -- caller report the never-activated bosses instead.
    if #order == 0 then return end

    print("\n-- Route coverage ------------------------------------------")

    totals = { routes = 0, neverLogged = 0, loggedNeverDispatched = 0 }

    for _, key in ipairs(order) do
        local b = report[key]
        local exp = expectedByBoss[key] or {}
        local ids = sortedIds(exp)

        -- Any id logged without being declared must also show up.
        for id in pairs(b.logged) do
            if not exp[id] then ids[#ids + 1] = id; exp[id] = "unrouted" end
        end
        table.sort(ids)

        print(string.format("  %s  [%s]", b.name or key, key))

        if #ids == 0 then
            print("    (no routes declared)")
        end

        for _, id in ipairs(ids) do
            local logged      = b.logged[id] or 0
            local dispatchedN = b.dispatched[id] or 0
            local kind        = exp[id] or b.kinds[id] or "?"
            local verdict
            if dispatchedN > 0 then
                verdict = ""
            elseif logged > 0 then
                verdict = "  <- LOGGED, NEVER DISPATCHED"
                totals.loggedNeverDispatched = totals.loggedNeverDispatched + 1
            else
                verdict = "  <- NEVER LOGGED"
                totals.neverLogged = totals.neverLogged + 1
            end
            totals.routes = totals.routes + 1
            print(string.format("    %-8s %-14s logged %4d  dispatched %4d%s",
                tostring(id), kind, logged, dispatchedN, verdict))
        end
    end

    print(string.format(
        "  routes=%d  never logged=%d  logged-never-dispatched=%d",
        totals.routes, totals.neverLogged, totals.loggedNeverDispatched))
end

--- Union of what the shipping code would have registered for a boss, as
--- { [abilityId] = kind }, read from the class tables themselves.
function Coverage.expectedFor(bossClass)
    local out = {}
    local function add(id, kind)
        -- An id may legitimately appear in both route tables (separate combat
        -- and effect registrations in game); report it as both, never drop one.
        if out[id] and out[id] ~= kind then
            out[id] = "both"
        else
            out[id] = kind
        end
    end
    for id in pairs(bossClass.combatRoutes or {}) do add(id, "combat") end
    for id in pairs(bossClass.effectRoutes or {}) do add(id, "effect") end
    local c = bossClass.common
    if c then
        for id in pairs(c.combatAbilityIds or {}) do add(id, "common") end
        for id in pairs(c.effectAbilityIds or {}) do add(id, "commonEffect") end
    end
    return out
end

--- Aggregate counters from the last print(), for the caller's summary block.
function Coverage.totals()
    return totals
end

--- Coverage for bosses that were never activated cannot be attributed to a
--- log window; the report lists only activated bosses, and this says so.
function Coverage.missingActivation(activatedKeys, allBossClasses)
    local missing = {}
    for _, cls in ipairs(allBossClasses) do
        if not activatedKeys[cls.key] then
            missing[#missing + 1] = cls.key
        end
    end
    return missing
end

return Coverage
