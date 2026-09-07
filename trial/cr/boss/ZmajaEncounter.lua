local Timer    = require("lib.Timer")

local CA            = require("external-api.CombatAlerts")
local MechanicIcons = require("external-api.MechanicIcons")
local BossBase      = require("lib.BossBase")
local CastDur       = require("lib.CastDur")
local Settings      = require("core.Settings")
local Lang          = require("core.Lang")
local Colors = require("core.Colors")

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
-- 103765 (GALE_HOARFROST_AO)  -- reference: ground AoE zone; passive, no alert needed
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
-- 105339 BEAD_TICK, 105363 BEAD_SPAWN, 105373 BEAD_CHARGE  -- reference: bead sub-mechanics; V2.0
local OLORIME_SPEAR    = 104018
-- 106023 BREAK_AMULET, 105291 MALICIOUS_SPHERE              -- reference: shadow-realm mechanics; V2.0

-- -- Timer durations (seconds) ---------------------------------------------
local SIRO_JUMP_CD     = 23
local SIRO_BANNER_CD   = 45
local RELE_JUMP_CD     = 19
local RELE_BASH_CD     = 20
local RELE_JOLT_CD     = 15
local GALE_JUMP_CD     = 19
local GALE_BASH_CD     = 22
local GALE_DONUT_CD    = 22
-- HOARFROST_DROP = 6  -- reference: drop delay (unimplemented proactive timer; V2.0)
local FLARE_WINDOW     = 7     -- Roaring Flare alert window (seconds)
-- COMET_WINDOW = 4    -- reference: comet alert window (handler uses hardcoded ms; V2.0)
local PORTAL_OPEN_DUR  = 75    -- portal stays open ~75 s
local PORTAL_NEXT_CD   = 46    -- seconds until next portal after close

-- -- CA colour palettes ----------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DARK_DUR = 6000   -- CrushingDarkness: empirical
local FALLBACK_HA_DUR   = 1500   -- Siroria/Relequen/Galenwe HeavyAttack: empirical

local ZmajaEncounter = {}
ZmajaEncounter.__index = ZmajaEncounter
setmetatable(ZmajaEncounter, {__index = BossBase})  -- inherit cleanupAlertList, onDied

ZmajaEncounter.key               = "zmaja"
ZmajaEncounter.nameAliases       = { Lang.t("boss_zmaja") }
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
    if unitName and unitName:find(Lang.t("boss_siroria"), 1, true) then
        self.siroActive = false
        self.siroJumpTimer:clear(); self.siroBannerTimer:clear()
    elseif unitName and unitName:find(Lang.t("boss_relequen"), 1, true) then
        self.releActive = false
        self.releJumpTimer:clear(); self.releBashTimer:clear(); self.releJoltTimer:clear()
    elseif unitName and unitName:find(Lang.t("boss_galenwe"), 1, true) then
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
    alerts:showAction(Lang.t("cr_zmaja_siro_flare", target))
    local dur = CastDur.get(abilityId, math.floor(FLARE_WINDOW * 1000))
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_flare", target), dur, Colors.FIRE)
    if cid and unitId then self.alertList[unitId] = cid end
end

