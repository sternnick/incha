--- test/checks/hm-thresholds.lua  -  the HM sentinel inventory, frozen.
---
--- hmHealthThreshold decides NORMAL vs HARDMODE (core/BossRegistry.lua's
--- detectDifficulty: a sample >= threshold reads HARDMODE). Two placeholder
--- values shipped in the tree read silently wrong against real pools:
---
---   math.huge     - no pool is >= infinity, difficulty stays NORMAL forever
---   100000001     - below every vet HM pool, difficulty locks HARDMODE
---
--- Neither is a crash, so nothing ever failed and the placeholders drifted
--- into "looks settled" territory (the failure mode agents/workflow-code-review.md
--- §1 warns about). 16 of 25 declarations were sentinels at de1dea6
--- (grep-verified; staged upstream as finding 7e(i)/21c).
---
--- This check does NOT try to be right about which numbers are measured —
--- it freezes the CURRENT sentinel set: a NEW sentinel anywhere fails, a
--- fixed value prints FIXED, and a baseline entry whose file/value changed
--- fails as stale. Real values come from `/incha thresholds` in-game.
---
--- Usage (from the repository root):
---   luajit test/checks/hm-thresholds.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local MANIFEST = "incha.txt"

-- file -> sentinel value as written in the source ("math.huge" or the
-- number). Update ONLY when a threshold is measured (value becomes a plain
-- number here and the line drops out) or a NEW sentinel is knowingly added
-- (which then also needs an in-game request per agents/workflow-code-review.md §4).
local BASELINE = {
    ["trial/ss/boss/Lokke.lua"]              = "math.huge",
    ["trial/ss/boss/Yolna.lua"]              = "math.huge",
    ["trial/ss/boss/Nahvii.lua"]             = "math.huge",
    ["trial/rg/boss/Oaxiltso.lua"]           = "math.huge",
    ["trial/rg/boss/Bahsei.lua"]             = "100000001",
    ["trial/rg/boss/Xalvakka.lua"]           = "100000001",
    ["trial/dsr/boss/Lylanar.lua"]           = "100000001",
    ["trial/dsr/boss/ReefGuardian.lua"]      = "100000001",
    ["trial/dsr/boss/Taleria.lua"]           = "100000001",
    ["trial/as/boss/OlmsEncounter.lua"]      = "math.huge",
    ["trial/cr/boss/ZmajaEncounter.lua"]     = "math.huge",
    ["trial/lc/boss/DarielEncounter.lua"]    = "math.huge",
    ["trial/lc/boss/XynizataEncounter.lua"]  = "math.huge",
    ["trial/oc/boss/JynorahEncounter.lua"]   = "math.huge",
    ["trial/oc/boss/KazpianEncounter.lua"]   = "math.huge",
    ["trial/oc/boss/ShaperEncounter.lua"]    = "math.huge",
}

local SENTINELS = { ["math.huge"] = true, ["100000001"] = true }

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

local manifest = read(MANIFEST)
if not manifest then
    print("cannot read " .. MANIFEST .. "  -  run this from the repository root")
    os.exit(1)
end

-- Every value written for hmHealthThreshold in a shipped file, keyed by
-- file. Boss files assign exactly once; multiple assigns are themselves a
-- finding (which line wins becomes load-order trivia).
local found = {}
for line in manifest:gmatch("[^\r\n]+") do
    local path = line:match("^%s*([%w_%-%./]+%.lua)%s*$")
    if path and path:find("^trial/") then
        path = path:gsub("^%./", "")
        local body = read(path)
        if body then
            for val in body:gmatch("hmHealthThreshold%s*=%s*([^%s%-]+)") do
                found[path] = found[path] or {}
                table.insert(found[path], val)
            end
        end
    end
end

local checked, fixed = 0, 0
for path, vals in pairs(found) do
    if #vals > 1 then
        fail("MULTIPLE      %s assigns hmHealthThreshold %d times", path, #vals)
    end
    local val = vals[1]
    checked = checked + 1
    local base = BASELINE[path]
    if SENTINELS[val] then
        if base == nil then
            fail("NEW SENTINEL  %s declares hmHealthThreshold = %s - a placeholder that "
                 .. "silently pins difficulty (math.huge -> always NORMAL, 100000001 -> "
                 .. "always HARDMODE). Measure it in-game (/incha thresholds) instead.",
                 path, val)
        elseif base ~= val then
            fail("STALE BASELINE %s baseline says %s, source says %s - update BASELINE "
                 .. "deliberately, never silently", path, base, val)
        else
            print(string.format("KNOWN         %s hmHealthThreshold = %s (unmeasured)",
                                path, val))
        end
    else
        if not val:match("^%d+$") then
            fail("UNPARSEABLE   %s hmHealthThreshold = %q - expected a number or a known sentinel",
                 path, val)
        elseif base then
            print(string.format("FIXED         %s (was %s) - remove the BASELINE entry",
                                path, base))
            fixed = fixed + 1
        end
    end
end

for path in pairs(BASELINE) do
    if not found[path] then
        fail("STALE BASELINE %s listed here declares no hmHealthThreshold - the boss lost "
             .. "its threshold entirely (difficulties no longer distinguishable)", path)
    end
end

local sentinelListed = 0
for path, vals in pairs(found) do
    if SENTINELS[vals[1]] and BASELINE[path] == vals[1] then
        sentinelListed = sentinelListed + 1
    end
end
print(string.format("%d boss files declare hmHealthThreshold (%d listed sentinels, %d newly measured)",
    checked, sentinelListed, fixed))

if findings > 0 then
    print(string.format("hm-thresholds: %d finding(s)", findings))
    os.exit(1)
end
print("hm-thresholds: OK (sentinel inventory matches baseline)")
