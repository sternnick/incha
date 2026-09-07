--- core/Lang.lua  -  String table selector.
---
--- Reads GetCVar("Language.2") at load time (available before EVENT_ADD_ON_LOADED)
--- and returns the matching lang module, falling back to English.
---
--- Usage:
---   local Lang = require("core.Lang")
---   -- static string:
---   alerts:showAction(Lang.t("ss_block_jump"))
---   -- format string:
---   alerts:setRow(1, Lang.t("ss_yolna_next_flare"), T)
---
--- Adding a new locale:
---   1. Create lang/<code>.lua in the same style as lang/en.lua.
---   2. Add it to incha.txt BEFORE core/Lang.lua.
---   3. Translate boss .name / .nameAliases and all alert strings.

local Lang = {}

local _code = (GetCVar and GetCVar("Language.2")) or "en"
local _t    = package.loaded["lang." .. _code]
           or package.loaded["lang.en"]
           or {}

if _code ~= "en" and not package.loaded["lang." .. _code] then
    -- Non-fatal: warn once in chat log and fall back to English.
    d("[Incha] Lang: no strings for locale '" .. _code .. "' — using English fallback.")
end

--- Return the localised string for `key`.
--- When extra arguments are given the string is treated as a format string
--- and passed through string.format(str, ...).
--- Returns the key itself when no entry is found so missing keys are visible.
---@param key string
---@return string
function Lang.t(key, ...)
    local str = _t[key]
    if not str then return key end
    if select("#", ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

package.loaded["core.Lang"] = Lang
return Lang
