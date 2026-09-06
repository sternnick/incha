local Difficulty = require("core.Difficulty")

local BossRegistry = {}
BossRegistry.__index = BossRegistry

function BossRegistry.new(bosses)
    local self = setmetatable({
        bosses = bosses or {},
        byId = {},
        byKey = {},
    }, BossRegistry)

    for i, boss in ipairs(self.bosses) do
        boss.id = i          -- auto-assigned from array position; matches Factory order
        self.byId[boss.id] = boss
        self.byKey[boss.key] = boss
    end

    return self
end

function BossRegistry:getById(id)
    return self.byId[id]
end

function BossRegistry:getByKey(key)
    return self.byKey[key]
end

function BossRegistry:findAtPosition(x, y, z)
    for _, boss in ipairs(self.bosses) do
        if boss.location and boss.location:contains(x, y, z) then
            return boss
        end
    end

    return nil
end

-- GetUnitName can return a name carrying ESO's gender / article markup
-- ("^Fx", "^n" suffixes and similar).  zo_strformat("<<1>>", name) is the
-- documented way to render it to the plain display string, and this file
-- must apply it to BOTH sides: the declared boss.name literals were written
-- by hand and are already plain, but normalising them too keeps the
-- comparison symmetric if someone later pastes a raw name in.
local function normalize(name)
    if not name or name == "" then return nil end
    local ok, plain = pcall(zo_strformat, "<<1>>", name)
    if ok and plain and plain ~= "" then return plain end
    return name
end

-- Name-based fallback for trials whose bosses have no location bounding box.
-- Matches boss.name (or any entry in boss.nameAliases) against the supplied
-- unit name. nameAliases lets a single boss entry cover multiple unit names
-- (e.g. the Lylanar/Turlassil dual-boss pair in DSR).
--
-- CAVEAT: this compares against English literals, so on a localised client
-- (DE/FR/RU/ES/JP) it matches nothing and the trial silently does nothing.
-- Only KA currently declares Location bounds, which are locale-independent;
-- every other trial relies solely on this path.  See the "Real Location
-- bounds" item tracked as issue #123.
function BossRegistry:findByName(unitName)
    local target = normalize(unitName)
    if not target then return nil end

    for _, boss in ipairs(self.bosses) do
        if normalize(boss.name) == target then
            return boss
        end
        if boss.nameAliases then
            for _, alias in ipairs(boss.nameAliases) do
                if normalize(alias) == target then
                    return boss
                end
            end
        end
    end
    return nil
end

--- Every unit name this registry would accept, for diagnostics.
--- Used by Trial to report what was expected when detection fails.
function BossRegistry:knownNames()
    local names = {}
    for _, boss in ipairs(self.bosses) do
        if boss.name then names[#names + 1] = boss.name end
        if boss.nameAliases then
            for _, alias in ipairs(boss.nameAliases) do
                names[#names + 1] = alias
            end
        end
    end
    return names
end

--- Classify an encounter from the boss's effective max health.
---
--- Returns Difficulty.NONE for "not known yet" as well as "boss declares no
--- threshold".  The distinction matters: GetUnitPower can legitimately read 0
--- on the frame a boss appears, and reporting NORMAL from that sample is a
--- positive claim the addon has not earned.  NONE lets Trial re-resolve on a
--- later tick once a real value arrives.
function BossRegistry:detectDifficulty(boss, effectiveMaxHealth)
    if not boss or not boss.hmHealthThreshold then
        return Difficulty.NONE
    end

    -- No usable sample yet  -  stay unknown rather than guessing NORMAL.
    if not effectiveMaxHealth or effectiveMaxHealth <= 0 then
        return Difficulty.NONE
    end

    if effectiveMaxHealth >= boss.hmHealthThreshold then
        return Difficulty.HARDMODE
    end

    return Difficulty.NORMAL
end

package.loaded["core.BossRegistry"] = BossRegistry
return BossRegistry
