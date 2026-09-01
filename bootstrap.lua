-- ESO does not expose require() or the package library.  This file MUST be
-- the very first entry in incha.txt.
--
-- Every module file registers itself immediately before its return statement:
--     package.loaded["module.name"] = ExportVar
--     return ExportVar
-- so that later require() calls resolve without file I/O.

-- -- Addon identity ---------------------------------------------------------
-- To rename the addon, change _n below.  Also update three things outside Lua:
--   1. The folder name on disk
--   2. ## Title: in the manifest (.txt)
--   3. ## SavedVariables: in the manifest (.txt)  <- only if you want a clean break;
--      keeping the old SV name lets existing users keep their saved settings.
local _n = "incha"
local _t = _n:sub(1, 1):upper() .. _n:sub(2)  -- title-case: "Incha"

ADDON_NAME   = _n                -- folder name  -  matches EVENT_ADD_ON_LOADED
ADDON_TITLE  = _t                -- display name  -  "Incha"
ADDON_TAG    = "|cFFD700[" .. _t .. "]|r"  -- coloured chat prefix  -  "[Incha]"
ADDON_SLASH  = "/" .. _n         -- slash command  -  "/incha"
ADDON_VERSION = "0.1.0"         -- single source of truth (README badge, LAM, chat)
ADDON_SV     = _t .. "_SV"      -- SavedVariables key  -  "Incha_SV"
ADDON_PREFIX = _t .. "_"        -- event/handler name prefix  -  "Incha_"
ADDON_LAM    = _t .. "Settings"  -- LibAddonMenu panel ID  -  "InchaSettings"
-- --------------------------------------------------------------------------

package = { loaded = {} }

function require(name)
    local mod = package.loaded[name]
    if mod ~= nil then return mod end
    error(ADDON_TAG .. " require('" .. name .. "'): module not registered. "
        .. "Ensure it appears before its first caller in incha.txt.", 2)
end
