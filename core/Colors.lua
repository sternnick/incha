--- core/Colors.lua  -  Colour name enum.
---
--- The single source of truth for colour *names*.  Boss files import this
--- module and reference colours by name:
---
---   local Colors = require("core.Colors")
---   CA.melee(id, name, dur, Colors.FIRE)
---   Fmt.c(Colors.PURPLE, "next curse")
---
--- Colors.lua knows only names — never RGB values, hex strings, or any
--- format-specific encoding.  The translation from name to actual colour
--- value lives in the API layer that needs it (Fmt, CombatAlerts, etc.),
--- each of which builds its own O(1) lookup table from external-api.ColorDefs.

local Colors = {}

-- Elemental
Colors.FIRE      = "FIRE"       -- fire orange  (stomp / slam / blast)
Colors.ICE       = "ICE"        -- frost blue   (ice cast / freeze)
Colors.LIGHTNING = "LIGHTNING"  -- electric     (shock / surge / arc)
Colors.VOID      = "VOID"       -- void purple  (shadow / arcane void)
Colors.POISON    = "POISON"     -- poison green (dot / corrosion)

-- Semantic
Colors.RED       = "RED"        -- danger / critical / INC
Colors.ORANGE    = "ORANGE"     -- caution
Colors.YELLOW    = "YELLOW"     -- warning / gold
Colors.GREEN     = "GREEN"      -- success / ready / clear
Colors.CYAN      = "CYAN"       -- aqua label
Colors.AQUA      = "AQUA"       -- aquamarine (laser / portal labels)
Colors.GOLD      = "GOLD"       -- addon tag / golden accent
Colors.PURPLE    = "PURPLE"     -- light purple / arcane accent
Colors.FROST     = "FROST"      -- light frost blue (paired-boss ice-side)

-- Accent
Colors.AMBER     = "AMBER"      -- warm amber (LC mechanics / phases)
Colors.ARCANE    = "ARCANE"     -- deep arcane (manifold / curse)
Colors.TEAL      = "TEAL"       -- teal (shield / safe window)
Colors.SKY       = "SKY"        -- sky-blue (portal label / teleport)
Colors.SMOKE     = "SMOKE"      -- slate (in-progress / neutral timer)
Colors.GRAY      = "GRAY"       -- gray (count / secondary info)
Colors.PINK      = "PINK"       -- pink-red (soft warning / fog-end)
Colors.CRIMSON   = "CRIMSON"    -- dark red (fail / hard stop)
Colors.LEAF      = "LEAF"       -- medium green (skip / ok signal)
Colors.LANDING   = "LANDING"    -- light green (landing countdown)
Colors.FLYZONE   = "FLYZONE"    -- orange (fly-in / enter threshold)

-- Special-use
Colors.BLUE      = "BLUE"       -- pure blue (fog / magical barrier)
Colors.SILVER    = "SILVER"     -- neutral gray (untyped block/dodge bar)
Colors.MAGENTA   = "MAGENTA"    -- hot pink (urgent dodge signal)

package.loaded["core.Colors"] = Colors
return Colors
