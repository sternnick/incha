--- Shared map / proximity utilities.

local MapUtils = {}

--- Returns true when `unitTag` is within `threshold` world-units of the local player.
--- Uses GetUnitWorldPosition for accuracy; avoids the stale-map bug from
--- SetMapToPlayerLocation() + GetMapPlayerPosition().
---
--- Threshold values are in ESO world units (same scale as GetUnitWorldPosition).
--- Existing call-sites that relied on the old normalised * 1000 scale must be
--- recalibrated in-game (see GitHub issues #29, #30, #31).
function MapUtils.isGroupMemberNearby(unitTag, threshold)
    local _, x1, _, z1 = GetUnitWorldPosition("player")
    local _, x2, _, z2 = GetUnitWorldPosition(unitTag)
    if not x1 or not x2 then return false end
    return math.sqrt((x1 - x2)^2 + (z1 - z2)^2) <= threshold
end

package.loaded["lib.MapUtils"] = MapUtils
return MapUtils
