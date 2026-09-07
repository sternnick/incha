--- external-api/ColorDefs.lua  -  Linear RGB definitions for API layers.
---
--- This file is the single source of colour *values*.  It is required only
--- by the API layers that need to translate a colour name into a
--- format-specific value (hex string, CA table, RGB array …).
--- Boss files never require this — they use core.Colors for named constants.
---
--- Usage in a layer:
---   local ColorDefs = require("external-api.ColorDefs")
---   local _hex = ColorDefs.build(function(r, g, b)
---       return string.format("%02x%02x%02x", r*255, g*255, b*255)
---   end)
---   -- _hex["FIRE"] == "ff591a", etc.

local ColorDefs = {}

-- ── Linear RGB values (0-1) ────────────────────────────────────────────────
-- Must contain exactly the same set of names as core.Colors.

local _rgb = {
    -- Elemental
    FIRE      = { 1.00, 0.35, 0.10 },   -- fire orange  (stomp / slam / blast)
    ICE       = { 0.30, 0.75, 1.00 },   -- frost blue   (ice cast / freeze)
    LIGHTNING = { 0.90, 0.90, 0.10 },   -- electric     (shock / surge / arc)
    VOID      = { 0.70, 0.20, 0.90 },   -- void / arcane purple
    POISON    = { 0.40, 0.80, 0.40 },   -- poison green (dot / corrosion)

    -- Semantic
    RED       = { 1.00, 0.00, 0.00 },   -- danger / critical / INC
    ORANGE    = { 1.00, 0.53, 0.00 },   -- caution
    YELLOW    = { 1.00, 0.87, 0.00 },   -- warning / gold
    GREEN     = { 0.00, 1.00, 0.00 },   -- success / ready / clear
    CYAN      = { 0.00, 1.00, 1.00 },   -- aqua label
    AQUA      = { 0.50, 1.00, 0.83 },   -- aquamarine (laser / portal labels)
    GOLD      = { 1.00, 0.84, 0.00 },   -- addon tag / golden accent
    PURPLE    = { 0.80, 0.50, 1.00 },   -- light purple / arcane accent
    FROST     = { 0.60, 0.80, 1.00 },   -- light frost blue (paired-boss ice-side)

    -- Accent
    AMBER     = { 1.00, 0.67, 0.27 },   -- warm amber (LC mechanics / phases)
    ARCANE    = { 0.67, 0.27, 1.00 },   -- deep arcane (manifold / curse)
    TEAL      = { 0.46, 0.90, 0.85 },   -- teal (shield / safe window)
    SKY       = { 0.22, 0.74, 0.97 },   -- sky-blue (portal label / teleport)
    SMOKE     = { 0.48, 0.51, 0.63 },   -- slate (in-progress / neutral timer)
    GRAY      = { 0.53, 0.53, 0.53 },   -- gray (count / secondary info)
    PINK      = { 1.00, 0.40, 0.40 },   -- pink-red (soft warning / fog-end)
    CRIMSON   = { 0.80, 0.27, 0.27 },   -- dark red (fail / hard stop)
    LEAF      = { 0.33, 0.67, 0.33 },   -- medium green (skip / ok signal)
    LANDING   = { 0.36, 0.84, 0.36 },   -- light green (landing countdown)
    FLYZONE   = { 1.00, 0.65, 0.00 },   -- orange (fly-in / enter threshold)

    -- Special-use
    BLUE      = { 0.00, 0.00, 1.00 },   -- pure blue (fog / magical barrier)
    SILVER    = { 0.70, 0.70, 0.70 },   -- neutral gray (untyped block/dodge bar)
    MAGENTA   = { 1.00, 0.20, 0.90 },   -- hot pink (urgent dodge signal)
}

-- ── Layer builder ──────────────────────────────────────────────────────────
--- Build a lookup table { colorName → value } from the RGB definitions.
--- Each API layer calls this once at module-load time.
---
--- @param fn function  fn(r, g, b) → value to store under colorName
--- @return table        { [colorName] = fn(r, g, b), ... }
function ColorDefs.build(fn)
    local t = {}
    for name, c in pairs(_rgb) do
        t[name] = fn(c[1], c[2], c[3])
    end
    return t
end

package.loaded["external-api.ColorDefs"] = ColorDefs
return ColorDefs
