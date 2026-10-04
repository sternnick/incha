--- test/checks/snapshot.lua  -  alert-sequence snapshot regression net.
---
--- Phase 2 item 1 of test/README.md: replay every committed fixture through
--- the shipping runner (test/run_log.lua), capture its complete output, and
--- fail when it differs from the committed golden under test/snapshots/.
--- Until now "the replay ran clean" only proved no handler threw; a change
--- that silently dropped or reordered an alert, or regressed a tracker row,
--- moved the whole tree one quiet step sideways with nothing to notice.
---
--- The golden is the FULL stdout+stderr of the runner for that fixture:
--- alert lines, TRACKER row writes, handler errors, per-ability coverage and
--- the summary counts. Every one of those is a shipping behaviour worth
--- pinning, and pinning the summary counts too catches drift (a fixture that
--- stopped activating a boss, a route table that lost an entry) even where
--- no alert text changed.
---
--- Determinism is the precondition of this check and was measured before it
--- was written: all nine fixtures produce byte-identical output across
--- repeated runs on one machine (the simulated clock is driven from log
--- timestamps, never wall time). If a future change makes any replay vary,
--- THIS check will report the variance as a mismatch against its own golden
--- after --update - investigate that before touching a golden again.
---
--- Usage (from the repository root):
---   luajit test/checks/snapshot.lua            # compare against goldens
---   luajit test/checks/snapshot.lua --update   # rewrite goldens (after an
---                                              # INTENTIONAL behaviour
---                                              # change; review the diff!)
---
--- Exit code 0 = every fixture reproduces its golden, 1 = at least one
--- fixture changed, failed, or has no golden yet.

local UPDATE = (arg[1] == "--update")

-- The fixtures double as the trial list: one file per trial, named by trial
-- id. io.popen keeps the list honest without restating it here - a fixture
-- dropped into test/fixtures/ is covered automatically. (POSIX popen is what
-- CI runs on; the harness already assumes a POSIX-ish shell via *.sh checks.)
local pipe = io.popen("ls test/fixtures 2>/dev/null")
if not pipe then
    print("FAIL  could not list test/fixtures (io.popen unavailable?)")
    os.exit(1)
end
local names = {}
for line in pipe:lines() do
    if line:match("^(.+)%.log$") then names[#names + 1] = line end
end
pipe:close()
table.sort(names)

if #names == 0 then
    print("FAIL  no .log fixtures found under test/fixtures")
    os.exit(1)
end

os.execute("mkdir -p test/snapshots 2>/dev/null")

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- One hunk of context is enough to find the change in a few-thousand-line
-- diff by eye; capping the list keeps a wholesale rewrite from flooding CI.
local MAX_REPORTED_DIFFS = 10

local function reportDiff(golden, actual, path)
    local gl, al = {}, {}
    for line in (golden .. "\n"):gmatch("([^\n]*)\n") do gl[#gl + 1] = line end
    for line in (actual  .. "\n"):gmatch("([^\n]*)\n") do al[#al + 1] = line end
    local reported = 0
    local n = math.max(#gl, #al)
    for i = 1, n do
        if gl[i] ~= al[i] then
            reported = reported + 1
            if reported <= MAX_REPORTED_DIFFS then
                print(string.format("  line %d:", i))
                print(string.format("    golden: %s", gl[i] or "(missing)"))
                print(string.format("    actual: %s", al[i] or "(missing)"))
            end
        end
    end
    if reported > MAX_REPORTED_DIFFS then
        print(string.format("  ... and %d more differing lines", reported - MAX_REPORTED_DIFFS))
    end
    print(string.format("  (%d of %d lines differ)", (function()
        local d = 0
        for i = 1, n do if gl[i] ~= al[i] then d = d + 1 end end
        return d
    end)(), n))
    print("  If this change is intended: luajit test/checks/snapshot.lua --update")
    print("  then review the golden diff before committing. Never --update to")
    print("  silence an unexplained mismatch.")
    print("  golden: " .. path)
end

local findings = 0
local matched, written = 0, 0

for _, name in ipairs(names) do
    local trial  = name:gsub("%.log$", "")
    local golden = "test/snapshots/" .. trial .. ".txt"
    local fixture = "test/fixtures/" .. name

    -- The runner exits nonzero on handler errors; __rc= lets us see that
    -- through the pipe. stderr joins the capture on purpose - a handler
    -- error is exactly the kind of change a snapshot must make loud.
    local p = io.popen(string.format(
        "luajit test/run_log.lua %s 2>&1; echo \"__rc=$?\"", fixture))
    if not p then
        print("FAIL  " .. trial .. ": could not run the replay runner")
        findings = findings + 1
    else
        local out = p:read("*a")
        p:close()
        local rc = tonumber(out:match("__rc=(%d+)%s*$")) or -1
        out = out:gsub("__rc=%d+%s*$", "")

        if rc ~= 0 then
            print("FAIL  " .. trial .. ": replay exited " .. rc
                .. " (handler errors or bad log - see output above)")
            findings = findings + 1
        else
            local gold = readAll(golden)
            if UPDATE then
                local f = io.open(golden, "wb")
                if not f then
                    print("FAIL  " .. trial .. ": cannot write " .. golden)
                    findings = findings + 1
                else
                    f:write(out)
                    f:close()
                    print("WROTE " .. trial .. ": " .. golden)
                    written = written + 1
                end
            elseif gold == nil then
                -- A missing golden must NOT silently record-and-pass: that is
                -- the exact silent-failure shape this whole check exists to
                -- catch. CI fails; regenerate deliberately with --update.
                print("FAIL  " .. trial .. ": no golden under test/snapshots/ (run `luajit test/checks/snapshot.lua --update` locally and commit the golden)")
                findings = findings + 1
            elseif gold == out then
                print("ok    " .. trial)
                matched = matched + 1
            else
                print("FAIL  " .. trial .. ": replay output differs from golden")
                reportDiff(gold, out, golden)
                findings = findings + 1
            end
        end
    end
end

print(string.format("snapshot: %d matched, %d recorded, %d failed",
    matched, written, findings))
os.exit(findings > 0 and 1 or 0)
