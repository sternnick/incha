local AlertSink = {}
AlertSink.__index = AlertSink

function AlertSink.new(handlers)
    return setmetatable({
        handlers = handlers or {},
    }, AlertSink)
end

-- File-local: internal dispatch only.  Not part of the public API.
-- text is passed straight through to the handler (no payload table wrapper)
-- since this runs on the boss-health hot path and every allocation there
-- adds up across a multi-second fight.
local function emit(self, eventType, text)
    local handler = self.handlers[eventType]
    if handler then
        handler(text)
    end
end


-- setRow(n, name, eta)  -  structured tracker row.
-- name: display label string (may contain |c colour codes).
-- eta:  remaining seconds as a number, or nil for a static / no-timer row.
-- Handlers receive (n, name, eta) directly.
function AlertSink:setRow(n, name, eta)
    local handler = self.handlers.setRow
    if handler then
        handler(n, name, eta)
    end
end

-- clearRow(n)  -  blank tracker row n.
function AlertSink:clearRow(n)
    local handler = self.handlers.clearRow
    if handler then
        handler(n)
    end
end

function AlertSink:showAction(text)
    emit(self, "action", text)
end

function AlertSink:showHeader(text)
    emit(self, "header", text)
end

-- Named method so callers never need to know the "hideAction" event string.
-- A typo in the channel name previously silently no-opped; now a wrong
-- method name produces a Lua error at call time.
function AlertSink:hideAction()
    emit(self, "hideAction")
end

function AlertSink:clear()
    emit(self, "clear")
end

package.loaded["core.AlertSink"] = AlertSink
return AlertSink
