--- hmHealthThreshold diagnostic: turns "we need a game client" into "stand
--- in the encounter, run one command, paste one block".
---
--- Background: 16 of the 25 bosses declaring hmHealthThreshold carry a
--- sentinel instead of a measured number at master de1dea6 (11x math.huge,
--- 5x 100000001 - verified by grep and enforced by
--- test/checks/hm-thresholds.lua). Both sentinels are silently wrong:
--- math.huge pins difficulty to NORMAL forever (no real pool is >= inf),
--- while 100000001 sits below every vet pool so BossRegistry's >= compare
--- pins those bosses to HARDMODE. Staged upstream items 7e(i)/21c.
---
--- /incha thresholds prints two blocks:
---   1. the whole declared inventory across all 9 trials, sentinel-marked;
---   2. live health samples for the boss<N> slots of the zone you are
---      standing in, with a paste-ready assignment line.
--- Run block 2 during a boss encounter (debug flag NOT required - the
--- values printed are engine samples, not guesses).

local Log         = require("lib.Log")
local ZoneManager = require("core.ZoneManager")

local Thresholds = {}

-- 100000001 is the project's historical "unmeasured" sentinel (one above
-- the round 1e8 pools); no real boss pool equals it.
-- why: same constant test/checks/hm-thresholds.lua classifies with - keep
-- the two in sync or the inventory report and the CI check disagree.
local SENTINEL = 100000001

-- Mirrors BOSS_SLOTS in core/Trial.lua:193 - concurrent-boss encounters
-- (e.g. Ryelaz+Zilyesset) occupy boss1..boss4 in unspecified order, so
-- every slot must be sampled, not just boss1.
-- why: duplicated rather than imported because BOSS_SLOTS is a file-local
-- of core/Trial.lua and importing it would widen that module's surface for
-- a diagnostic.
local BOSS_SLOTS = { "boss1", "boss2", "boss3", "boss4" }

local function classify(v)
    if v == nil then
        return "no-HM (declares nothing)"
    elseif v == math.huge then
        return "UNKNOWN (math.huge -> always NORMAL)"
    elseif v == SENTINEL then
        return "SENTINEL (100000001 -> always HARDMODE)"
    end
    return string.format("measured (%d)", v)
end

--- Print the declared inventory and, when a boss unit is live, the engine
--- health samples needed to replace every sentinel for this encounter.
function Thresholds.dump()
    Log.print("-- 1. declared hmHealthThreshold inventory --")
    local sentinelCount, totalCount = 0, 0
    for _, entry in ipairs(ZoneManager.getTrialList()) do
        local trial = entry.module
        for _, boss in ipairs(trial.registry.bosses) do
            totalCount = totalCount + 1
            local v = boss.hmHealthThreshold
            if v == math.huge or v == SENTINEL then
                sentinelCount = sentinelCount + 1
            end
            Log.print("  %s  %-18s %-24s %s",
                tostring(trial.id), tostring(boss.key),
                tostring(boss.name or "?"), classify(v))
        end
    end
    Log.print("  %d of %d threshold declarations are sentinels",
        sentinelCount, totalCount)

    Log.print("-- 2. live samples (this zone) --")
    local trial = ZoneManager.getActiveTrial()
    if not trial then
        Log.print("  not in a trial zone - stand in one and re-run")
        return
    end

    local seen = 0
    for _, slot in ipairs(BOSS_SLOTS) do
        if DoesUnitExist(slot) then
            local cur, maxHp, effMax = GetUnitPower(slot, POWERTYPE_HEALTH)
            if maxHp and maxHp > 0 then
                seen = seen + 1
                local unitName = GetUnitName(slot)
                local match = trial.registry:findByName(unitName)
                Log.print("  %s %q  hp=%d/%d eff=%d  match: %s",
                    slot, unitName, cur or 0, maxHp, effMax or 0,
                    match and (tostring(trial.id) .. "/" .. tostring(match.key))
                            or "no class matched by name")
                -- Effective max first: ESO reports HM pools enlarged via
                -- effectiveMax, and core/Trial.lua's difficulty sampler
                -- (Trial.lua:296) uses the same fallback order.
                local sample = (effMax and effMax > 0) and effMax or maxHp
                Log.print("    -- measured in-game: %s.%s.hmHealthThreshold = %d",
                    tostring(trial.id),
                    match and tostring(match.key) or "<boss>",
                    sample)
            end
        end
    end
    if seen == 0 then
        Log.print("  no live boss unit in any slot - run during an encounter")
    end
end

package.loaded["ui.Thresholds"] = Thresholds
return Thresholds
