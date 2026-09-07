--- DebuffTracker  -  timed debuff window with optional player-name tracking.
---
--- Wraps a Timer and an optional display name so callers do not have to
--- manage a raw timestamp and a name field separately.
---
--- Typical usage:
---   local dt = DebuffTracker.new(duration)   -- duration in seconds
---
---   -- On EFFECT_GAINED:
---   dt:start(GetUnitDisplayName(unitTag) or unitName)
---
---   -- On EFFECT_FADED (optional; the timer auto-expires otherwise):
---   dt:clear()
---
---   -- In display loop:
---   local T = dt:remaining()    -- seconds left (0 when idle or expired)
---   if T > 0 then
---       local name = dt:playerName() or "?"
---       alerts:setRow(n, "Debuff on " .. name, T)
---   end

local Timer = require("lib.Timer")

local DebuffTracker = {}
DebuffTracker.__index = DebuffTracker

--- Create a tracker for debuffs of the given duration (seconds).
function DebuffTracker.new(duration)
    return setmetatable({
        _timer  = Timer.new(duration),
        _player = nil,
    }, DebuffTracker)
end

--- Start (or restart) the debuff window; records the player display name.
--- @param playerName string|nil   GetUnitDisplayName result, or nil if irrelevant.
function DebuffTracker:start(playerName)
    self._timer:reset()
    self._player = playerName
end

--- Clear the tracker early (e.g. on EFFECT_FADED).
--- Safe to call when already idle.
function DebuffTracker:clear()
    self._timer:clear()
    self._player = nil
end

--- Seconds remaining in the debuff window.  Returns 0 when idle or expired.
function DebuffTracker:remaining()
    return self._timer:remaining()
end

--- True while the debuff window is active and has not yet expired.
function DebuffTracker:isActive()
    return self._timer:isActive()
end

--- Display name of the tracked player, or nil when cleared.
function DebuffTracker:playerName()
    return self._player
end

package.loaded["lib.DebuffTracker"] = DebuffTracker
return DebuffTracker
