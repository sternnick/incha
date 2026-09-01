local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- -- Ability ID sets for mini-boss detection -------------------------------
-- Any of these firing marks that mini as active (detects +1/+2/+3 variant).
local SIRO_IDS = {
    [104755]=true, -- HA
    [106601]=true, -- Jump
    [104902]=true, -- Banner
    [103531]=true, -- Flare
    [110431]=true, -- Flare (execute)
    [105765]=true, -- Dark Talons
}
local RELE_IDS = {
    [105780]=true, -- HA
    [105796]=true, -- Flux Burst jump
    [105380]=true, -- Direct Current (interrupt)
    [106614]=true, -- Jolt
    [103555]=true, -- Overload incoming
    [87346] =true, -- Overload active
}
local GALE_IDS = {
    [106375]=true, -- HA
    [106682]=true, -- Teleport jump
    [106405]=true, -- Glacial Spikes (interrupt)
    [106378]=true, -- Donut
    [105151]=true, -- Hoarfrost cast
    [110466]=true, -- Hoarfrost cast (execute)
    [103695]=true, -- Hoarfrost debuff
    [110516]=true, -- Hoarfrost debuff (execute)
    [106374]=true, -- Chilling Comet
    [106367]=true, -- Chilling Comet variant
}

-- -- Ability IDs (from HowToCloudrest / CrutchAlerts) ---------------------

-- -- Siroria ---------------------------------------------------------------
local SIRO_HA          = 104755  -- Heavy Attack → block/dodge
local SIRO_JUMP        = 106601  -- Jump - 23 s CD
local SIRO_BANNER      = 104902  -- Banner skill - 45 s CD
local SIRO_DARK_TALONS = 105765  -- Root on player
local SIRO_FLARE       = 103531  -- Roaring Flare → target name, 6.6 s window
local SIRO_FLARE_EXEC  = 110431  -- Roaring Flare execute variant

-- -- Relequen --------------------------------------------------------------
local RELE_HA          = 105780  -- Heavy Attack
local RELE_JUMP        = 105796  -- Flux Burst jump - 19 s CD
local RELE_DIRECT_CURR = 105380  -- Direct Current channel → INTERRUPT! 20 s CD
local RELE_JOLT        = 106614  -- Jolt cone - 15 s CD
local RELE_OVERLOAD_1  = 103555  -- Voltaic Overload incoming (bar-swap warning)
local RELE_OVERLOAD_2  = 87346   -- Voltaic Overload active on player

-- -- Galenwe ---------------------------------------------------------------
local GALE_HA          = 106375  -- Heavy Attack
local GALE_JUMP        = 106682  -- Teleport jump - 19 s CD
local GALE_GLACIAL     = 106405  -- Glacial Spikes channel → INTERRUPT! 22 s CD
local GALE_DONUT       = 106378  -- Donut AoE - 22 s CD
local GALE_HOARFROST_C = 105151  -- Hoarfrost cast (ground AoE incoming)
local GALE_HOARFROST_C2= 110466  -- Hoarfrost cast execute variant
local GALE_HOARFROST   = 103695  -- Hoarfrost debuff on player - 6 s drop window
local GALE_HOARFROST_2 = 110516  -- Hoarfrost debuff execute variant
local GALE_HOARFROST_SY= 103697  -- Hoarfrost synergy used (drop frost now!)
local GALE_HOARFROST_S2= 110525  -- Hoarfrost synergy execute variant
local GALE_HOARFROST_AO= 103765  -- Hoarfrost AoE on ground
local GALE_COMET       = 106374  -- Chilling Comet on player - 4 s window
local GALE_COMET_2     = 106367  -- Chilling Comet variant

-- -- Environment / mini shared ---------------------------------------------
local RAZOR_THORNS     = 106656  -- Creeper root on player

-- -- Portal mechanics ------------------------------------------------------
local PORTAL_OPEN      = 103946  -- Portal spawns / opens (75 s window)
local PORTAL_CLOSE_1   = 104057  -- Remove Shadow Realm (normal close)
local PORTAL_CLOSE_2   = 104792  -- Portal close (PC win)
local PORTAL_RESET     = 105890  -- Z'Maja re-engage - reset portal group to 1
local PLAYER_EXIT      = 105218  -- Player exits shadow realm (side-boss variant)

