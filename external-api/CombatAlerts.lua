--- external-api/CombatAlerts.lua  -  dependency-injected gateway for CombatAlerts.
---
--- Replaces the raw AlertCast / CastAlertsStart pass-throughs with typed
--- methods that accept a colour name (Colors.*) and build the CA table
--- internally.  Every lookup table is pre-computed once at load time (O(1)
--- per call).
---
--- Bootstrap (incha.lua OnAddOnLoaded):
---   require("external-api.CombatAlerts").configure(CombatAlerts)
---
--- Usage (boss / common files):
---   local CA     = require("external-api.CombatAlerts")
---   local Colors = require("core.Colors")
---
---   CA.cast(abilityId, srcName, dur, Colors.FIRE)       -- auto-detect timing
---   CA.melee(abilityId, srcName, dur, Colors.FIRE)      -- melee dodge window
---   CA.ranged(abilityId, srcName, dur, Colors.ICE)      -- ranged dodge window
---   CA.interrupt(abilityId, srcName, dur, Colors.ICE)   -- interruptible, auto
---   CA.interrupt_melee(id, srcName, dur, Colors.ICE)    -- interruptible, melee
---   CA.bar(abilityId, label, dur, pauseDur, Colors.RED) -- castAlertsStart bar
---   CA.alert(id, label, color, sound, duration)         -- instant alert
---   CA.castAlertsStop(id)                               -- stop a cast bar
---
--- CA table layout (for reference — callers never construct these):
---   { timing, dodge_text, interruptible, bg_rgba, fg_rgba }
---   timing: -1 = auto-detect from GetAbilityRange
---           -2 = melee (full dodge window)
---           -3 = ranged (0.8 × dodge window)

local ColorDefs = require("external-api.ColorDefs")
local CA = {}

local _impl = nil

--- Inject the real CombatAlerts global (or a test stub).
--- Called once from OnAddOnLoaded after ESO globals are available.
function CA.configure(impl)
    _impl = impl
end

--- Fall back to the CombatAlerts ESO global when configure() was called before
--- CombatAlerts published itself (e.g. if it publishes in EVENT_PLAYER_ACTIVATED
--- rather than EVENT_ADD_ON_LOADED).  Caches the result so the lookup is
--- one-time.
local function getImpl()
    if not _impl then _impl = CombatAlerts end
    return _impl
end

-- ── O(1) lookup tables (built once at load time) ──────────────────────────

local function _caTable(timing, interruptible)
    return ColorDefs.build(function(r, g, b)
        return { timing, 0, interruptible, { r, g, b, 0.4 }, { r, g, b, 0.8 } }
    end)
end

local _cast     = _caTable(-1, false)   -- auto-detect timing, dodge
local _melee    = _caTable(-2, false)   -- melee dodge window
local _ranged   = _caTable(-3, false)   -- ranged dodge window
local _interrupt      = _caTable(-1, true)  -- interruptible, auto
local _interrupt_melee = _caTable(-2, true) -- interruptible, melee

local _bar = ColorDefs.build(function(r, g, b)
    return { r, g, b, 0.4 }   -- default alpha; callers may override
end)

-- ── Cast-bar methods ───────────────────────────────────────────────────────

--- Show a cast alert: CA auto-detects timing from the ability's range.
--- action: optional action table { dur, text, r, g, b, a, sound } passed through.
function CA.cast(abilityId, srcName, dur, color, action)
    if getImpl() then return _impl.AlertCast(abilityId, srcName, dur, _cast[color], action) end
end

--- Show a cast alert with explicit melee timing (-2 = full dodge window).
--- action: optional action table passed through unchanged.
function CA.melee(abilityId, srcName, dur, color, action)
    if getImpl() then return _impl.AlertCast(abilityId, srcName, dur, _melee[color], action) end
end

--- Show a cast alert with explicit ranged timing (-3 = 0.8× dodge window).
--- action: optional action table passed through unchanged.
function CA.ranged(abilityId, srcName, dur, color, action)
    if getImpl() then return _impl.AlertCast(abilityId, srcName, dur, _ranged[color], action) end
end

--- Show an interruptible cast bar (auto-detect timing).
--- action: optional action table passed through unchanged.
function CA.interrupt(abilityId, srcName, dur, color, action)
    if getImpl() then return _impl.AlertCast(abilityId, srcName, dur, _interrupt[color], action) end
end

--- Show an interruptible cast bar with melee timing.
--- action: optional action table passed through unchanged.
function CA.interrupt_melee(abilityId, srcName, dur, color, action)
    if getImpl() then return _impl.AlertCast(abilityId, srcName, dur, _interrupt_melee[color], action) end
end

--- CastAlertsStart — a freestanding progress bar (not tied to an ability cast).
--- alpha overrides the default bar opacity (0.4).
function CA.bar(abilityId, caption, dur, durMax, color, alpha, action)
    if not getImpl() then return end
    local c = _bar[color]
    local rgba = alpha and { c[1], c[2], c[3], alpha } or c
    return _impl.CastAlertsStart(abilityId, caption, dur, durMax, rgba, action)
end

--- Stop a cast bar by its cast ID.
--- Guards against nil id — callers can pass the stored id directly without
--- checking it first.
function CA.castAlertsStop(id)
    if getImpl() and id then _impl.CastAlertsStop(id) end
end

-- ── Instant alert ─────────────────────────────────────────────────────────

function CA.alert(...)
    if getImpl() then return _impl.Alert(...) end
end

-- ── Screen-edge border ────────────────────────────────────────────────────

--- Show or hide the screen-edge danger border.
--- @param active boolean       true = show, false = hide
--- @param dur    number        duration in ms
--- @param color  table|string  {r, g, b, a} colour table, or a named-colour
---                             string accepted by CombatAlerts
function CA.border(active, dur, color)
    if getImpl() then _impl.AlertBorder(active, dur, color) end
end

package.loaded["external-api.CombatAlerts"] = CA
return CA