-- Hoarfrost: EFFECT_GAINED -> OSI icon + alert; EFFECT_FADED -> remove icon.
local function handleGaleHoarfrost(self, context, alerts, result, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    if not self.galeActive then self.galeActive = true end
    if result == ACTION_RESULT_EFFECT_GAINED then
        local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
        if dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
            MechanicIcons.set(dname, GetAbilityIcon(abilityId), Colors.CYAN)
        end
        if IsUnitPlayer(unitTag) then
            alerts:showAction(Lang.t("cr_zmaja_gale_frost_you"))
            CA.alert(nil, Lang.t("cr_zmaja_gale_frost_alert"), 0x00EEEEff, SOUNDS.NONE, 4000)
        elseif unitName and unitName ~= "" then
            alerts:showAction(Lang.t("cr_zmaja_gale_frost_tgt", unitName))
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
        if dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
            MechanicIcons.remove(dname)
        end
    end
end

-- Hoarfrost synergy: player uses synergy to drop frost.
local function handleGaleHoarfrostSy(self, context, alerts, result, abilityId,
                                      unitTag, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_drop_frost"))
    CA.alert(nil, Lang.t("cr_zmaja_gale_drop_alert"), 0x00EEEEff, SOUNDS.NONE, 2000)
end

-- Chilling Comet: personal alert on EFFECT_GAINED.
local function handleGaleComet(self, context, alerts, result, abilityId,
                                unitTag, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_comet"))
    CA.alert(nil, Lang.t("cr_zmaja_gale_comet_alert"), 0x00AAFFFF, SOUNDS.NONE, 2500)
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
    alerts:showAction(Lang.t("cr_zmaja_portal_reset"))
end

-- Crushing Darkness: shared handler for 3 variants.
local function handleCrushingDark(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_crushing_dark"))
    local dur = CastDur.get(abilityId, FALLBACK_DARK_DUR)
    CA.ranged(abilityId, Lang.t("cr_zmaja_crushing_kite"), dur, Colors.VOID)
end

local function handleSiroHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_siro_ha", target))
    local dur = CastDur.get(SIRO_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_ha_bar"), dur, Colors.FIRE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleSiroJump(self, context, alerts, result, abilityId, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_siro_jump"))
    self.siroJumpTimer:reset()
end

local function handleSiroBanner(self, context, alerts, result, abilityId, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_siro_banner"))
    self.siroBannerTimer:reset()
end

local function handleSiroDarkTalons(self, context, alerts, result, abilityId,
                                     unitTag, ...)
    if not self.siroActive then self.siroActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_siro_root"))
end

local function handleReleHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_rele_ha", target))
    local dur = CastDur.get(RELE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_rele_ha_bar"), dur, Colors.ICE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleReleJump(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_jump"))
    self.releJumpTimer:reset()
end

local function handleReleDirectCurr(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    self.releBashTimer:reset()
end

local function handleReleJolt(self, context, alerts, result, abilityId, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_jolt"))
    self.releJoltTimer:reset()
end

local function handleReleOverload1(self, context, alerts, result, abilityId,
                                    unitTag, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_in"))
end

local function handleReleOverload2(self, context, alerts, result, abilityId,
                                    unitTag, ...)
    if not self.releActive then self.releActive = true end
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_you"))
    CA.alert(nil, Lang.t("cr_zmaja_rele_bar_swap"), 0x3399FFFF, SOUNDS.NONE, 3000)
end

local function handleGaleHa(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_gale_ha", target))
    local dur = CastDur.get(GALE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_gale_ha_bar"), dur, Colors.CYAN)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleGaleJump(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_jump"))
    self.galeJumpTimer:reset()
end

local function handleGaleGlacial(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    self.galeBashTimer:reset()
end

local function handleGaleDonut(self, context, alerts, result, abilityId, ...)
    if not self.galeActive then self.galeActive = true end
    if result ~= ACTION_RESULT_BEGIN then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_donut"))
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
    alerts:showAction(Lang.t("cr_zmaja_olorime_spear", target, self.spearCount))
end

local function handleRazorThorns(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_creeper_root"))
end

local function handlePortalOpen(self, context, alerts, abilityId, ...)
    self.portalGroup  = self.portalGroup + 1
    self.portalActive = true
    self.portalTimer:reset(PORTAL_OPEN_DUR)
    self.portalNextTimer:clear()
    alerts:showHeader(Lang.t("cr_zmaja_shadow_realm", self.portalGroup))
end

local function handleZmajaJump(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_jump"))
end

local function handleZmajaHideJump(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_hide_jump"))
end

local FALLBACK_SPLASH_DUR = 3000  -- Shadow Splash cast duration: empirical

local function handleShadowSplash(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_shadow_splash"))
    local dur = CastDur.get(abilityId, FALLBACK_SPLASH_DUR)
    CA.ranged(abilityId, Lang.t("cr_zmaja_shadow_splash_bar"), dur, Colors.VOID)
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
end

local function handleBanefulMark(self, context, alerts, abilityId, ...)
    self.executePhase = true
    alerts:showAction(Lang.t("cr_zmaja_baneful_mark"))
    CA.alert(nil, Lang.t("cr_zmaja_baneful_alert"), 0xFF4444FF, SOUNDS.NONE, 4000)
end

local function handleCoreExposed(self, context, alerts, abilityId, ...)
    self.coreAlert = Lang.t("cr_zmaja_core_out_alert")
    alerts:showAction(Lang.t("cr_zmaja_core_exposed"))
    CA.alert(nil, Lang.t("cr_zmaja_core_out_ca"), 0xFFDD00FF, SOUNDS.NONE, 4000)
end

local function handleCoreMissed(self, context, alerts, abilityId, ...)
    self.coreAlert = Lang.t("cr_zmaja_core_missed_alert")
    alerts:showAction(Lang.t("cr_zmaja_core_missed"))
    CA.alert(nil, Lang.t("cr_zmaja_core_missed_ca"), 0xFF4444FF, SOUNDS.NONE, 5000)
end

local function handleCorePickedUp(self, context, alerts, abilityId, ...)
    self.coreAlert = false
    alerts:showAction(Lang.t("cr_zmaja_core_picked"))
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
        if r > 0 then
            alerts:setRow(1, Lang.t("cr_zmaja_portal_open_label"), r)
        else
            alerts:setRow(1, Lang.t("cr_zmaja_portal_open_label") .. " " .. Lang.t("cr_zmaja_portal_closing"), nil)
        end
    elseif not self.portalNextTimer:isExpired() then
        local r = self.portalNextTimer:remaining()
        alerts:setRow(1, Lang.t("cr_zmaja_portal_next_label"), r)
    else
        alerts:clearRow(1)
    end
end

-- Line 2: Current portal group assignment, or execute-phase banner.
local function showPortalGroupLine(self, alerts)
    if self.executePhase then
        alerts:setRow(2, Lang.t("cr_zmaja_execute_phase"), nil)
    elseif self.portalGroup > 0 then
        alerts:setRow(2, Lang.t("cr_zmaja_shadow_group", self.portalGroup), nil)
    else
        alerts:clearRow(2)
    end
end

-- Line 4: Olorime Spear count.
local function showSpearLine(self, alerts)
    if self.spearCount > 0 then
        alerts:setRow(4, Lang.t("cr_zmaja_spears_label") .. self.spearCount, nil)
    else
        alerts:clearRow(4)
    end
end

-- Line 5: Siroria jump + banner timers.
local function showSiroLine(self, alerts)
    if self.siroActive then
        local j  = self.siroJumpTimer:remaining()
        local b  = self.siroBannerTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("common_ready")
        alerts:setRow(5, Lang.t("cr_zmaja_siro_label", jt, bt), nil)
    else
        alerts:clearRow(5)
    end
end

-- Line 6: Relequen jump + bash timers.
local function showReleLine(self, alerts)
    if self.releActive then
        local j  = self.releJumpTimer:remaining()
        local b  = self.releBashTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("cr_zmaja_bash_due")
        alerts:setRow(6, Lang.t("cr_zmaja_rele_label", jt, bt), nil)
    else
        alerts:clearRow(6)
    end
end

-- Line 7: Galenwe jump + bash timers.
local function showGaleLine(self, alerts)
    if self.galeActive then
        local j  = self.galeJumpTimer:remaining()
        local b  = self.galeBashTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("cr_zmaja_bash_due")
        alerts:setRow(7, Lang.t("cr_zmaja_gale_label", jt, bt), nil)
    else
        alerts:clearRow(7)
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
    if self.coreAlert then alerts:setRow(3, self.coreAlert, nil) else alerts:clearRow(3) end  -- core alert
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