-- -- Z'Maja abilities ------------------------------------------------------
local ZMAJA_JUMP       = 104564  -- BEGIN → "Z'Maja jumping!"
local ZMAJA_HIDE_JUMP  = 104452  -- BEGIN → Z'Maja retreats to shadow
local CRUSHING_DARK_1  = 105152  -- BEGIN → Kite! Crushing Darkness
local CRUSHING_DARK_2  = 105172
local CRUSHING_DARK_3  = 105239
local SHADOW_SPLASH    = 105123  -- BEGIN → Shadow Splash! Interrupt!
local BANEFUL_MARK     = 107196  -- BEGIN (execute) → Baneful Mark!
local ZMAJA_SHACKLE    = 107490  -- EFFECT_GAINED -> mini shackled / dies
local ZMAJA_RESET_PORT = 107478  -- Z'Maja portal-phase reset (all portals close)

-- -- Malevolent Cores / misc -----------------------------------------------
local CORE_EXPOSED     = 103980
local CORE_PICKED_UP   = 103989
local CORE_MISSED      = 110202
local BEAD_TICK        = 105339
local BEAD_SPAWN       = 105363
local BEAD_CHARGE      = 105373
local OLORIME_SPEAR    = 104018
local BREAK_AMULET     = 106023
local MALICIOUS_SPHERE = 105291

-- -- Timer durations (seconds) ---------------------------------------------
local SIRO_JUMP_CD     = 23
local SIRO_BANNER_CD   = 45
local RELE_JUMP_CD     = 19
local RELE_BASH_CD     = 20
local RELE_JOLT_CD     = 15
local GALE_JUMP_CD     = 19
local GALE_BASH_CD     = 22
local GALE_DONUT_CD    = 22
local HOARFROST_DROP   = 6     -- seconds until Hoarfrost is droppable
local FLARE_WINDOW     = 7     -- Roaring Flare alert window (seconds)
local COMET_WINDOW     = 4     -- Chilling Comet window (seconds)
local PORTAL_OPEN_DUR  = 75    -- portal stays open ~75 s
local PORTAL_NEXT_CD   = 46    -- seconds until next portal after close

-- -- CA colour palettes ----------------------------------------------------
local COL_SIRO  = { -3, 0, false, { 1, 0.27, 0, 0.4 },    { 1, 0.27, 0, 0.8 } }    -- orange (fire)
local COL_RELE  = { -3, 0, false, { 0.2, 0.6, 1, 0.4 },   { 0.2, 0.6, 1, 0.8 } }  -- blue (lightning)
local COL_GALE  = { -3, 0, false, { 0, 0.87, 0.87, 0.4 }, { 0, 0.87, 0.87, 0.8 } } -- cyan (frost)
local COL_ZMAJA = { -3, 0, false, { 0.6, 0, 0.8, 0.4 },   { 0.6, 0, 0.8, 0.8 } }   -- purple (shadow)

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DARK_DUR = 6000   -- CrushingDarkness: empirical
local FALLBACK_HA_DUR   = 1500   -- Siroria/Relequen/Galenwe HeavyAttack: empirical

local ZmajaEncounter = {}
ZmajaEncounter.__index = ZmajaEncounter
setmetatable(ZmajaEncounter, {__index = BossBase})  -- inherit cleanupAlertList, onDied

