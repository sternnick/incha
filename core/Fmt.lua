--- core/Fmt.lua  -  ESO colour-markup and number-format helpers.
---
--- Colour names (Colors.FIRE, Colors.ICE, …) are accepted by Fmt.c and
--- Fmt.colored.  A hex-string lookup table is built from Colors._rgb once
--- at load time, giving O(1) name→hex conversion.
---
--- Fmt also re-exports every colour name as a constant (Fmt.FIRE, …) so
--- files that already import Fmt do not need a separate Colors import.
---
--- Usage:
---   local Fmt = require("core.Fmt")
---   Fmt.c(Fmt.RED, "INC")                       -- "|cff0000INC|r"
---   Fmt.c(Colors.FIRE, "Stomp inbound!")
---   Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " INC")

local ColorDefs = require("external-api.ColorDefs")
local Colors    = require("core.Colors")
local Fmt = {}

-- ── Hex lookup (built once) ───────────────────────────────────────────────

local _hex = ColorDefs.build(function(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end)

-- ── Colour re-exports ─────────────────────────────────────────────────────
-- Fmt.FIRE == Colors.FIRE == "FIRE"; the hex string stays private.

for name in pairs(_hex) do
    Fmt[name] = Colors[name]
end

-- ── API ───────────────────────────────────────────────────────────────────

--- Wrap text in a single ESO colour segment.
--- @param color string  colour name (Colors.*) or raw 6-char hex string
--- @param text  string  text to colour
--- @return string       "|cCOLORtext|r"
function Fmt.c(color, text)
    return "|c" .. (_hex[color] or color) .. tostring(text) .. "|r"
end

--- Build a multi-segment coloured string from alternating (color, text) pairs.
--- Fmt.colored(Fmt.CYAN, "Ice Tomb", Fmt.RED, " 2 INC")
--- An odd trailing arg (colour without text) is silently ignored.
function Fmt.colored(...)
    local args = { ... }
    local parts = {}
    for i = 1, #args - 1, 2 do
        parts[#parts + 1] = "|c" .. (_hex[args[i]] or args[i]) .. tostring(args[i + 1]) .. "|r"
    end
    return table.concat(parts)
end

--- Format a timer value as a human-readable string.
--- Fmt.timer(3.7)    → "4s"   (0 decimals, default)
--- Fmt.timer(3.7, 1) → "3.7s"
function Fmt.timer(n, d)
    return string.format("%." .. (d or 0) .. "f", n) .. "s"
end

--- Format a percentage value as a human-readable string.
--- Fmt.pct(54.3)     → "54%"  (0 decimals, default)
--- Fmt.pct(37.5, 1)  → "37.5%"
function Fmt.pct(n, d)
    return string.format("%." .. (d or 0) .. "f%%", n)
end

package.loaded["core.Fmt"] = Fmt
return Fmt
