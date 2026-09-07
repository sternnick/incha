--- external-api/PositionIcons.lua  -  dependency-injected gateway for
--- OdySupportIcons world-space position-icon calls.
---
--- All methods are silent no-ops until the OSI global is available, either via
--- configure() or (lazily) on first use.  The lazy path handles addons that
--- publish in EVENT_PLAYER_ACTIVATED rather than EVENT_ADD_ON_LOADED.
---
--- Bootstrap (incha.lua OnAddOnLoaded):
---   require("external-api.PositionIcons").configure(OSI)
---
--- Usage:
---   local PositionIcons = require("external-api.PositionIcons")
---   local Colors        = require("core.Colors")
---   local handle = PositionIcons.create(x, y, z, texture, size, Colors.TEAL)
---   PositionIcons.discard(handle)
---   PositionIcons.update(handle, texture, Colors.AMBER)
---   PositionIcons.discardAll(iconTable)
---   if PositionIcons.isAvailable() then ... end

local ColorDefs = require("external-api.ColorDefs")
local PositionIcons = {}

local _impl = nil

--- Inject the real OSI global (or a test stub).
--- Called once from OnAddOnLoaded after ESO globals are available.
function PositionIcons.configure(impl)
    _impl = impl
end

--- Fall back to the OSI ESO global when configure() was called before OSI
--- published itself (e.g. if it publishes in EVENT_PLAYER_ACTIVATED rather than
--- EVENT_ADD_ON_LOADED).
local function getImpl()
    if not _impl then _impl = OSI end
    return _impl
end

-- ── O(1) RGB lookup (built once at load time) ─────────────────────────────

local _rgb = ColorDefs.build(function(r, g, b)
    return { r, g, b }
end)

-- ── API ───────────────────────────────────────────────────────────────────

--- Returns true when the implementation is configured and supports position icons.
function PositionIcons.isAvailable()
    local i = getImpl()
    return i ~= nil and i.CreatePositionIcon ~= nil
end

--- Create a world-space position icon.  Returns an icon handle, or nil when
--- not configured.
--- @param color string  color name (Colors.*)
function PositionIcons.create(x, y, z, texture, size, color)
    if not PositionIcons.isAvailable() then return nil end
    return _impl.CreatePositionIcon(x, y, z, texture, size, _rgb[color])
end

--- Discard a single icon handle.  Silent no-op on nil handle or when not
--- configured.
function PositionIcons.discard(handle)
    if getImpl() and handle and _impl.DiscardPositionIcon then
        _impl.DiscardPositionIcon(handle)
    end
end

--- Update the texture and color of an existing icon.
--- Silent no-op on nil handle or when not configured.
--- @param color string  color name (Colors.*)
function PositionIcons.update(handle, texture, color)
    if getImpl() and handle and _impl.UpdateIconData then
        _impl.UpdateIconData(handle, texture, nil, _rgb[color])
    end
end

--- Discard all icon handles stored in a table.
--- Silent no-op when not configured or iconTable is falsy.
function PositionIcons.discardAll(iconTable)
    if not (iconTable and getImpl() and _impl.DiscardPositionIcon) then return end
    for _, icon in pairs(iconTable) do _impl.DiscardPositionIcon(icon) end
end

package.loaded["external-api.PositionIcons"] = PositionIcons
return PositionIcons
