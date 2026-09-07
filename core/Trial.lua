local AlertSink    = require("core.AlertSink")
local BossRegistry = require("core.BossRegistry")
local Difficulty   = require("core.Difficulty")
local EventPipeline = require("core.EventPipeline")
local HealthRules  = require("core.HealthRules")
local Log          = require("lib.Log")
local Throttle     = require("lib.Throttle")
local TrialContext = require("core.TrialContext")
local BridgeBase   = require("core.Bridge")

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
            self:onPowerUpdate(powerValue, powerMax, unitTag, powerEffectiveMax)
        end,
        -- Always registered  -  Trial:onCombatState delegates to the active boss
        -- if it has the callback, so no trial-level conditional is needed.
        onCombatState = function(eventCode, inCombat)
            self:onCombatState(inCombat)
        end,
        -- Combat / effect events are registered per ability id and per combat
        -- result by EventPipeline:setActiveBoss, so these are the narrow
        -- entry points rather than one unfiltered dispatcher.  Each filtered
        -- registration admits a disjoint slice; see core/CombatHandler.lua.
        abilityIdsFor = options.abilityIdsFor,
        onCombatEventFiltered = options.onCombatEventFiltered
            and function(...) options.onCombatEventFiltered(self, ...) end or nil,
        onEffectChangedFiltered = options.onEffectChangedFiltered
            and function(...) options.onEffectChangedFiltered(self, ...) end or nil,
        onDiedCombatEvent = options.onDiedCombatEvent
            and function(...) options.onDiedCombatEvent(self, ...) end or nil,
        onLegacyCombatEvent = options.onLegacyCombatEvent
            and function(...) options.onLegacyCombatEvent(self, ...) end or nil,
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
        -- Drop any :after() callbacks the outgoing boss still had in flight,
        -- so they cannot fire against a discarded instance.  Runs after
        -- onLeave so the boss can still schedule teardown work if it needs to.
        if self.activeBoss.cancelPending then
            self.activeBoss:cancelPending()
        end
        self.activeBoss = nil
    end

    self.healthThrottle:reset()

    local _, x, y, z = GetUnitWorldPosition("player")
    local bossClass = self.registry:findAtPosition(x, y, z)

    -- Fallback: name-based detection for trials whose bosses carry a `name`
    -- field instead of (or in addition to) a location bounding box.
    -- Check boss1-boss4 so concurrent-boss encounters (e.g. Ryelaz+Zilyesset)
    -- are detected correctly regardless of which slot the engine assigns first.
    -- Which boss<N> slot the encounter was recognised in.  Health samples for
    -- difficulty detection must come from that unit, not unconditionally from
    -- boss1, or a concurrent-boss encounter reads the wrong health pool.
    local detectedSlot = "boss1"

    if not bossClass then
        for _, slot in ipairs({"boss1", "boss2", "boss3", "boss4"}) do
            if DoesUnitExist(slot) then
                local candidate = self.registry:findByName(GetUnitName(slot))
                if candidate then
                    bossClass = candidate
                    detectedSlot = slot
                    break
                end
            end
        end
    end

    -- Detection failing is silent by design  -  no boss, no panel, no error  -
    -- which is exactly why a wrong name literal or a stale AABB can sit in the
    -- tree unnoticed.  Behind the debug flag, report what the game actually
    -- reported so one run through a trial yields the whole correction list.
    if not bossClass and Log.isEnabled() then
        local present = {}
        for _, slot in ipairs({"boss1", "boss2", "boss3", "boss4"}) do
            if DoesUnitExist(slot) then
                present[#present + 1] = string.format("%s=%q", slot, GetUnitName(slot))
            end
        end
        if #present > 0 then
            Log.warn("%s: no boss matched. Game reports %s",
                self.id, table.concat(present, "  "))
            Log.warn("  registry expects: %s",
                table.concat(self.registry:knownNames(), " | "))
            Log.warn("  player at %.0f / %.0f / %.0f (no AABB contains this)",
                x or 0, y or 0, z or 0)
        end
    end

    -- Blank the panel before either branch runs.  The outgoing boss owned
    -- whatever is currently on screen, and the incoming one only rewrites the
    -- info slots it actually uses  -  so without this, walking straight from
    -- one boss to the next leaves the previous boss's countdown lines up
    -- until (or unless) the new boss happens to write those same slots.
    self.alerts:clear()

    if bossClass then
        -- Create a fresh instance  -  no state carried over from previous pulls.
        local instance = bossClass.new()
        self.activeBoss = instance
        self.context:setBoss(instance)

        -- First sample.  This can legitimately read 0 on the frame the boss
        -- appears, in which case detectDifficulty returns NONE and
        -- onPowerUpdate re-resolves from the next real health tick.
        self.bossSlot = detectedSlot
        local _, _, effectiveMax = GetUnitPower(detectedSlot, POWERTYPE_HEALTH)
        self.context:setDifficulty(self.registry:detectDifficulty(bossClass, effectiveMax))

        -- Narrow the combat / effect event registrations to the abilities and
        -- results this boss can actually act on.  Done before onEnter so a
        -- boss that fires alerts from onEnter is already wired up.
        self.pipeline:setActiveBoss(instance)

        if instance.onEnter then
            instance:onEnter(self.context, self.alerts)
        end

        self.bridge.onBossEnter(instance, self.context)
    else
        self.context:setBoss(nil)
        self.context:setDifficulty(Difficulty.NONE)
        self.pipeline:setActiveBoss(nil)

        self.bridge.onBossExit()
    end
end

function Trial:onPowerUpdate(powerValue, powerMax, unitTag, powerEffectiveMax)
    if not self.enabled then
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

    -- Second chance at difficulty detection.  The sample taken in
    -- onBossesChanged can read 0 on the frame the boss appears, which leaves
    -- difficulty at NONE; this event carries an authoritative effective-max
    -- for free, so re-resolve until it is known.  Restricted to the slot the
    -- encounter was recognised in, since the POWER_UPDATE filter admits every
    -- boss<N> tag and a concurrent boss has a different health pool.
    --
    -- context.isHM gates real mechanics (Xalvakka's jump timer, Taleria's
    -- behemoth line), so getting this right matters beyond the header text.
    if self.context.difficulty == Difficulty.NONE
    and (unitTag == nil or unitTag == self.bossSlot) then
        local sample = powerEffectiveMax
        if not sample or sample <= 0 then sample = powerMax end
        local resolved = self.registry:detectDifficulty(boss, sample)
        if resolved ~= Difficulty.NONE then
            self.context:setDifficulty(resolved)
            Log.debug("%s: difficulty resolved to %s (max hp %d, threshold %s)",
                self.id,
                resolved == Difficulty.HARDMODE and "HARDMODE" or "NORMAL",
                sample, tostring(boss.hmHealthThreshold))
        end
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
    if not inCombat and boss then
        -- Cancel in-flight :after() callbacks first, so a delayed alert from
        -- the pull that just ended cannot fire into the reset.  onWipe runs
        -- afterwards and may schedule new ones.
        if boss.cancelPending then
            boss:cancelPending()
        end
        if boss.onWipe then
            boss:onWipe(self.context, self.alerts)
        end
    end
end

function Trial:enable()
    if self.enabled then
        return
    end

    self.enabled = true

    self.bridge.onEnable()

    self.pipeline:enable()
    self:onBossesChanged(true)
end

function Trial:disable()
    if not self.enabled then
        return
    end

    self.pipeline:disable()

    if self.activeBoss then
        if self.activeBoss.onLeave then
            self.activeBoss:onLeave(self.context)
        end
        if self.activeBoss.cancelPending then
            self.activeBoss:cancelPending()
        end
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
