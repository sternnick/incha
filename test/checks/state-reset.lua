--- test/checks/state-reset.lua  -  every piece of per-pull state must be reset on wipe.
---
--- Trial keeps the SAME boss instance across a wipe: core/Trial.lua:301-310 calls
--- boss:cancelPending() and then boss:onWipe() and never rebuilds it, because the
--- boss stays active (onEnter is not re-run until the zone or the boss changes).
--- So a field created from stateSchema only returns to its starting value if
--- onWipe touches it - by assigning it, or by calling a method on it such as
--- Timer:clear().
---
--- Two ways a field escapes that, both silent in game:
---
---   - a Timer armed late in the pull keeps its deadline, so :remaining() can still
---     count down a mechanic from the pull that already ended;
---   - a CA cast-bar handle that is not stopped points at a bar from the old pull.
---
--- ('k = nil' in a stateSchema declares nothing at all: Lua drops nil keys from a
--- table constructor, so the pairs() loop in lib/BossBase.lua:42 never sees it.
--- Write `= false` / `= 0` when the field must exist.)
---
--- A reset that lives in a same-file helper called from onWipe (`lokke_cleanup(self)`)
--- counts, and so does an empty alertList via BossBase:cleanupAlertList().
--- Exempt one key by appending `-- statecheck: exempt` to its schema line.
---
--- Usage (from the repository root):
---   luajit test/checks/state-reset.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local MANIFEST = "incha.txt"

-- Fields already known to survive a wipe.  Green on purpose, so the check can gate
-- CI from the day it lands and only fail on NEW gaps.  Delete an entry by clearing
-- the field in that boss's onWipe - or, better, by centralising the reset in
-- BossBase, which is the fix the linked issue proposes.
--
-- The Timer entries are countdowns armed during a pull and never cleared, so they
-- can still render between a wipe and the next pull's first arming event.  The
-- *BarId entries are CA cast-bar handles.
local GRANDFATHERED = {
    ["trial/ka/boss/Falgravn.lua"] = {
        instabilityTimer = "countdown survives the wipe; its zo_callLater IS cancelled",
        bloodBallTimer   = "countdown survives the wipe",
        openGatesTimer   = "countdown survives the wipe",
        torturerTimer    = "countdown survives the wipe",
        showPercentUI    = "re-derived from Settings every onUpdate",
        bHM              = "re-derived from the difficulty the context resolves",
    },
    ["trial/ka/boss/Vrol.lua"] = {
        portalTimer  = "re-armed in onCombatState, so the exposure is the idle gap",
        conduitTimer = "re-armed in onCombatState",
        fogTimer     = "re-armed in onCombatState",
    },
    ["trial/ka/boss/Yandir.lua"] = {
        totemTimer       = "countdown survives the wipe",
        gryphonTimer     = "countdown survives the wipe",
        poisonTotemTimer = "a zo_callLater handle; Trial:cancelPending() covers :after handles centrally",
    },
    ["trial/ss/boss/Lokke.lua"] = {
        iceNext         = "ice-tomb sequencer counters, see the issue",
        tombsClear      = "ice-tomb sequencer state",
        iceDouble       = "ice-tomb sequencer state",
        checkDouble     = "ice-tomb sequencer state",
        tCast           = "ice-tomb event timestamps",
        tArmed          = "ice-tomb event timestamps",
        tFaded          = "ice-tomb event timestamps",
        iGained         = "ice-tomb effect bookkeeping",
        iFaded          = "ice-tomb effect bookkeeping",
        laserBarId      = "CA bar handle",
        laserResetTimer = "zo_callLater handle (cancelPending covers it)",
    },
    ["trial/ss/boss/Nahvii.lua"] = {
        thrashBarId = "CA bar handle (interruptTimer IS cleared)",
    },
    ["trial/ss/boss/Yolna.lua"] = {
        cataBarId = "CA bar handle (both timers ARE cleared)",
    },
}

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local manifestText = read(MANIFEST)
if not manifestText then
    print("cannot read " .. MANIFEST .. "  -  run this from the repository root")
    os.exit(1)
end

