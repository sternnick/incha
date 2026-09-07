--- test/checks/globals.lua  -  static scan for unintended global access.
---
--- ESO addons share one Lua environment with every other addon the player has
--- installed, so an accidental global write is a cross-addon bug and an
--- accidental global read is a silent nil.  Both are invisible until the line
--- happens to run mid-fight.
---
--- This catches the class directly:  a missing `local X = require(...)` shows
--- up as a global READ of a name that is not part of the ESO API.
---
--- Usage (from the repository root):
---   luajit test/checks/globals.lua
---
--- Exit code 0 = clean, 1 = at least one finding.
---
--- Requires `luajit` on PATH  -  the scan reads the bytecode listing
--- (`luajit -bl`) rather than parsing Lua source with regexes.

--- Every file the addon actually ships, read from the manifest rather than from
--- a directory list.  A hardcoded list is a silent allow-list: when the DI
--- refactor added external-api/ (core/Fmt.lua's companion modules) they simply
--- were never scanned, and a directory list has no way to notice.  Anything in
--- incha.txt is scanned, including files at the repository root.
---
--- Bootstrap is exempt, and only bootstrap: its whole job is to define the
--- ADDON_* identity globals that every other module reads, so nine global
--- writes there are the design, not a leak.  A manifest entry that is missing
--- or unreadable is reported, because a file nothing analysed is the same blind
--- spot this change is about.
local EXEMPT = {
    ["bootstrap.lua"] = "defines the ADDON_* identity globals on purpose",
}

-- Names the addon is allowed to read from the global environment: the ESO API
-- surface, the ADDON_* identity globals set by bootstrap.lua, the optional
-- third-party addons, and the Lua 5.1 standard library.
--
-- Constant families: a plain prefix match is enough, they are SHOUT_CASE.
local ALLOW_PREFIX = {
    "ACTION_RESULT_", "EFFECT_RESULT_", "EVENT_", "REGISTER_FILTER_",
    "POWERTYPE_", "ATTRIBUTE_VISUAL_", "LFG_ROLE_", "CT_", "TEXT_ALIGN_",
    "ADDON_", "zo_", "ZO_",
}

-- ESO API function families.  These need the NEXT character to be uppercase,
-- because a bare prefix match is far too loose: "Set" alone would silently
-- allow "Settings", which is exactly the missing-require bug this check
-- exists to catch (ZmajaEncounter read a nil global `Settings` for months).
--   SetMapToPlayerLocation -> "M" -> ESO API, allowed
--   Settings               -> "t" -> not ESO, reported
local ALLOW_VERB = { "Get", "Is", "Does", "Are", "Set", "Play", "Create" }

local ALLOW_EXACT = {}
for _, name in ipairs({
    -- ESO singletons and constants
    "EVENT_MANAGER", "SCENE_MANAGER", "WINDOW_MANAGER", "SLASH_COMMANDS",
    "GuiRoot", "SOUNDS", "TOPLEFT", "TOPRIGHT", "BOTTOM", "BOTTOMLEFT",
    "BOTTOMRIGHT", "TOP", "LEFT", "RIGHT", "CENTER", "d",
    -- Optional third-party addons  -  every call site must nil-guard these
    "OSI", "CombatAlerts", "LibAddonMenu2", "BSCHTKA",
    -- Lua 5.1 standard library
    "require", "package", "assert", "error", "pairs", "ipairs", "next",
    "select", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal",
    "pcall", "xpcall", "type", "tostring", "tonumber", "unpack", "print",
    "string", "table", "math", "os", "io", "debug", "coroutine", "_G",
}) do ALLOW_EXACT[name] = true end

local function isAllowed(name)
    if ALLOW_EXACT[name] then return true end
    for _, p in ipairs(ALLOW_PREFIX) do
        if name:sub(1, #p) == p then return true end
    end
    for _, p in ipairs(ALLOW_VERB) do
        if name:sub(1, #p) == p then
            local nextChar = name:sub(#p + 1, #p + 1)
            if nextChar:match("%u") then return true end
        end
    end
    return false
end

--- Every file the addon ships, straight from incha.txt.
---
--- Paths are normalised (a leading "./" dropped) and de-duplicated before
--- scanning: the summary counts files, so a manifest entry listed twice would
--- report a file twice and double-count any finding in it.  Matching the
--- exemption on the base name rather than the exact manifest text keeps
--- "./bootstrap.lua" from silently losing its exemption and failing with nine
--- global writes  -  a wrong answer, not a missing one.
---
--- What this does NOT scan is a .lua that sits in a shipped directory but is
--- missing from incha.txt.  That case is covered by manifest.lua in the same CI
--- job (verified: "NOT LOADED  lib/ZzzUnlisted.lua exists but is not listed in
--- incha.txt", exit 1), which is the reason it is safe to follow the manifest
--- here instead of walking the tree as well.
local function sourceFiles()
    local seen, files, skipped = {}, {}, {}
    local fh = io.open("incha.txt", "r")
    if not fh then return nil, "incha.txt not readable" end
    for line in fh:lines() do
        local path = line:match("^%s*([%w_%-%./]+%.lua)%s*$")
        if path then
            path = path:gsub("^%./", "")
            if not seen[path] then
                seen[path] = true
                local base = path:match("([^/]+)$")
                if EXEMPT[path] or EXEMPT[base] then
                    skipped[#skipped + 1] = path
                else
                    files[#files + 1] = path
                end
            end
        end
    end
    fh:close()
    table.sort(files)
    return files, skipped
end

--- Read GGET (global read) and GSET (global write) operands out of the
--- LuaJIT bytecode listing for one file.  Returns an error string when no
--- listing was produced: a scan that saw no instructions has seen nothing,
--- which is not the same as having seen nothing wrong.
local function scan(path)
    local reads, writes = {}, {}
    local p = io.popen('luajit -bl "' .. path .. '" 2>&1')
    if not p then return reads, writes, "could not run luajit -bl" end

    local sawListing, firstError = false, nil
    for line in p:lines() do
        if not sawListing and line:find("BYTECODE", 1, true) then
            sawListing = true
        end
        if not firstError and line:find("luajit:", 1, true) then
            firstError = line
        end
        local op, name = line:match("(GGET).-;%s*\"([^\"]+)\"")
        if not op then op, name = line:match("(GSET).-;%s*\"([^\"]+)\"") end
        if op == "GGET" then reads[name] = true
        elseif op == "GSET" then writes[name] = true end
    end

    local _, code, reason = p:close()
    if not sawListing then
        return reads, writes, firstError
            or string.format("no bytecode listing (close: %s, %s)",
                             tostring(code), tostring(reason))
    end
    return reads, writes
end

local listed, skippedOrError = sourceFiles()
if not listed then
    print(string.format("NO MANIFEST   %s  -  nothing could be analysed", tostring(skippedOrError)))
    print("globals: 1 finding(s)")
    os.exit(1)
end

if skippedOrError then
    for _, path in ipairs(skippedOrError) do
        print(string.format("EXEMPT        %s  %s", path, EXEMPT[path]))
    end
end

local findings, files = 0, 0
for _, path in ipairs(listed) do
    local reads, writes, err = scan(path)
    files = files + 1

    if err then
        -- The file was not analysed.  Calling that clean is the worst possible
        -- answer: a broken or missing luajit, or a file that does not compile,
        -- would turn the whole check into a no-op that passes.
        print(string.format("NO LISTING    %s  luajit -bl gave no bytecode: %s", path, err))
        print("                ^ this file was NOT analysed  -  fix the toolchain or the file")
        findings = findings + 1
    else

    -- Any global write from addon code is a bug: it leaks into the shared
    -- environment.  The tree currently has zero; keep it that way.
    local wnames = {}
    for name in pairs(writes) do wnames[#wnames + 1] = name end
    table.sort(wnames)
    for _, name in ipairs(wnames) do
        print(string.format("GLOBAL WRITE  %-46s %s", name, path))
        findings = findings + 1
    end

    local rnames = {}
    for name in pairs(reads) do rnames[#rnames + 1] = name end
    table.sort(rnames)
    for _, name in ipairs(rnames) do
        if not isAllowed(name) then
            print(string.format("GLOBAL READ   %-46s %s", name, path))
            print("              ^ not an ESO symbol  -  missing a require?")
            findings = findings + 1
        end
    end

    end
end

if findings == 0 then
    print(string.format("globals: clean (%d files scanned)", files))
else
    print(string.format("globals: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
