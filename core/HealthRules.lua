local HealthRules = {}

local function formatText(template, healthPercent)
    return (template:gsub("{hp}", string.format("%.1f", healthPercent)))
end

-- `boss` is the active boss instance (or singleton).  Passed through to
-- rule.when() as a second argument so predicates can read boss state
-- (e.g. a per-trial setting flag) without polluting TrialContext.
-- Legacy when(ctx) predicates that ignore the second arg still work fine.
function HealthRules.matches(rule, healthPercent, context, boss)
    if rule.min == nil or rule.max == nil then return false end
    if healthPercent < rule.min or healthPercent > rule.max then
        return false
    end

    if rule.when and not rule.when(context, boss) then
        return false
    end

    return true
end

-- Sort rules by priority descending at registration time so evaluate()
-- can stay a simple first-match scan.  Call once per boss class, not
-- per encounter  -  the sorted order is shared across all instances.
-- Rules with no priority field default to 0; table.sort is stable in
-- LuaJIT so equal-priority rules keep their declaration order.
--
-- Also pre-compiles any rule whose text contains no {hp} placeholder:
-- the formatted string is baked in at load time so evaluate() never
-- calls formatText (or string.format) for those rules on the hot path.
function HealthRules.register(rules)
    table.sort(rules, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
    for _, rule in ipairs(rules) do
        if not rule.text:find("{hp}", 1, true) then
            -- Static text: no runtime substitution needed.
            rule._staticText = rule.text
        end
    end
    return rules
end

-- Returns id, text as plain values (no table) since this runs on the
-- boss-health hot path and Lua multiple-return doesn't allocate.
-- Assumes rules were sorted by HealthRules.register at class load time.
-- For rules pre-compiled by register() (_staticText set), the cached
-- string is returned directly  -  no allocation occurs on the hot path.
-- Returns nil immediately when rules is nil/absent (avoids the `or {}`
-- empty-table allocation that would otherwise occur on every throttled tick).
function HealthRules.evaluate(rules, healthPercent, context, boss)
    if not rules then return nil end
    for _, rule in ipairs(rules) do
        if HealthRules.matches(rule, healthPercent, context, boss) then
            return rule.id, rule._staticText or formatText(rule.text, healthPercent)
        end
    end
    return nil
end

package.loaded["core.HealthRules"] = HealthRules
return HealthRules
