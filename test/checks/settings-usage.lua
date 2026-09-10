--- test/checks/settings-usage.lua  -  every setting must actually do something.
---
--- A settings entry is three pieces of code that can drift apart on their own:
--- a default in core/Settings.lua, a checkbox in ui/Menu.lua, and a reader in a
--- boss or ui module.  The first two are visible in the settings panel, the
--- third is not  -  so when the reader is deleted (or never written) the player
--- still sees a working checkbox that changes nothing, and nothing anywhere
--- fails.  That is the worst kind of dead code: it is *advertised*.
---
--- Usage (from the repository root):
---   luajit test/checks/settings-usage.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local SETTINGS = "core/Settings.lua"
local MANIFEST = "incha.txt"

-- Files that define or expose settings and are therefore not "readers".
local NOT_A_READER = {
    ["core/Settings.lua"] = true,   -- declares the schema
    ["ui/Menu.lua"]       = true,   -- draws the checkboxes
}

-- Known findings, kept green on purpose so this check can gate CI from the day
-- it lands and only fail on NEW dead settings.  Remove an entry by fixing it.
local GRANDFATHERED = {
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

local settingsText = read(SETTINGS)
if not settingsText then
    print("cannot read " .. SETTINGS .. "  -  run this from the repository root")
    os.exit(1)
end

-- -- Collect the per-trial keys ----------------------------------------------
-- Track brace depth from the opening of the trials block:
--
--   trials = {           depth 1 on entry
--       ka = {           depth 2 inside each trial sub-table
--           enabled = true,
--           bosses = {   depth 3 inside the per-boss sub-table (NOT collected)
--               yandir = true,
--           },
--       },
--   }
--
-- A name is a setting when it appears at depth == 2 (direct trial key), or on
-- the trial ID line itself (depth 1, same-line assignments beside the id).
-- Boss name keys nested inside bosses = { } are at depth 3 and are read
-- dynamically in Trial.lua via bosses[bossClass.key], so they are not
-- collected here — only the bosses container key itself is.
local keys, seen = {}, {}
local inTrials, depth = false, 0
for line in settingsText:gmatch("[^\n]+") do
    if not inTrials then
        if line:match("^%s*trials%s*=%s*{") then
            inTrials, depth = true, 1
        end
    else
        local before = depth
        local opens, closes = 0, 0
        for _ in line:gmatch("{") do opens = opens + 1 end
        for _ in line:gmatch("}") do closes = closes + 1 end
        if not line:match("^%s*%-%-") then
            local row = line:match("^%s*(%w+)%s*=%s*{")
            for name in line:gmatch("([%w_]+)%s*=") do
                local isSetting = before == 2 or (before == 1 and row and name ~= row)
                if isSetting and not seen[name] then
                    seen[name] = true
                    keys[#keys + 1] = name
                end
            end
        end
        depth = depth + opens - closes
        if depth <= 0 then inTrials = false end
    end
end
if #keys == 0 then
    print("no per-trial keys found in " .. SETTINGS)
    os.exit(1)
end

-- -- Read every addon source file once ---------------------------------------
local sources = {}
local fileCount = 0
for line in (read(MANIFEST) or ""):gmatch("[^\r\n]+") do
    local entry = line:match("^%s*([%w_%-/%.]+%.lua)%s*$")
    if entry then
        entry = entry:gsub("\\", "/")
        if not NOT_A_READER[entry] then
            local body = read(entry)
            if body then
                sources[#sources + 1] = body
                fileCount = fileCount + 1
            end
        end
    end
end

-- -- A key is live if some other file mentions it as a field -----------------
table.sort(keys)
for _, key in ipairs(keys) do
    local readers = 0
    local pattern = "[%.:]" .. key .. "%W"
    for _, body in ipairs(sources) do
        for _ in body:gmatch(pattern) do
            readers = readers + 1
        end
    end
    if readers == 0 then
        if GRANDFATHERED[key] then
            print(string.format("KNOWN         trials.*.%s has no reader (grandfathered, see the issue)", key))
        else
            fail("DEAD SETTING  trials.*.%s is declared in %s and drawn in ui/Menu.lua but no module reads it",
                 key, SETTINGS)
        end
    end
end

-- -- Cross-check: per-boss keys vs boss module declarations -------------------
-- The brace-depth collector above stops at depth 2, so the 25 per-boss toggles
-- at trials.<trial>.bosses.<name> are invisible to it.  A typo on either side
-- (settings subkey renamed, or `.key = "..."` misspelled in a boss module)
-- silently makes that checkbox toggle nothing, because Trial.lua looks bosses up
-- by bossClass.key at runtime.  This section closes that gap: every bosses
-- subkey must be declared by some boss module and vice versa.
--
-- Scope: the bosses sub-table of each trial (same "bosses = {" anchor the
-- collector above already recognises) to the matching close brace; and one
-- `Class.key = "<literal>"` per file under trial/*/boss/*.
local bossKeys = {}       -- trial -> { name = true }
local declared = {}       -- key literal -> { file = name }
do
    local inTrialsBlock, inBosses, trial, bossesDepth = false, false, nil, 0
    for line in settingsText:gmatch("[^\r\n]+") do
        if not inTrialsBlock then
            if line:match("^%s*trials%s*=%s*{") then inTrialsBlock = true end
        elseif not inBosses then
            -- Check the bosses anchor FIRST: a `bosses = {` line also matches
            -- the bare `name = {` trial-id pattern, and recording it as a
            -- trial id would corrupt the reported label.
            if line:match("^%s*bosses%s*=%s*{") then
                inBosses, bossesDepth = true, 1
                bossKeys[trial or "?"] = bossKeys[trial or "?"] or {}
            else
                local t = line:match("^%s*(%a%w*)%s*=%s*{")
                if t then trial = t end
                if trial and line:match("^%s*}%s*,?%s*$") then
                    trial = nil
                end
            end
        else
            local opens, closes = 0, 0
            for _ in line:gmatch("{") do opens = opens + 1 end
            for _ in line:gmatch("}") do closes = closes + 1 end
            local name = (bossesDepth == 1 and not line:match("^%s*%-%-"))
                and line:match("^%s*([%a_][%w_]*)%s*=") or nil
            if name then bossKeys[trial or "?"][name] = true end
            bossesDepth = bossesDepth + opens - closes
            if bossesDepth <= 0 then
                inBosses, trial = false, nil
            end
        end
    end
end

-- Enumerate boss modules through the manifest (same file list the reader scan
-- uses), not a shell glob, so this check honours incha.txt exactly.
for line in (read(MANIFEST) or ""):gmatch("[^\r\n]+") do
    local entry = line:match("^%s*(trial/[%w_%-/%.]+/boss/[%w_]+%.lua)%s*$")
    if entry then
        local body = read(entry)
        local k = body and body:match("%.%s*key%s*=%s*\"([^\"]+)\"")
        if not k then
            fail("MISSING KEY    %s declares no `Class.key = \"...\"` literal", entry)
        elseif declared[k] then
            fail("DUPLICATE KEY  %s redeclares boss key %q already declared by %s",
                 entry, k, declared[k])
        else
            declared[k] = entry
        end
    end
end

local bossKeyCount = 0
for trial, names in pairs(bossKeys) do
    for name in pairs(names) do
        bossKeyCount = bossKeyCount + 1
        if not declared[name] then
            fail("NO BOSS FILE   trials.%s.bosses.%s in %s has no boss module declaring key %q",
                 trial, name, SETTINGS, name)
        end
    end
end
for k, file in pairs(declared) do
    local inSettings = false
    for _, names in pairs(bossKeys) do
        if names[k] then inSettings = true end
    end
    if not inSettings then
        fail("NO SETTINGS    %s declares boss key %q with no trials.*.bosses entry in %s",
             file, k, SETTINGS)
    end
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("settings-usage: clean (%d keys checked against %d source files, %d boss keys cross-checked)",
          #keys, fileCount, bossKeyCount))
else
    print(string.format("settings-usage: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
