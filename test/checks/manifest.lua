--- test/checks/manifest.lua  -  keep incha.txt and the file tree in agreement.
---
--- ESO loads exactly the files listed in the manifest, in the order listed.
--- Two failure modes follow, and neither produces an error in game:
---
---   - a .lua file that exists but is not listed simply never runs, so its
---     package.loaded registration never happens and the first require() of
---     it throws at load time;
---   - a listed file that no longer exists is skipped silently.
---
--- Usage (from the repository root):
---   luajit test/checks/manifest.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

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

-- -- Parse the manifest ------------------------------------------------------
local manifestText = read(MANIFEST)
if not manifestText then
    print("cannot read " .. MANIFEST .. "  -  run this from the repository root")
    os.exit(1)
end

local listed, order = {}, {}
for line in manifestText:gmatch("[^\r\n]+") do
    local entry = line:match("^%s*([%w_%-/%.]+%.lua)%s*$")
    if entry then
        entry = entry:gsub("\\", "/")
        if listed[entry] then
            fail("DUPLICATE     %s is listed twice in %s", entry, MANIFEST)
        end
        listed[entry] = true
        order[#order + 1] = entry
    end
end

-- -- Every listed file must exist -------------------------------------------
for _, entry in ipairs(order) do
    local f = io.open(entry, "r")
    if not f then
        fail("MISSING FILE  %s is listed in %s but does not exist", entry, MANIFEST)
    else
        f:close()
    end
end

-- -- Every source file must be listed ---------------------------------------
local p = io.popen('find . -name "*.lua" -not -path "./.git/*" '
    .. '-not -path "./.claude/*" -not -path "./test/*" 2>/dev/null')
local onDisk = {}
for line in p:lines() do
    local rel = line:gsub("%s+$", ""):gsub("^%./", ""):gsub("\\", "/")
    onDisk[#onDisk + 1] = rel
end
p:close()
table.sort(onDisk)

for _, rel in ipairs(onDisk) do
    if not listed[rel] then
        fail("NOT LOADED    %s exists but is not listed in %s  -  ESO will "
             .. "never execute it", rel, MANIFEST)
    end
end

-- -- bootstrap.lua must come first ------------------------------------------
if order[1] ~= "bootstrap.lua" then
    fail("LOAD ORDER    bootstrap.lua must be the first entry in %s "
         .. "(it defines require and the ADDON_* globals); found %s",
         MANIFEST, tostring(order[1]))
end

-- -- Version strings must agree ---------------------------------------------
-- The code-side version lives in ADDON_VERSION in bootstrap.lua; the ESO-
-- side version lives in "## Version:" in incha.txt.  Both must match.
-- (incha.lua and ui/Menu.lua reference ADDON_VERSION at runtime so they
-- are always in sync with bootstrap.lua and need no separate check here.)
local function versionIn(path, pattern, label)
    local text = read(path)
    if not text then
        fail("MISSING FILE  cannot read %s", path)
        return nil
    end
    local v = text:match(pattern)
    if not v then
        fail("NO VERSION    could not find the %s version string in %s", label, path)
    end
    return v
end

local manifestVersion  = manifestText:match("##%s*Version:%s*(%S+)")
local bootstrapVersion = versionIn("bootstrap.lua",
                             'ADDON_VERSION%s*=%s*"(%d+%.%d+%.%d+)"',
                             "ADDON_VERSION")

if not manifestVersion then
    fail("NO VERSION    %s has no '## Version:' line", MANIFEST)
elseif bootstrapVersion then
    if manifestVersion ~= bootstrapVersion then
        fail("VERSION DRIFT %s says %s, bootstrap.lua ADDON_VERSION is %s",
             MANIFEST, manifestVersion, bootstrapVersion)
    end
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("manifest: clean (%d files listed, version %s)",
          #order, tostring(manifestVersion)))
else
    print(string.format("manifest: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
