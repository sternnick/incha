--- test/checks/load-order.lua  -  prove incha.txt is ordered so it can execute.
---
--- manifest.lua proves every file is *listed*. Nothing proved the *order* is
--- executable, and the difference is a shipped-bug class: move lib/Throttle.lua
--- to the last line of incha.txt  -  after core/Trial.lua, which requires it on
--- its line 7  -  and all ten checks still pass, while ESO throws on the first
--- require, because bootstrap.lua's shim errors on any module that has not
--- registered yet:
---
---     require('lib.Throttle'): module not registered. Ensure it appears before
---     its first caller in incha.txt.
---
--- So the invariant this check owns is: if a file calls require() *while it is
--- being loaded*, the module it asks for must already have run, i.e. must sit
--- earlier in the manifest.
---
--- Method: execute each listed file in manifest order in one shared environment
--- (as ESO does), with one substitution  -  our own require(). It records the
--- name and returns an inert stub instead of loading anything. Consequences:
---
---   - no file cascades into loading its dependencies, so nothing needs the
---     real ESO API beyond what test/harness/eso_api.lua already stubs;
---   - only requires that actually execute during load are recorded. A require
---     inside a function body does not run at load time, cannot be broken by
---     manifest order, and is deliberately ignored (22 of the 285 requires in
---     this tree are of that kind);
---   - a stub answers any field access, call, concat or length with itself, so
---     inert dependencies do not turn a clean tree into a wall of errors.
---
--- Usage (from the repository root):
---   luajit test/checks/load-order.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local MANIFEST = "incha.txt"

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

-- -- Parse the manifest (same rules as manifest.lua) -------------------------
local manifestText = read(MANIFEST)
if not manifestText then
    print("cannot read " .. MANIFEST .. "  -  run this from the repository root")
    os.exit(1)
end

local order, rank = {}, {}
for line in manifestText:gmatch("[^\r\n]+") do
    local entry = line:match("^%s*([%w_%-/%.]+%.lua)%s*$")
    if entry then
        entry = entry:gsub("\\", "/")
        if not rank[entry] then
            rank[entry] = #order + 1
            order[#order + 1] = entry
        end
    end
end

-- -- An inert dependency: answers everything with itself ---------------------
local stub
local stubmt = {
    __index    = function() return stub end,
    __call     = function() return stub end,
    __concat   = function() return "" end,
    __tostring = function() return "" end,
    __len      = function() return 0 end,
}
stub = setmetatable({}, stubmt)

-- -- One environment for the whole run, as ESO has one Lua state -------------
local askedFor = {}     -- file -> { module = true }
local currentFile
local function recordRequire(name)
    if type(name) ~= "string" then
        fail("BAD REQUIRE   %s  require(%s) needs a string module name",
             tostring(currentFile), tostring(name))
        return stub
    end
    local by = askedFor[currentFile]
    if by then by[name] = true end
    return stub
end
local sandbox = setmetatable({ require = recordRequire }, { __index = _G })

-- -- Run the manifest --------------------------------------------------------
local deps = 0
for pos, entry in ipairs(order) do
    currentFile = entry
    askedFor[entry] = {}

    local chunk, err = loadfile(entry)
    if not chunk then
        fail("PARSE ERROR   %-34s %s", entry, tostring(err))
    else
        setfenv(chunk, sandbox)
        -- bootstrap.lua defines `function require(name)` as a global, which lands
        -- in this shared environment and would replace our recorder from entry 1
        -- onwards. Re-arm it before every file, so what we record is every require
        -- that executes while a file loads.
        sandbox.require = recordRequire
        local ok, loadErr = pcall(chunk)
        if not ok then
            fail("LOAD ERROR    %-34s %s", entry, tostring(loadErr))
        end
    end
end
currentFile = nil

-- -- Order: every recorded require must point earlier in the manifest --------
local function moduleToFile(name)
    local guess = name:gsub("%.", "/") .. ".lua"
    if rank[guess] ~= nil then return guess end
    return nil
end

local unresolved = 0
for _, entry in ipairs(order) do
    for name in pairs(askedFor[entry]) do
        local dep = moduleToFile(name)
        if dep then
            deps = deps + 1
            if rank[dep] > rank[entry] then
                fail("ORDER VIOLATION  %-30s (%s #%d) requires %s  -  which runs "
                     .. "LATER in %s (#%d)", entry, entry, rank[entry], dep,
                     MANIFEST, rank[dep])
            end
        else
            -- Not a repo module: an ESO library, an optional addon wrapper, or a
            -- typo. Only a typo is actionable, and contracts.lua catches broken
            -- module names by loading the real graph  -  so count, do not fail.
            unresolved = unresolved + 1
        end
    end
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("load-order: clean (%d files, %d load-time dependencies, "
          .. "%d non-repo requires ignored)",
          #order, deps, unresolved))
else
    print(string.format("load-order: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
