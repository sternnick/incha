local AlertSink    = require("core.AlertSink")
local BossRegistry = require("core.BossRegistry")
local Difficulty   = require("core.Difficulty")
local EventPipeline = require("core.EventPipeline")
local HealthRules  = require("core.HealthRules")
local Throttle     = require("lib.Throttle")
local TrialContext = require("core.TrialContext")
local BridgeBase   = require("core.Bridge")

-- Unit tags occupied by trial bosses (nameplate slots, engine order).
local BOSS_SLOTS   = { "boss1", "boss2", "boss3", "boss4" }

local Trial = {}
Trial.__index = Trial

--- Boss interface  -  all methods are optional unless marked REQUIRED.
--- Each boss is a table with __index pointing at the class (prototype).
--- Trial checks for each method before calling; missing methods are no-ops.
---
---   REQUIRED: key (string)           -  unique identifier, matches BossRegistry key
---   REQUIRED: name (string)          -  display name returned by GetUnitName("bossN"),
---                                     OR nameAliases table listing all unit names
---   REQUIRED: new() -> instance       -  returns a fresh table, NO carried-over state
---
---   onLeave(context)                 -  full teardown on zone exit: stop bars,
---                                     discard position icons, unregister events
---   onEnter(context, alerts)         -  boss became active (called after context:setBoss)
---   onCombatState(ctx, inCombat, alerts)
---   onWipe(ctx, alerts)              -  soft reset on wipe while still in zone:
---                                     stop active bars, clear per-pull flags and
---                                     OSI mechanic icons; keep long-lived position
---                                     icons so they survive into the next pull
---   onCombatEvent(ctx, alerts, result, abilityId,
---                 unitTag, sourceUnitTag, sourceUnitId, unitId,
---                 sourceUnitName, unitName)
---   onEffectChanged(ctx, alerts, changeType, abilityId,
---                   unitTag, unitId, unitName)
---   onUpdate(ctx, alerts)            -  200 ms tick while boss is active
---   onPowerUpdate(ctx, healthPct, alerts)
---
---   hmHealthThreshold (number)       -  max HP above which difficulty = HARDMODE
---   healthRules (table)              -  HealthRules table for phase-change callouts
---   hideActionWhenNoRule (boolean)   -  clear action slot when no health rule fires
---   location (Location)              -  AABB for position-based boss detection
---   stage (number)                   -  initial context.stage value (default 1)
---
function Trial.create(options)
    local self = setmetatable({
        id = options.id,
        zoneId = options.zoneId,
        name = options.name or options.id,
        eventPrefix = options.eventPrefix or (ADDON_PREFIX .. options.id),
        -- Default to BridgeBase so every hook can be called unconditionally.
        bridge = options.bridge or BridgeBase,
        registry = BossRegistry.new(options.bosses),
        context = TrialContext.new(options.id),
        alerts = AlertSink.new(options.alerts),
        enabled = false,
        -- The live boss instance for the current encounter; nil between bosses.
        -- Always a fresh object created by the boss class's new() factory  - 
        -- never the class prototype itself.
        activeBoss = nil,
        -- Only gates the cosmetic health-rule text (and the AlertSink calls
        -- it triggers), not boss:onPowerUpdate itself, so mechanic timing
        -- logic still sees every real tick. 1% granularity is safe since
        -- healthRules windows are several points wide.
        healthThrottle = Throttle.new(1),
    }, Trial)

    self.pipeline = EventPipeline.new(self.eventPrefix, {
        onBossesChanged = function(eventCode, forceReset)
            self:onBossesChanged(forceReset)
        end,
        onPowerUpdate = function(eventCode, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)
            self:onPowerUpdate(unitTag, powerValue, powerMax)
        end,
        -- Always registered  -  Trial:onCombatState delegates to the active boss
        -- if it has the callback, so no trial-level conditional is needed.
        onCombatState = function(eventCode, inCombat)
            self:onCombatState(inCombat)
        end,
        onCombatEvent = options.onCombatEvent and function(...)
            options.onCombatEvent(self, ...)
        end or nil,
        onEffectChanged = options.onEffectChanged and function(...)
            options.onEffectChanged(self, ...)
        end or nil,
        -- 200ms timer-display loop.  Calls boss:onUpdate(context, alerts) when
        -- a boss is active.  No-op otherwise, so the loop is always registered
        -- without wasting ticks between encounters.
        onUpdate = function()
            self:onUpdate()
        end,
        updateInterval = 200,
    })

    return self
end

function Trial:getActiveBoss()
    return self.activeBoss
end