ZmajaEncounter.key               = "zmaja"
ZmajaEncounter.nameAliases       = { "Z'Maja" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
-- To calibrate: pull on vet HM, run /script d(GetUnitPower("boss1", POWERTYPE_HEALTH))
ZmajaEncounter.hmHealthThreshold = math.huge
-- location: placeholder - Cloudrest arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

ZmajaEncounter.stateSchema = {
    -- Siroria
    siroJumpTimer   = function() return Timer.new(SIRO_JUMP_CD) end,
    siroBannerTimer = function() return Timer.new(SIRO_BANNER_CD) end,
    -- Relequen
    releJumpTimer   = function() return Timer.new(RELE_JUMP_CD) end,
    releBashTimer   = function() return Timer.new(RELE_BASH_CD) end,
    releJoltTimer   = function() return Timer.new(RELE_JOLT_CD) end,
    -- Galenwe
    galeJumpTimer   = function() return Timer.new(GALE_JUMP_CD) end,
    galeBashTimer   = function() return Timer.new(GALE_BASH_CD) end,
    galeDonutTimer  = function() return Timer.new(GALE_DONUT_CD) end,
    -- Portal
    portalTimer     = function() return Timer.new(PORTAL_OPEN_DUR) end,
    portalNextTimer = function() return Timer.new(PORTAL_NEXT_CD) end,
    -- Mini-boss presence
    siroActive      = false,
    releActive      = false,
    galeActive      = false,
    -- Portal / Z'Maja state
    portalGroup     = 0,
    portalActive    = false,
    executePhase    = false,
    spearCount      = 0,
    alertList       = function() return {} end,
    -- Nullable string: "Core MISSED!" while a missed core is in play; false otherwise.
    coreAlert       = false,
}

function ZmajaEncounter.new()
    return BossBase.fromSchema(ZmajaEncounter)
end

-- -- Lifecycle -------------------------------------------------------------
function ZmajaEncounter:onLeave(context)
    self:cleanupAlertList()
end

-- -- Handlers ------------------------------------------------------------
-- (Z'Maja has no shared common module; no per-unit DIED cleanup needed.)

-- Mini-boss shackle: Z'Maja removes a mini from the fight.
local function handleShackle(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if unitName and unitName:find("Siroria") then
        self.siroActive = false
        self.siroJumpTimer:clear(); self.siroBannerTimer:clear()
    elseif unitName and unitName:find("Relequen") then
        self.releActive = false
        self.releJumpTimer:clear(); self.releBashTimer:clear(); self.releJoltTimer:clear()
    elseif unitName and unitName:find("Galenwe") then
        self.galeActive = false
        self.galeJumpTimer:clear(); self.galeBashTimer:clear(); self.galeDonutTimer:clear()
    end
end

-- Roaring Flare: shared handler for base and execute variant.
local function handleSiroFlare(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Flare → " .. target)
    local dur = CastDur.get(abilityId, math.floor(FLARE_WINDOW * 1000))
    local cid = CA.alertCast(abilityId, "Flare → " .. target, dur, COL_SIRO)
    if cid and unitId then self.alertList[unitId] = cid end
end

-- Hoarfrost: EFFECT_GAINED -> OSI icon + alert; EFFECT_FADED -> remove icon.
local function handleGaleHoarfrost(self, context, alerts, result, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    if not self.galeActive then self.galeActive = true end
    if result == ACTION_RESULT_EFFECT_GAINED then
        local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
        if OSI and dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
            local sz = OSI.GetIconSize and (2 * OSI.GetIconSize()) or nil
            OSI.SetMechanicIconForUnit(dname, GetAbilityIcon(abilityId), sz,
                                       {0, 0.87, 0.87}, nil, nil)
        end
        if IsUnitPlayer(unitTag) then
            alerts:showAction("Frost! Drop in 6s")
            CA.alert(nil, "FROST -- drop in 6s", 0x00EEEEff, SOUNDS.NONE, 4000)
        elseif unitName and unitName ~= "" then
            alerts:showAction("Frost -> " .. unitName)
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
        if OSI and dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
            OSI.RemoveMechanicIconForUnit(dname)
        end
    end
end

-- Hoarfrost synergy: player uses synergy to drop frost.
local function handleGaleHoarfrostSy(self, context, alerts, result, abilityId,
                                      unitTag, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Drop frost now!")
    CA.alert(nil, "DROP FROST!", 0x00EEEEff, SOUNDS.NONE, 2000)
end

-- Chilling Comet: personal alert on EFFECT_GAINED.
local function handleGaleComet(self, context, alerts, result, abilityId,
                                unitTag, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Chilling Comet! Move!")
    CA.alert(nil, "COMET - move!", 0x00AAFFFF, SOUNDS.NONE, 2500)
end

-- Portal close: shared handler for normal close and PC win.
local function handlePortalClose(self, context, alerts, abilityId, ...)
    self.portalActive = false
    self.portalTimer:clear()
    self.portalNextTimer:reset(PORTAL_NEXT_CD)
    self.coreAlert = false
end

-- Portal reset: Z'Maja re-engages after all three minis are shackled.
-- Resets portal group counter to 0 so the next PORTAL_OPEN starts at 1 again.
local function handlePortalReset(self, context, alerts, abilityId, ...)
    self.portalGroup    = 0
    self.portalActive   = false
    self.portalTimer:clear()
    self.portalNextTimer:clear()
    self.coreAlert      = false
    alerts:showAction("Z'Maja re-engaged -- portal counter reset")
end

-- Crushing Darkness: shared handler for 3 variants.
local function handleCrushingDark(self, context, alerts, abilityId, ...)
    alerts:showAction("Kite! Crushing Darkness")
    local dur = CastDur.get(abilityId, FALLBACK_DARK_DUR)
    CA.alertCast(abilityId, "KITE!", dur, COL_ZMAJA)
end

local function handleSiroHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Siroria HA! (" .. target .. ")")
    local dur = CastDur.get(SIRO_HA, FALLBACK_HA_DUR)
    local cid = CA.alertCast(abilityId, "Siro HA!", dur, COL_SIRO)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleSiroJump(self, context, alerts, result, abilityId, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Siroria jumping!")
    self.siroJumpTimer:reset()
end

local function handleSiroBanner(self, context, alerts, result, abilityId, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Siroria Banner!")
    self.siroBannerTimer:reset()
end

local function handleSiroDarkTalons(self, context, alerts, result, abilityId,
                                     unitTag, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Rooted! (Siroria)")
end

local function handleReleHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Relequen HA! (" .. target .. ")")
    local dur = CastDur.get(RELE_HA, FALLBACK_HA_DUR)
    local cid = CA.alertCast(abilityId, "Rele HA!", dur, COL_RELE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleReleJump(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Relequen jumping!")
    self.releJumpTimer:reset()
end

local function handleReleDirectCurr(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Interrupt Relequen!")
    CA.alert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)
    self.releBashTimer:reset()
end

local function handleReleJolt(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Relequen Jolt! Move!")
    self.releJoltTimer:reset()
end

local function handleReleOverload1(self, context, alerts, result, abilityId,
                                    unitTag, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Overload incoming - bar swap!")
end

local function handleReleOverload2(self, context, alerts, result, abilityId,
                                    unitTag, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Overload on you - swap now!")
    CA.alert(nil, "BAR SWAP", 0x3399FFFF, SOUNDS.NONE, 3000)
end

local function handleGaleHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Galenwe HA! (" .. target .. ")")
    local dur = CastDur.get(GALE_HA, FALLBACK_HA_DUR)
    local cid = CA.alertCast(abilityId, "Gale HA!", dur, COL_GALE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleGaleJump(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Galenwe jumping!")
    self.galeJumpTimer:reset()
end

local function handleGaleGlacial(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Interrupt Galenwe!")
    CA.alert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)
    self.galeBashTimer:reset()
end

local function handleGaleDonut(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction("Galenwe Donut! Out!")
    self.galeDonutTimer:reset()
end

-- Hoarfrost cast: marks Galenwe active (presence detection only; no alert).
local function handleGaleHoarfrostCast(self, ...)
    if not self.galeActive then self.galeActive = true end
end

local function handleOlorimeSpear(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if result ~= ACTION_RESULT_EFFECT_GAINED and result ~= ACTION_RESULT_BEGIN then return end
    self.spearCount = self.spearCount + 1
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Spear → " .. target .. " (" .. self.spearCount .. ")")
end

local function handleRazorThorns(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Rooted! (Creeper)")
end

local function handlePortalOpen(self, context, alerts, abilityId, ...)
    self.portalGroup  = self.portalGroup + 1
    self.portalActive = true
    self.portalTimer:reset(PORTAL_OPEN_DUR)
    self.portalNextTimer:clear()
    alerts:showHeader("Shadow Realm - Group " .. self.portalGroup)
end

local function handleZmajaJump(self, context, alerts, abilityId, ...)
    alerts:showAction("Z'Maja jumping!")
end

local function handleZmajaHideJump(self, context, alerts, abilityId, ...)
    alerts:showAction("Z'Maja retreating to shadow!")
end

local FALLBACK_SPLASH_DUR = 3000  -- Shadow Splash cast duration: empirical

local function handleShadowSplash(self, context, alerts, abilityId, ...)
    alerts:showAction("Shadow Splash! Interrupt!")
    local dur = CastDur.get(abilityId, FALLBACK_SPLASH_DUR)
    CA.alertCast(abilityId, "INTERRUPT! Shadow Splash", dur, COL_ZMAJA)
    CA.alert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)
end

local function handleBanefulMark(self, context, alerts, abilityId, ...)
    self.executePhase = true
    alerts:showAction("Baneful Mark! (execute)")
    CA.alert(nil, "BANEFUL MARK", 0xFF4444FF, SOUNDS.NONE, 4000)
end

local function handleCoreExposed(self, context, alerts, abilityId, ...)
    self.coreAlert = "Core out! Pick it up!"
    alerts:showAction("Core exposed!")
    CA.alert(nil, "CORE OUT!", 0xFFDD00FF, SOUNDS.NONE, 4000)
end

local function handleCoreMissed(self, context, alerts, abilityId, ...)
    self.coreAlert = "Core MISSED!"
    alerts:showAction("Core missed!")
    CA.alert(nil, "CORE MISSED!", 0xFF4444FF, SOUNDS.NONE, 5000)
end

local function handleCorePickedUp(self, context, alerts, abilityId, ...)
    self.coreAlert = false
    alerts:showAction("Core picked up.")
end

-- -- Routing tables (C3) --------------------------------------------------

ZmajaEncounter.combatRoutes = {
    -- Mini shackle
    [ZMAJA_SHACKLE]    = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleShackle },

    -- -- SIRORIA ------------------------------------------------------------
    [SIRO_HA]           = handleSiroHa,
    [SIRO_JUMP]         = handleSiroJump,
    [SIRO_BANNER]       = handleSiroBanner,
    [SIRO_FLARE]        = handleSiroFlare,
    [SIRO_FLARE_EXEC]   = handleSiroFlare,
    [SIRO_DARK_TALONS]  = handleSiroDarkTalons,

    -- -- RELEQUEN -----------------------------------------------------------
    [RELE_HA]           = handleReleHa,
    [RELE_JUMP]         = handleReleJump,
    [RELE_DIRECT_CURR]  = handleReleDirectCurr,
    [RELE_JOLT]         = handleReleJolt,
    [RELE_OVERLOAD_1]   = handleReleOverload1,
    [RELE_OVERLOAD_2]   = handleReleOverload2,

    -- -- GALENWE ------------------------------------------------------------
    [GALE_HA]            = handleGaleHa,
    [GALE_JUMP]          = handleGaleJump,
    [GALE_GLACIAL]       = handleGaleGlacial,
    [GALE_DONUT]         = handleGaleDonut,
    [GALE_HOARFROST_C]   = handleGaleHoarfrostCast,
    [GALE_HOARFROST_C2]  = handleGaleHoarfrostCast,
    [GALE_HOARFROST]     = handleGaleHoarfrost,
    [GALE_HOARFROST_2]   = handleGaleHoarfrost,
    [GALE_HOARFROST_SY]  = handleGaleHoarfrostSy,
    [GALE_HOARFROST_S2]  = handleGaleHoarfrostSy,
    [GALE_COMET]         = handleGaleComet,
    [GALE_COMET_2]       = handleGaleComet,

    -- -- Environment --------------------------------------------------------
    [RAZOR_THORNS]    = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleRazorThorns },

    -- -- Portal -------------------------------------------------------------
    [PORTAL_OPEN]      = { result = ACTION_RESULT_BEGIN, fn = handlePortalOpen },
    [PORTAL_CLOSE_1]   = { result = ACTION_RESULT_BEGIN, fn = handlePortalClose },
    [PORTAL_CLOSE_2]   = { result = ACTION_RESULT_BEGIN, fn = handlePortalClose },
    [PLAYER_EXIT]      = { result = ACTION_RESULT_BEGIN, fn = handlePortalClose },
    [PORTAL_RESET]     = { result = ACTION_RESULT_BEGIN, fn = handlePortalReset },
    [ZMAJA_RESET_PORT] = { result = ACTION_RESULT_BEGIN, fn = handlePortalReset },

    -- -- Z'Maja -------------------------------------------------------------
    [ZMAJA_JUMP]      = { result = ACTION_RESULT_BEGIN, fn = handleZmajaJump },
    [ZMAJA_HIDE_JUMP] = { result = ACTION_RESULT_BEGIN, fn = handleZmajaHideJump },
    [CRUSHING_DARK_1] = { result = ACTION_RESULT_BEGIN, fn = handleCrushingDark },
    [CRUSHING_DARK_2] = { result = ACTION_RESULT_BEGIN, fn = handleCrushingDark },
    [CRUSHING_DARK_3] = { result = ACTION_RESULT_BEGIN, fn = handleCrushingDark },
    [SHADOW_SPLASH]   = { result = ACTION_RESULT_BEGIN, fn = handleShadowSplash },
    [BANEFUL_MARK]    = { result = ACTION_RESULT_BEGIN, fn = handleBanefulMark },
    [OLORIME_SPEAR]   = handleOlorimeSpear,

    -- -- Malevolent Cores ----------------------------------------------------
    [CORE_EXPOSED]   = { result = ACTION_RESULT_BEGIN, fn = handleCoreExposed },
    [CORE_MISSED]    = { result = ACTION_RESULT_BEGIN, fn = handleCoreMissed },
    [CORE_PICKED_UP] = { result = ACTION_RESULT_BEGIN, fn = handleCorePickedUp },
}
-- (effectRoutes: CR-3 TODO - portal world-state, mini shackle via effect path)

-- -- Info-line renderers ---------------------------------------------------

-- Line 1: Portal open countdown, or time until next portal.
local function showPortalStatusLine(self, alerts)
    if self.portalActive then
        local r = self.portalTimer:remaining()
        local t = r > 0 and ZO_FormatCountdownTimer(r) or "closing"
        alerts:showInfo(1, "Portal open: " .. t)
    elseif not self.portalNextTimer:isExpired() then
        local r = self.portalNextTimer:remaining()
        alerts:showInfo(1, "Next portal: " .. ZO_FormatCountdownTimer(r))
    else
        alerts:showInfo(1, "")
    end
end

-- Line 2: Current portal group assignment, or execute-phase banner.
local function showPortalGroupLine(self, alerts)
    if self.executePhase then
        alerts:showInfo(2, "!!! EXECUTE PHASE !!!")
    elseif self.portalGroup > 0 then
        alerts:showInfo(2, "Shadow Group " .. self.portalGroup)
    else
        alerts:showInfo(2, "")
    end
end

-- Line 4: Olorime Spear count.
local function showSpearLine(self, alerts)
    if self.spearCount > 0 then
        alerts:showInfo(4, "Spears: " .. self.spearCount)
    else
        alerts:showInfo(4, "")
    end
end

-- Line 5: Siroria jump + banner timers.
local function showSiroLine(self, alerts)
    if self.siroActive then
        local j  = self.siroJumpTimer:remaining()
        local b  = self.siroBannerTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "ready"
        alerts:showInfo(5, "Siro: Jump " .. jt .. "  Bnr " .. bt)
    else
        alerts:showInfo(5, "")
    end
end

-- Line 6: Relequen jump + bash timers.
local function showReleLine(self, alerts)
    if self.releActive then
        local j  = self.releJumpTimer:remaining()
        local b  = self.releBashTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "INTERRUPT"
        alerts:showInfo(6, "Rele: Jump " .. jt .. "  Bash " .. bt)
    else
        alerts:showInfo(6, "")
    end
end

-- Line 7: Galenwe jump + bash timers.
local function showGaleLine(self, alerts)
    if self.galeActive then
        local j  = self.galeJumpTimer:remaining()
        local b  = self.galeBashTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "INTERRUPT"
        alerts:showInfo(7, "Gale: Jump " .. jt .. "  Bash " .. bt)
    else
        alerts:showInfo(7, "")
    end
end

-- -- 200 ms display update -------------------------------------------------
function ZmajaEncounter:onWipe()
    self:cleanupAlertList()
    self.siroJumpTimer:clear();   self.siroBannerTimer:clear()
    self.releJumpTimer:clear();   self.releBashTimer:clear();  self.releJoltTimer:clear()
    self.galeJumpTimer:clear();   self.galeBashTimer:clear();  self.galeDonutTimer:clear()
    self.portalTimer:clear();     self.portalNextTimer:clear()
    self.siroActive   = false;    self.releActive   = false;   self.galeActive = false
    self.portalGroup  = 0;        self.portalActive = false
    self.executePhase = false;    self.spearCount   = 0
    self.coreAlert    = false
end

function ZmajaEncounter:onUpdate(context, alerts)
    showPortalStatusLine(self, alerts)
    showPortalGroupLine(self, alerts)
    alerts:showInfo(3, self.coreAlert or "")   -- core alert: persistent until resolved
    showSpearLine(self, alerts)
    showSiroLine(self, alerts)
    showReleLine(self, alerts)
    showGaleLine(self, alerts)
end

function ZmajaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- CR-3: execute threshold pre-warning (if applicable)
end

package.loaded["trial.cr.boss.ZmajaEncounter"] = ZmajaEncounter
return ZmajaEncounter