-- -- Split a file into top-level function bodies ------------------------------
-- Keys are "Class:name", values are the body text.  Only a `function` in column 0
-- opens a new one, which is the convention every boss file follows.
local function functions(text)
    local out, name, body = {}, nil, {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local cls, fn = line:match("^function%s+([%w_]+)[:%.]([%w_]+)%(")
        if cls then
            if name then out[name] = table.concat(body, "\n") end
            name, body = cls .. ":" .. fn, {}
        elseif name then
            body[#body + 1] = line
        end
    end
    if name then out[name] = table.concat(body, "\n") end
    return out
end

-- -- Resolve a `helper(self)` call to the helper's own body -------------------
local function helperBody(text, helper)
    return text:match("local function " .. helper .. "%s*%([^%)]*%)%s*\n(.-)\nend")
end

local checked, bossFiles = 0, 0
for line in manifestText:gmatch("[^\r\n]+") do
    local entry = line:match("^%s*(trial/[%w_]+/boss/[%w_]+%.lua)%s*$")
    if entry then
        entry = entry:gsub("\\", "/")
        local text = read(entry)
        if text then
            bossFiles = bossFiles + 1
            local clsName, schemaBody = text:match("([%w_]+)%.stateSchema%s*=%s*{(.-)\n}")
            if text:match("[^%w_]stateSchema%s*=%s*{%s*}") then
                clsName, schemaBody = nil, nil    -- `Class.stateSchema = {}`  -  no fields
            end
            if clsName then
                checked = checked + 1
                local fns = functions(text)
                local wipe = fns[clsName .. ":onWipe"]
                if not wipe then
                    fail("NO WIPE       %s declares stateSchema but has no %s:onWipe  -  nothing resets it",
                         entry, clsName)
                else
                    local grandfathered = GRANDFATHERED[entry] or {}

                    -- Pull in the bodies of same-file helpers the wipe delegates to.
                    local scanText = wipe
                    for helper in wipe:gmatch("([%w_]+)%s*%(%s*self%s*%)") do
                        local h = helperBody(text, helper)
                        if h then scanText = scanText .. "\n" .. h end
                    end

                    -- alertList is the CA cast-bar map, emptied centrally by
                    -- BossBase:cleanupAlertList(); calling that on wipe - directly or
                    -- through a helper - IS a reset, even though nothing assigns
                    -- self.alertList.
                    local cleansAlerts = scanText:match("cleanupAlertList") ~= nil

                    -- One key per line, and only at depth 0 inside the schema block: a
                    -- nested table (PRISONERS = function() return { Brekalda = 0 } end)
                    -- is mechanic data, not a field of its own.
                    local depth = 0
                    for schemaLine in schemaBody:gmatch("[^\n]+") do
                        local opens, closes = 0, 0
                        for _ in schemaLine:gmatch("{") do opens = opens + 1 end
                        for _ in schemaLine:gmatch("}") do closes = closes + 1 end
                        if not schemaLine:match("^%s*%-%-") and depth == 0 then
                            local key, val = schemaLine:match("^%s*([%w_]+)%s*=%s*(.-),?%s*$")
                            if key and not val:match("statecheck:%s*exempt")
                               and not (key == "alertList" and cleansAlerts) then
                                -- NIL ENTRY: `= nil` in a table constructor is a no-op;
                                -- pairs() never sees the key.  Flag unconditionally —
                                -- it is always wrong, touched or not.
                                if val == "nil" then
                                    fail("NIL ENTRY     %s  %s.%s = nil is invisible to the pairs() loop in lib/BossBase.lua:42  -  a table constructor cannot declare a nil field",
                                         entry, clsName, key)
                                else
                                    -- "reset" = onWipe (or a helper it calls) mentions the
                                    -- field at all: assigning it, calling a method on it, or
                                    -- clearing it in a loop.
                                    local touched = scanText:match("self%." .. key .. "%W")
                                    if not touched and not grandfathered[key] then
                                        fail("NOT RESET     %s  %s.%s is in stateSchema but %s:onWipe never touches it",
                                             entry, clsName, key, clsName)
                                    end
                                end
                            end
                        end
                        depth = depth + opens - closes
                    end
                end
            end
        end
    end
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("state-reset: clean (%d boss files, %d with a stateSchema)", bossFiles, checked))
else
    print(string.format("state-reset: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