function Trial:onBossesChanged(forceReset)
    if not self.enabled then
        return
    end

    -- Give the outgoing boss a chance to clean up (stop CA bars, unregister events).
    if self.activeBoss then
        if self.activeBoss.onLeave then
            self.activeBoss:onLeave(self.context)
        end
        self.activeBoss = nil
    end

    self.healthThrottle:reset()

    local _, x, y, z = GetUnitWorldPosition("player")
    local bossClass = self.registry:findAtPosition(x, y, z)
    local bossSlot  = nil   -- which boss1..boss4 tag the match came from

    -- Fallback: name-based detection for trials whose bosses carry a `name`
    -- field instead of (or in addition to) a location bounding box.
    -- Check boss1-boss4 so concurrent-boss encounters (e.g. Ryelaz+Zilyesset)
    -- are detected correctly regardless of which slot the engine assigns first.
    if not bossClass then
        for _, slot in ipairs(BOSS_SLOTS) do
            if DoesUnitExist(slot) then
                local candidate = self.registry:findByName(GetUnitName(slot))
                if candidate then
                    bossClass = candidate
                    bossSlot  = slot
                    break
                end
            end
        end
    else
        -- Position match: resolve which slot this boss actually occupies so the
        -- health poll and the power-update guard use the same unit.
        for _, slot in ipairs(BOSS_SLOTS) do
            if DoesUnitExist(slot)
               and self.registry:findByName(GetUnitName(slot)) == bossClass then
                bossSlot = slot
                break
            end
        end
    end

    if bossClass then
        -- Create a fresh instance  -  no state carried over from previous pulls.
        local instance = bossClass.new()
        self.activeBoss = instance
        self.context:setBoss(instance, bossSlot)

        -- Info/action lines from the previous boss must not survive the
        -- transition: on a boss-to-boss change nothing else clears them, so the
        -- panel keeps the dead boss's timers until the new boss overwrites each
        -- line - or forever, for lines the new boss never writes.
        self.alerts:clear()

        local _, _, effectiveMax =
            GetUnitPower(bossSlot or "boss1", POWERTYPE_HEALTH)
        self.context:setDifficulty(self.registry:detectDifficulty(bossClass, effectiveMax))

        if instance.onEnter then
            instance:onEnter(self.context, self.alerts)
        end

        self.bridge.onBossEnter(instance, self.context)
    else
        self.context:setBoss(nil)
        self.context:setDifficulty(Difficulty.NONE)
        self.alerts:clear()

        self.bridge.onBossExit()
    end
end

function Trial:onPowerUpdate(unitTag, powerValue, powerMax)
    if not self.enabled then
        return
    end

    -- Only the tracked boss drives the overlay. Concurrent encounters put two
    -- units into boss slots at once (Ryelaz + Zilyesset in LC, Lylanar +
    -- Turlassil in DSR); without this guard the wrong unit's percentage feeds
    -- health rules and every timer keyed on a % window.
    local tracked = self.context.bossUnitTag
    if tracked and unitTag ~= tracked then
        return
    end
    -- powerMax can be 0 briefly during boss transitions; skip the tick to
    -- avoid a divide-by-zero producing nan in health rules.
    if powerMax == 0 then
        return
    end

    local boss = self:getActiveBoss()
    if not boss then
        return
    end

    local healthPercent = powerValue / powerMax * 100
    self.context.healthPercent = healthPercent

    -- Boss mechanic callbacks run on every real tick regardless of
    -- throttling below - mechanic timing shouldn't depend on UI granularity.
    if boss.onPowerUpdate then
        boss:onPowerUpdate(self.context, healthPercent, self.alerts)
    end

    -- The health-rule text/alert display only needs to react when the
    -- rounded percent actually changes, not on every raw power-update tick
    -- (which can fire many times per second). This avoids re-running
    -- rule evaluation and re-touching the UI when nothing visible changed.
    if self.healthThrottle:shouldUpdate(healthPercent) then
        local id, text = HealthRules.evaluate(boss.healthRules, healthPercent, self.context, boss)
        if id then
            self.alerts:showAction(text)
        elseif boss.hideActionWhenNoRule then
            self.alerts:hideAction()
        end
    end

    -- Use the context flag maintained by onCombatState rather than calling the
    -- ESO API on every tick  -  avoids one C->Lua round-trip per power update.
    if not self.context.inCombat then
        self.bridge.checkHardmode(self.context)
    end
end

function Trial:onUpdate()
    if not self.enabled then return end
    local boss = self:getActiveBoss()
    if not boss or not boss.onUpdate then return end
    boss:onUpdate(self.context, self.alerts)
end

function Trial:onCombatState(inCombat)
    self.context.inCombat = inCombat

    local boss = self:getActiveBoss()
    if boss and boss.onCombatState then
        boss:onCombatState(self.context, inCombat, self.alerts)
    end

    -- On wipe (inCombat = false, boss still active), give the boss a chance
    -- to soft-reset without a full zone-exit teardown: stop active cast bars,
    -- clear per-pull flags, hide position icons  -  but keep long-lived icons
    -- created in onEnter so they're still visible at the start of the next pull.
    if not inCombat and boss and boss.onWipe then
        boss:onWipe(self.context, self.alerts)
    end
end

function Trial:enable()
    if self.enabled then
        return
    end

    self.enabled = true

    -- 16 of 25 boss modules still carry a placeholder hmHealthThreshold and 42
    -- context.isHM gates depend on it: a wrong boundary silently shows or hides
    -- whole mechanic displays. Say so once per boss per session so the value
    -- gets measured (see /incha hp) instead of guessed.
    if not self.hmThresholdWarned then
        self.hmThresholdWarned = {}
    end
    for _, boss in ipairs(self.registry.bosses) do
        local th = boss.hmHealthThreshold
        if (th == nil or th == math.huge or th == 100000001)
           and not self.hmThresholdWarned[boss.key] then
            self.hmThresholdWarned[boss.key] = true
            require("lib.Log").warn(
                "%s/%s: hmHealthThreshold = %s - hardmode detection is a guess. "
                .. "Pull the boss once in normal and once in hardmode, run "
                .. "/incha hp for each, and set the threshold between them.",
                self.id, boss.key, tostring(th))
        end
    end

    self.bridge.onEnable()

    self.pipeline:enable()
    self:onBossesChanged(true)
end

function Trial:disable()
    if not self.enabled then
        return
    end

    self.pipeline:disable()

    if self.activeBoss and self.activeBoss.onLeave then
        self.activeBoss:onLeave(self.context)
    end
    self.activeBoss = nil

    self.context:setBoss(nil)
    self.context:setDifficulty(Difficulty.NONE)
    self.healthThrottle:reset()
    self.alerts:clear()

    self.bridge.onDisable()

    self.enabled = false
end

package.loaded["core.Trial"] = Trial
return Trial
