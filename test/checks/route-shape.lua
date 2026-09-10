--- test/checks/route-shape.lua  -  route-table entries cannot silently stop firing.
--
-- EventPipeline registers events per ability id and CombatHandler decides
-- reachability from the shape of each combatRoutes / effectRoutes entry
-- (test/checks/filters.lua comment).  Four shapes silently break a mechanic
-- and none of them throws in the game:
--
--   1. A NIL DISPATCH TARGET.  A table entry whose .fn went missing (a
--      rename, a require that came back nil) never calls anything.
--
--   2. A DROPPED FILTER KEY.  A table entry with .fn but no .result /
--      .changeType compares `result == nil`, never fires, and reports
--      clean.  Caught live on 2026-09-07: mutating Vrol's fog route to this
--      shape kept a log replay green while its alerts went from fired to
--      silent with zero handler errors.
--
--   3. AN UNDEFINED FILTER CONSTANT.  `result = ACTION_RESULT_BEGN` is a
--      typo that evaluates to nil in Lua - shape 2 by another door.  An
--      entry whose filter is not a number falls into this class.
--
--   4. A NON-NUMERIC TABLE KEY.  The engine filters on the numeric
--      REGISTER_FILTER_ABILITY_ID; a string key registers nothing and
--      dispatches nothing.
--
-- And one drift the replay itself can suffer from, checked here because the
-- replay cannot check itself: the harness's textual log fields are turned
-- into numbers by test/harness/log_reader.lua.  If one of those numbers
-- drifts from the constant the shipping code compares against, routes stop
-- matching IN REPLAY ONLY and every coverage report goes quietly wrong.
--
-- What this check deliberately does NOT do: claim handlers match what ESO
-- really emits. Filter values are validated against the constants defined
-- in the repo's ESO surface model (test/harness/eso_api.lua), not against
-- observed game behaviour. Whether a route fires in a real trial stays a
-- LOG_VERIFICATION / INGAME_VERIFICATION question.
--
-- Usage (from the repository root):
--   luajit test/checks/route-shape.lua
--
-- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local TRIALS = { "ka", "ss", "rg", "dsr", "as", "cr", "se", "lc", "oc" }

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

-- -- 1. Route entry shapes ---------------------------------------------------

local totalBosses, entriesChecked = 0, 0

for _, trialId in ipairs(TRIALS) do
    local ok, trial = pcall(require, "trial." .. trialId .. ".Factory")
    if not ok or not trial or not trial.registry then
        fail("FACTORY LOAD  trial.%s.Factory  %s", trialId, tostring(trial))
    else
        for _, boss in ipairs(trial.registry.bosses) do
            totalBosses = totalBosses + 1
            local where = trialId .. "/" .. tostring(boss.key)

            -- rawget: onDied exists on BossBase and resolves through the
            -- metatable for every class; only a class-level declaration is
            -- a real mechanic source.  An empty route table is as dead as a
            -- missing one, so count entries, not presence.
            local mechanics = rawget(boss, "common") ~= nil
                              or rawget(boss, "onDied") ~= nil
                              or rawget(boss, "onCombatEvent") ~= nil
                              or rawget(boss, "onEffectChanged") ~= nil
                              or (rawget(boss, "combatResults") or {})[1] ~= nil
            if not mechanics then
                for _, kind in ipairs({ "combat", "effect" }) do
                    for _ in pairs(rawget(boss, kind .. "Routes") or {}) do
                        mechanics = true
                        break
                    end
                end
            end
            if not mechanics then
                fail("NO MECHANICS  %s declares no routes, common handler, results filter or fallback - nothing can ever dispatch and a replay of it proves nothing",
                     where)
            end

            for _, kind in ipairs({ "combat", "effect" }) do
                local routes = boss[kind .. "Routes"]
                if routes then
                    local filterKey = kind == "combat" and "result" or "changeType"

                    for id, entry in pairs(routes) do
                        entriesChecked = entriesChecked + 1

                        if type(id) ~= "number" then
                            fail("STRING KEY    %s %sRoutes[%s]  - route keys must be numeric ability ids; a string key never registers",
                                 where, kind, tostring(id))
                        end

                        if type(entry) == "function" then
                            -- plain shape: dispatch calls it unconditionally
                        elseif type(entry) == "table" then
                            if entry.fn == nil then
                                fail("NIL FN        %s %sRoutes[%s]  - table entry has no .fn, nothing is ever called",
                                     where, kind, tostring(id))
                            elseif type(entry.fn) ~= "function" then
                                fail("BAD FN        %s %sRoutes[%s]  .fn is %s",
                                     where, kind, tostring(id), type(entry.fn))
                            end

                            local filter = entry[filterKey]
                            if filter == nil then
                                fail("FILTER KEY    %s %sRoutes[%s]  - .fn present but no .%s; dispatch compares against nil and NEVER fires",
                                     where, kind, tostring(id), filterKey)
                            elseif type(filter) ~= "number" then
                                fail("FILTER CONST  %s %sRoutes[%s]  .%s = %s is not a defined constant (undefined names evaluate to nil in Lua - check the spelling)",
                                     where, kind, tostring(id), filterKey, tostring(filter))
                            end
                        else
                            fail("BAD ENTRY     %s %sRoutes[%s]  entry is %s; dispatch would throw at the call",
                                 where, kind, tostring(id), type(entry))
                        end
                    end
                end
            end
        end
    end
end

-- -- 2. Harness map fidelity -------------------------------------------------
-- log_reader.lua maps the log's textual result words to numbers that must
-- equal the constants the shipping routing tables compare against.  Drift
-- here makes correct routes look dead in every replay.

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local reader = read("test/harness/log_reader.lua")
if not reader then
    fail("READ FAIL     test/harness/log_reader.lua - run from the repository root")
else
    -- map name -> { log word prefix candidates tried against _G constants }
    -- Combat log words (BEGIN, EFFECT_FADED, ...) name the ACTION_RESULT_*
    -- constants verbatim after the prefix; effect words (GAINED, ...) name
    -- EFFECT_RESULT_* the same way.  DIED_XP is an alias handled by value.
    local function checkMap(mapName, prefix, alias)
        local block = reader:match("local " .. mapName .. " = {(.-)\n}")
        if not block then
            fail("MAP PARSE     could not locate the %s table in log_reader.lua - update this check's pattern", mapName)
            return
        end
        local seen = 0
        for name, value in block:gmatch("([%u_]+)%s*=%s*(%d+)") do
            seen = seen + 1
            local const = rawget(_G, prefix .. name) or (alias and alias[name])
            if const == nil then
                fail("MAP NAME      log_reader %s.%s  - no constant %s%s exists",
                     mapName, name, prefix .. name,
                     alias and "" or (" (nor alias for " .. name .. ")"))
            elseif const ~= tonumber(value) then
                fail("MAP DRIFT     log_reader %s.%s = %s but %s = %s  - replayed events would not match shipping filters",
                     mapName, name, value, prefix .. name, tostring(const))
            end
        end
        if seen == 0 then
            fail("MAP PARSE     %s table in log_reader.lua appears empty - pattern stale", mapName)
        end
    end

    checkMap("COMBAT_RESULT", "ACTION_RESULT_",
             { DIED_XP = rawget(_G, "ACTION_RESULT_DIED") })
    checkMap("EFFECT_CHANGE", "EFFECT_RESULT_")
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("route-shape: clean (%d route entries, %d boss classes, harness maps agree)",
          entriesChecked, totalBosses))
else
    print(string.format("route-shape: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
