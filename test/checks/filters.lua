--- test/checks/filters.lua  -  invariants for ability-filtered event registration.
---
--- EventPipeline registers EVENT_COMBAT_EVENT and EVENT_EFFECT_CHANGED per
--- ability id rather than unfiltered, so an ability the engine was not told
--- about never reaches Lua at all.  That makes two properties load-bearing:
---
---   1. DISJOINT SETS.  A boss's routing-table ids and its common module's
---      declared ids must not overlap.  The full dispatcher ran the common
---      handler first and let it short-circuit the routes; the filtered
---      handler relies on at most one of the two claiming any given id, so an
---      overlap would silently change which one wins.
---
---   2. A DECLARED SET EXISTS.  A common module that exposes handle() or
---      handleEffect() must declare the matching ability set, or nothing is
---      registered for it and the whole shared-mechanic path goes dark.
---
---   3. A CATCH-ALL IS REACHABLE.  A boss with an onCombatEvent fallback
---      guards on a combat result rather than an ability id, so it needs
---      boss.combatResults for EventPipeline to give it a registration.
---
--- What this check deliberately does NOT do: probe the handlers to discover
--- which abilities they can claim.  Branches gated on IsUnitPlayer,
--- GetPlayerRoles and similar are unreachable under the offline stubs, so a
--- probe reports far fewer ids than the module really handles and would give
--- false confidence.  The gate at the top of each handler is what ties the
--- declared set to dispatch: an id missing from the set is neither registered
--- NOR dispatched, so the failure mode is a dead branch rather than a
--- silently-dropped event.  Dead branches are what the log-replay coverage
--- pass in test/run_log.lua is for.
---
--- Usage (from the repository root):
---   luajit test/checks/filters.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local TRIALS = { "ka", "ss", "rg", "dsr", "as", "cr", "se", "lc", "oc" }

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

local checkedCommons = {}

for _, id in ipairs(TRIALS) do
    local ok, trial = pcall(require, "trial." .. id .. ".Factory")
    if not ok or not trial then
        fail("LOAD  trial.%s.Factory  %s", id, tostring(trial))
    else
        for _, boss in ipairs(trial.registry.bosses) do
            local common = boss.common
            if common then
                local cIds = common.combatAbilityIds or {}
                local eIds = common.effectAbilityIds or {}

                -- 1. Disjointness against this boss's routing tables.
                for abilityId in pairs(boss.combatRoutes or {}) do
                    if cIds[abilityId] then
                        fail("OVERLAP  %s/%s  combat ability %d is in BOTH the "
                             .. "routing table and the common module's set",
                             id, tostring(boss.key), abilityId)
                    end
                end
                for abilityId in pairs(boss.effectRoutes or {}) do
                    if eIds[abilityId] then
                        fail("OVERLAP  %s/%s  effect ability %d is in BOTH the "
                             .. "routing table and the common module's set",
                             id, tostring(boss.key), abilityId)
                    end
                end

                -- 2. The declared set must actually gate the handler, checked
                --    once per common module rather than once per boss.
                if not checkedCommons[common] then
                    checkedCommons[common] = true

                    if common.handle and next(cIds) == nil then
                        fail("NO SET  %s/%s  common declares handle() but no "
                             .. "combatAbilityIds  -  nothing will be registered",
                             id, tostring(boss.key))
                    end
                    if common.handleEffect and next(eIds) == nil then
                        fail("NO SET  %s/%s  common declares handleEffect() but "
                             .. "no effectAbilityIds", id, tostring(boss.key))
                    end

                end
            end

            -- 3. A boss with a catch-all handler must declare the combat
            --    results it guards on, or it gets no registration at all.
            if boss.onCombatEvent and not boss.combatResults then
                fail("NO RESULTS  %s/%s  declares onCombatEvent but no "
                     .. "combatResults  -  the catch-all can never fire",
                     id, tostring(boss.key))
            end
            if boss.onEffectChanged and next(boss.effectRoutes or {}) == nil then
                fail("NO ROUTES  %s/%s  declares onEffectChanged but no "
                     .. "effectRoutes  -  nothing registers it",
                     id, tostring(boss.key))
            end
        end
    end
end

-- -- 4. No duplicate ability ids inside one routing table --------------------
--
-- This has to be a SOURCE scan, not a runtime one.  A Lua table constructor
-- with the same key twice keeps the last entry and discards the first with no
-- error, so by the time the module is loaded the duplicate is already gone and
-- nothing can observe it.  The result is a handler that was written, reviewed
-- and registered, and simply never runs.
--
-- Same failure mode the string table had: eight shadowed keys shipped before
-- anything looked for them.
--
-- Keys are matched as written (`[SOME_CONSTANT]` or `[123456]`), so two
-- differently-named constants holding the same id are not caught here -
-- registration would still work for both, and the routes check above covers
-- whether an id is claimed twice across boss and common tables.

local ROUTE_TABLES = { "combatRoutes", "effectRoutes", "stateSchema" }

local function bossSourceFiles()
    local files, p = {}, io.popen('find trial -path "*/boss/*.lua" 2>/dev/null')
    if p then
        for l in p:lines() do files[#files + 1] = (l:gsub("%s+$", "")) end
        p:close()
    end
    table.sort(files)
    return files
end

for _, path in ipairs(bossSourceFiles()) do
    local f = io.open(path, "r")
    if f then
        local current, seen, lineNo = nil, nil, 0
        for line in (f:read("*a") .. "\n"):gmatch("([^\n]*)\n") do
            lineNo = lineNo + 1

            if not current then
                for _, name in ipairs(ROUTE_TABLES) do
                    if line:match("%." .. name .. "%s*=%s*{") then
                        current, seen = name, {}
                        break
                    end
                end
            elseif line:match("^}") then
                current = nil
            else
                -- `[KEY] =` for routes, `key =` for stateSchema.
                local key = line:match("^%s*%[%s*([%w_]+)%s*%]%s*=")
                          or line:match("^%s*([%w_]+)%s*=")
                if key then
                    if seen[key] then
                        fail("DUPLICATE  %s:%d  %s already lists %s at line %d  -  "
                             .. "Lua keeps the last, the earlier entry never runs",
                             path, lineNo, current, key, seen[key])
                    else
                        seen[key] = lineNo
                    end
                end
            end
        end
        f:close()
    end
end

if findings == 0 then
    print("filters: clean")
else
    print(string.format("filters: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
