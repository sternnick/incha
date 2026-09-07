--- Lylanar (& Turlassil)  -  Dreadsail Reef boss 1
---
--- Fire (Lylanar) and ice (Turlassil) boss pair fight simultaneously.
--- Both bosses' ability IDs are handled in this single module.
--- nameAliases = {"Turlassil"} ensures detection regardless of which unit
--- is reported as boss1 on any given pull.
---
--- Phase DSR-3: full mechanics
---   Fire side (Lylanar):
---     CinderSurge (166693): GAINED -> 500 ms delay -> "INTERRUPT! (Ice Dome)"
---     ImminentBlister (168525): GAINED_DURATION + tank/heal -> info countdown
---     BlisteringFragility (166525): GAINED_DURATION -> fragility timer
---     Firebrand (166472): GAINED_DURATION -> brand tracker; HM: MatchBrands
---     BroilingHew (167273): BEGIN + player -> AlertCast (heavy)
---     TorridCleave (167298): BEGIN + player -> AlertCast (cleave)
---     ScaldingSwell (169587): BEGIN -> Alert "Fire wave" 5.5 s
---     CharredConstriction (167466): BEGIN -> Alert "Fire jump (spike!)" 2.5 s
---     MagmaSpike (168646): BEGIN -> info countdown "Need Fire Dome"
---     IncendiaryAxe (168817): BEGIN -> HM weapon cooldown tracker
---     MultiLoc (166909): EFFECT_GAINED -> Alert "Lylanar teleports"
---     DestructiveEmber (166210): GAINED/UPDATED/FADED -> fire bubble stacks
---     SummonFlameHound (169317): GAINED_DURATION -> flameHounds++
---   Ice side (Turlassil):
---     NumbingShards (166735): GAINED -> 500 ms delay -> "INTERRUPT! (Fire Dome)"
---     ImminentChill (168526): GAINED_DURATION + tank/heal -> info countdown
---     ChillingFragility (166529): GAINED_DURATION -> fragility timer
---     Frostbrand (166482): GAINED_DURATION -> brand tracker; HM: MatchBrands
---     StingingShear (167280): BEGIN + player -> AlertCast (heavy)
---     BriskRip (167290): BEGIN + player -> AlertCast (cleave)
---     BitingBillow (169594): BEGIN -> Alert "Ice wave" 5.5 s
---     Frigidarium (167545): BEGIN -> Alert "Ice jump (spike!)" 2.5 s
---     GlacialSpike (168632): BEGIN -> info countdown "Need Ice Dome"
---     CalamitousSword (168912): BEGIN -> HM weapon cooldown tracker
---     MultiLoc (166745): EFFECT_GAINED -> Alert "Turlassil teleports"
---     PiercingHailstone (166192): GAINED/UPDATED/FADED -> ice bubble stacks
---     SummonFrostHound (169313): GAINED_DURATION -> frostHounds++
---   Shared:
---     Hindered (165972): GAINED_DURATION + player -> AlertBorder 12 s
---     Brand matching (HM): 2 fire + 2 ice brands -> "STACK ON: partner (far/close)"
---
--- HM detection: context.isHM (pre-computed by TrialContext from hmHealthThreshold)
---   TODO: verify exact HM health pool in-game.

local DreadsailCommon  = require("trial.dsr.DreadsailCommon")
local DebuffTracker    = require("lib.DebuffTracker")
local Lang             = require("core.Lang")
local Fmt              = require("core.Fmt")


-- -- Ability IDs  -  Fire (Lylanar) -------------------------------------------
local CINDER_SURGE         = 166693   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> interrupt ice dome
local IMMINENT_BLISTER     = 168525   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> tank/heal 10s warning
local BLISTERING_FRAGILITY = 166525   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> fragility timer 20s
local FIREBRAND            = 166472   -- effectRoute: EFFECT_RESULT_GAINED -> HM brand tracking
local BROILING_HEW         = 167273   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (player, heavy fire)
local TORRID_CLEAVE        = 167298   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (player, cleave fire)
local SCALDING_SWELL       = 169587   -- combatRoute: ACTION_RESULT_BEGIN -> Fire wave alert 5.5s
local CHARRED_CONSTRICTION = 167466   -- combatRoute: ACTION_RESULT_BEGIN -> Fire jump cage alert
local MAGMA_SPIKE          = 168646   -- combatRoute: ACTION_RESULT_BEGIN -> lastMagmaSpike timer
local INCENDIARY_AXE       = 168817   -- combatRoute: ACTION_RESULT_BEGIN -> HM weapon cooldown 40s
local LYLANAR_MULTILOC     = 166909   -- effectRoute: EFFECT_RESULT_GAINED -> Lylanar teleport alert
local DESTRUCTIVE_EMBER    = 166210   -- effectRoute: EFFECT_RESULT_GAINED / UPDATED / FADED -> fire bubble stacks
local SUMMON_FLAME_HOUND   = 169317   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> flameHounds counter
-- 166355 (PRE_FIREBRAND)  -- reference: cast before brand placement; potential early alert

-- -- Ability IDs  -  Ice (Turlassil) -----------------------------------------
local NUMBING_SHARDS       = 166735   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> interrupt fire dome
local IMMINENT_CHILL       = 168526   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> tank/heal 10s warning
local CHILLING_FRAGILITY   = 166529   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> fragility timer 20s
local FROSTBRAND           = 166482   -- effectRoute: EFFECT_RESULT_GAINED -> HM brand tracking
local STINGING_SHEAR       = 167280   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (player, heavy ice)
local BRISK_RIP            = 167290   -- combatRoute: ACTION_RESULT_BEGIN -> caAlertCast (player, cleave ice)
local BITING_BILLOW        = 169594   -- combatRoute: ACTION_RESULT_BEGIN -> Ice wave alert 5.5s
local FRIGIDARIUM          = 167545   -- combatRoute: ACTION_RESULT_BEGIN -> Ice jump cage alert
local GLACIAL_SPIKE        = 168632   -- combatRoute: ACTION_RESULT_BEGIN -> lastGlacialSpike timer
local CALAMITOUS_SWORD     = 168912   -- combatRoute: ACTION_RESULT_BEGIN -> HM weapon cooldown 40s
local TURLASSIL_MULTILOC   = 166745   -- effectRoute: EFFECT_RESULT_GAINED -> Turlassil teleport alert
local PIERCING_HAILSTONE   = 166192   -- effectRoute: EFFECT_RESULT_GAINED / UPDATED / FADED -> ice bubble stacks
local SUMMON_FROST_HOUND   = 169313   -- effectRoute: EFFECT_RESULT_GAINED / FADED -> frostHounds counter
-- 166364 (PRE_FROSTBRAND) -- reference: cast before brand placement; potential early alert

-- -- Ability IDs  -  Shared --------------------------------------------------
local HINDERED             = 165972   -- effectRoute: EFFECT_RESULT_GAINED + player -> AlertBorder 12s

-- -- Timing constants -----------------------------------------------------
local FRAGILITY_DUR  = 20    -- s: fragility debuff visible window
local SPIKE_DUR      = 6.5   -- s: spike cage must be solved
local WEAPON_CD      = 40    -- s: HM weapon cooldown
local BRAND_DEDUP    = 1.0   -- s: MatchBrands dedup gate
local BUBBLE_CD_NORM = 15    -- s: bubble drop cooldown (normal)
local BUBBLE_CD_HM   = 20    -- s: bubble drop cooldown (HM)

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")

-- -- CA colour palettes ----------------------------------------------------

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_HEAVY_DUR = 1500   -- BroilingHew / TorridCleave / StingingShear / BriskRip: empirical

-- -- Boss definition -------------------------------------------------------
local Lylanar = {}
Lylanar.__index = Lylanar

Lylanar.key          = "lylanar"
Lylanar.name         = Lang.t("boss_lylanar")     -- TODO: verify via GetUnitName("boss1") in-game
Lylanar.nameAliases  = { Lang.t("boss_turlassil") }  -- both bosses active simultaneously
-- location: name-based detection intentional  -  dual-boss pair; arenas share the
-- same room so a single AABB would be ambiguous.  nameAliases covers both names.
Lylanar.hmHealthThreshold = 100000001   -- TODO: verify exact HM health pool

Lylanar.stateSchema = {
    -- State  -  Fire
    cinderSurgeActive      = false,
    fireImminent           = function() return DebuffTracker.new(10) end,
    fireFragility          = function() return DebuffTracker.new(FRAGILITY_DUR) end,
    lastMagmaSpike         = 0,
    lastIncendiaryAxe      = 0,
    destructiveEmberStacks = 0,
    lastDestructiveEmber   = 0,
    destructiveEmberName   = false,
    firebrandTracker       = function() return {} end,
    lastBrandMatchFire     = 0,
    flameHounds            = 0,
    -- State  -  Ice
    numbingShardsActive    = false,
    iceImminent            = function() return DebuffTracker.new(10) end,
    iceFragility           = function() return DebuffTracker.new(FRAGILITY_DUR) end,
    lastGlacialSpike       = 0,
    lastCalamitousSword    = 0,
    piercingHailstacks     = 0,
    lastPiercingHail       = 0,
    piercingHailName       = false,
    frostbrandTracker      = function() return {} end,
    lastBrandMatchIce      = 0,
    frostHounds            = 0,
    -- State  -  Shared
    lastBrandMatch         = 0,
}

function Lylanar.new()
    return BossBase.fromSchema(Lylanar)
end

-- -- Brand matching (HM) ---------------------------------------------------
-- Called after both firebrand and frostbrand trackers each hold 2 entries.
-- Finds the local player in either list and names their required partner.
local function matchBrands(self)
    local now = GetGameTimeMilliseconds() / 1000
    if now - self.lastBrandMatch < BRAND_DEDUP then return end
    self.lastBrandMatch = now

    local fire  = self.firebrandTracker   -- [{unitId, name}, ...]
    local frost = self.frostbrandTracker

    if #fire < 2 or #frost < 2 then return end

    -- Find local player's slot index in fire or frost list.
    local myFire, myFrost = nil, nil
    for i, entry in ipairs(fire) do
        if AreUnitsEqual("player", entry.tag or "") then myFire = i end
    end
    for i, entry in ipairs(frost) do
        if AreUnitsEqual("player", entry.tag or "") then myFrost = i end
    end

    -- Player must be in exactly one list; their partner is the matching index
    -- in the other list (index 1 -> index 1, index 2 -> index 2).
    local partner, distance
    if myFire then
        partner  = frost[myFire] and frost[myFire].name or "?"
        distance = (myFire == 1) and "far" or "close"
    elseif myFrost then
        partner  = fire[myFrost] and fire[myFrost].name or "?"
        distance = (myFrost == 1) and "far" or "close"
    else
        return  -- player not branded this round
    end

    CA.alert(nil,
        "STACK ON: " .. partner .. " (" .. distance .. ")",
        0xFF8800D9, SOUNDS.DUEL_START, 6000)
    PlaySound(SOUNDS.DUEL_START)
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared trash mechanic handler.
Lylanar.common = DreadsailCommon

-- -- Handlers -------------------------------------------------------------

local function handleBroilingHew(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleTorridCleave(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    alerts:showAction(Lang.t("dsr_lylanar_dodge_cleave"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleScaldingSwell(self, context, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FIRE, "Fire wave") .. "  -  move!", 0xFF5733D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
end

local function handleCharredConstriction(self, context, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FIRE, "Fire jump!") .. " (spike  -  block)", 0xFF5733D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleMagmaSpike(self, context, alerts, abilityId, ...)
    self.lastMagmaSpike = GetGameTimeMilliseconds() / 1000
end

local function handleIncendiaryAxe(self, context, alerts, abilityId, ...)
    if context.isHM then
        self.lastIncendiaryAxe = GetGameTimeMilliseconds() / 1000
    end
end

local function handleStingingShear(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FROST)
end

local function handleBriskRip(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    alerts:showAction(Lang.t("dsr_lylanar_dodge_cleave"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FROST)
end

local function handleBitingBillow(self, context, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FROST, "Ice wave") .. "  -  move!", 0x99CCffD9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
end

local function handleFrigidarium(self, context, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FROST, "Ice jump!") .. " (spike  -  block)", 0x99CCffD9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleGlacialSpike(self, context, alerts, abilityId, ...)
    self.lastGlacialSpike = GetGameTimeMilliseconds() / 1000
end

local function handleCalamitousSword(self, context, alerts, abilityId, ...)
    if context.isHM then
        self.lastCalamitousSword = GetGameTimeMilliseconds() / 1000
    end
end

-- -- Routing tables (C3) --------------------------------------------------
Lylanar.combatRoutes = {
    -- -- Fire ---------------------------------------------------------------
    [BROILING_HEW]        = { result = ACTION_RESULT_BEGIN, fn = handleBroilingHew },
    [TORRID_CLEAVE]       = { result = ACTION_RESULT_BEGIN, fn = handleTorridCleave },
    [SCALDING_SWELL]      = { result = ACTION_RESULT_BEGIN, fn = handleScaldingSwell },
    [CHARRED_CONSTRICTION]= { result = ACTION_RESULT_BEGIN, fn = handleCharredConstriction },
    [MAGMA_SPIKE]         = { result = ACTION_RESULT_BEGIN, fn = handleMagmaSpike },
    [INCENDIARY_AXE]      = { result = ACTION_RESULT_BEGIN, fn = handleIncendiaryAxe },
    -- -- Ice ----------------------------------------------------------------
    [STINGING_SHEAR]      = { result = ACTION_RESULT_BEGIN, fn = handleStingingShear },
    [BRISK_RIP]           = { result = ACTION_RESULT_BEGIN, fn = handleBriskRip },
    [BITING_BILLOW]       = { result = ACTION_RESULT_BEGIN, fn = handleBitingBillow },
    [FRIGIDARIUM]         = { result = ACTION_RESULT_BEGIN, fn = handleFrigidarium },
    [GLACIAL_SPIKE]       = { result = ACTION_RESULT_BEGIN, fn = handleGlacialSpike },
    [CALAMITOUS_SWORD]    = { result = ACTION_RESULT_BEGIN, fn = handleCalamitousSword },
}

-- -- Fire: CinderSurge -> interrupt ice dome -----------------------------
local function handleCinderSurge(self, context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        self.cinderSurgeActive = true
        self:after(500, function()
            if self.cinderSurgeActive then
                CA.alert(nil, Fmt.c(Fmt.FIRE, "INTERRUPT!") .. " (Ice Dome)",
                    0xFF2020D9, SOUNDS.DUEL_START, 15000)
                PlaySound(SOUNDS.DUEL_START)
            end
        end)
    elseif changeType == EFFECT_RESULT_FADED then
        self.cinderSurgeActive = false
    end
end

-- -- Ice: NumbingShards -> interrupt fire dome ---------------------------
local function handleNumbingShards(self, context, alerts, changeType, abilityId,
                                    unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        self.numbingShardsActive = true
        self:after(500, function()
            if self.numbingShardsActive then
                CA.alert(nil, Fmt.c(Fmt.FROST, "INTERRUPT!") .. " (Fire Dome)",
                    0x2020FFD9, SOUNDS.DUEL_START, 15000)
                PlaySound(SOUNDS.DUEL_START)
            end
        end)
    elseif changeType == EFFECT_RESULT_FADED then
        self.numbingShardsActive = false
    end
end

-- -- Fire: ImminentBlister (tank/heal warning, 10 s) --------------------
local function handleImminentBlister(self, context, alerts, changeType, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        local _, isHeal, isTank = GetPlayerRoles()
        if isTank or isHeal then
            self.fireImminent:start(GetUnitDisplayName(unitTag) or unitName)
        end
    elseif changeType == EFFECT_RESULT_FADED then
        self.fireImminent:clear()
    end
end

-- -- Ice: ImminentChill (tank/heal warning, 10 s) -----------------------
local function handleImminentChill(self, context, alerts, changeType, abilityId,
                                    unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        local _, isHeal, isTank = GetPlayerRoles()
        if isTank or isHeal then
            self.iceImminent:start(GetUnitDisplayName(unitTag) or unitName)
        end
    elseif changeType == EFFECT_RESULT_FADED then
        self.iceImminent:clear()
    end
end

-- -- Fire: BlisteringFragility (20 s debuff on local player) -----------
local function handleBlisteringFragility(self, context, alerts, changeType, abilityId,
                                          unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        if AreUnitsEqual("player", unitTag) then
            self.fireFragility:start(GetUnitDisplayName(unitTag) or unitName)
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.fireFragility:clear()
        end
    end
end

-- -- Ice: ChillingFragility (20 s debuff on local player) --------------
local function handleChillingFragility(self, context, alerts, changeType, abilityId,
                                        unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        if AreUnitsEqual("player", unitTag) then
            self.iceFragility:start(GetUnitDisplayName(unitTag) or unitName)
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.iceFragility:clear()
        end
    end
end

-- -- Fire: DestructiveEmber (fire bubble stacks, stackCount used!) -------
local function handleDestructiveEmber(self, context, alerts, changeType, abilityId,
                                       unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.destructiveEmberStacks = stackCount or 1
            self.destructiveEmberName   = GetUnitDisplayName(unitTag) or unitName
            self.lastDestructiveEmber   = GetGameTimeMilliseconds() / 1000
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.destructiveEmberStacks = 0
            self.destructiveEmberName   = false
            self.lastDestructiveEmber   = 0
        end
    end
end

-- -- Ice: PiercingHailstone (ice bubble stacks, stackCount used!) --------
local function handlePiercingHailstone(self, context, alerts, changeType, abilityId,
                                        unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.piercingHailstacks = stackCount or 1
            self.piercingHailName   = GetUnitDisplayName(unitTag) or unitName
            self.lastPiercingHail   = GetGameTimeMilliseconds() / 1000
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.piercingHailstacks = 0
            self.piercingHailName   = false
            self.lastPiercingHail   = 0
        end
    end
end

-- -- Fire: Firebrand (HM brand tracking) ------------------------------
local function handleFirebrand(self, context, alerts, changeType, abilityId,
                                unitTag, unitId, unitName, stackCount)
    if not context.isHM then return end
    if changeType ~= EFFECT_RESULT_GAINED then return end
    local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
    table.insert(self.firebrandTracker, entry)
    if #self.firebrandTracker >= 2 and #self.frostbrandTracker >= 2 then
        matchBrands(self)
        self.firebrandTracker  = {}
        self.frostbrandTracker = {}
    end
end

-- -- Ice: Frostbrand (HM brand tracking) ------------------------------
local function handleFrostbrand(self, context, alerts, changeType, abilityId,
                                 unitTag, unitId, unitName, stackCount)
    if not context.isHM then return end
    if changeType ~= EFFECT_RESULT_GAINED then return end
    local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
    table.insert(self.frostbrandTracker, entry)
    if #self.firebrandTracker >= 2 and #self.frostbrandTracker >= 2 then
        matchBrands(self)
        self.firebrandTracker  = {}
        self.frostbrandTracker = {}
    end
end

local function handleLylanarMultiloc(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        CA.alert(nil, Fmt.c(Fmt.FIRE, "Lylanar teleports") .. "  -  reposition!",
            0xFF5733D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
    end
end

local function handleTurlassilMultiloc(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        CA.alert(nil, Fmt.c(Fmt.FROST, "Turlassil teleports") .. "  -  reposition!",
            0x99CCffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
    end
end

local function handleSummonFlameHound(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        self.flameHounds = self.flameHounds + 1
    elseif changeType == EFFECT_RESULT_FADED then
        if self.flameHounds > 0 then self.flameHounds = self.flameHounds - 1 end
    end
end

local function handleSummonFrostHound(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        self.frostHounds = self.frostHounds + 1
    elseif changeType == EFFECT_RESULT_FADED then
        if self.frostHounds > 0 then self.frostHounds = self.frostHounds - 1 end
    end
end

-- -- Shared: Hindered (slow on player -> yellow border 12 s) ----------
local function handleHindered(self, context, alerts, changeType, abilityId,
                               unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        CA.border(true, 12000, "yellow")
    end
end

Lylanar.effectRoutes = {
    -- -- Fire ---------------------------------------------------------------
    [CINDER_SURGE]         = handleCinderSurge,
    [NUMBING_SHARDS]       = handleNumbingShards,
    [IMMINENT_BLISTER]     = handleImminentBlister,
    [IMMINENT_CHILL]       = handleImminentChill,
    [BLISTERING_FRAGILITY] = handleBlisteringFragility,
    [CHILLING_FRAGILITY]   = handleChillingFragility,
    [DESTRUCTIVE_EMBER]    = handleDestructiveEmber,
    [PIERCING_HAILSTONE]   = handlePiercingHailstone,
    [FIREBRAND]            = handleFirebrand,
    [FROSTBRAND]           = handleFrostbrand,
    [LYLANAR_MULTILOC]     = handleLylanarMultiloc,
    [TURLASSIL_MULTILOC]   = handleTurlassilMultiloc,
    [SUMMON_FLAME_HOUND]   = handleSummonFlameHound,
    [SUMMON_FROST_HOUND]   = handleSummonFrostHound,
    -- -- Shared -------------------------------------------------------------
    [HINDERED]             = handleHindered,
}

-- -- Info-line renderers ---------------------------------------------------

-- Row 1: Fire bubble (Destructive Ember)  -  stack count in name column, drop countdown as ETA.
local function showFireBubbleLine(self, alerts, now, isHM)
    if self.lastDestructiveEmber > 0 then
        local cd     = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T      = cd - (now - self.lastDestructiveEmber)
        local stks   = self.destructiveEmberStacks
        local name   = self.destructiveEmberName or "?"
        local suffix = stks ~= 1 and Lang.t("dsr_lylanar_ember_suffix_p", stks)
                                   or  Lang.t("dsr_lylanar_ember_suffix",   stks)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.FIRE, "\xf0\x9f\x94\xa5 " .. name) .. suffix, T)
        else
            alerts:setRow(1,
                Fmt.c(Fmt.FIRE, "\xf0\x9f\x94\xa5 " .. name) .. suffix
                .. " " .. Fmt.c(Fmt.RED, Lang.t("dsr_lylanar_drop")), nil)
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Ice bubble (Piercing Hailstone)  -  stack count in name column, drop countdown as ETA.
local function showIceBubbleLine(self, alerts, now, isHM)
    if self.lastPiercingHail > 0 then
        local cd     = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T      = cd - (now - self.lastPiercingHail)
        local stks   = self.piercingHailstacks
        local name   = self.piercingHailName or "?"
        local suffix = stks ~= 1 and Lang.t("dsr_lylanar_ember_suffix_p", stks)
                                   or  Lang.t("dsr_lylanar_ember_suffix",   stks)
        if T > 0 then
            alerts:setRow(2, Fmt.c(Fmt.FROST, "\xe2\x9d\x84 " .. name) .. suffix, T)
        else
            alerts:setRow(2,
                Fmt.c(Fmt.FROST, "\xe2\x9d\x84 " .. name) .. suffix
                .. " " .. Fmt.c(Fmt.RED, Lang.t("dsr_lylanar_drop")), nil)
        end
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Fragility debuff countdown  -  fire takes priority over ice.
local function showFragilityLine(self, alerts)
    local fireT = self.fireFragility:remaining()
    local iceT  = self.iceFragility:remaining()
    if fireT > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_fire_fragility")), fireT)
    elseif iceT > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_ice_fragility")), iceT)
    else
        alerts:clearRow(3)
    end
end

-- Row 4: Spike cage (priority) > HM weapon cooldowns > Imminent tank/heal warning.
-- Axe/spike ETA goes in the tracker column; sword (secondary) is appended to name.
local function showSpikeLine(self, alerts, now, isHM)
    local fireSpikeT = (self.lastMagmaSpike   > 0) and (SPIKE_DUR - (now - self.lastMagmaSpike))   or -1
    local iceSpikeT  = (self.lastGlacialSpike > 0) and (SPIKE_DUR - (now - self.lastGlacialSpike)) or -1

    if fireSpikeT > 0 then
        alerts:setRow(4, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_need_fire_dome")), fireSpikeT)
    elseif iceSpikeT > 0 then
        alerts:setRow(4, Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_need_ice_dome")), iceSpikeT)
    elseif isHM and self.lastIncendiaryAxe > 0 then
        local T = WEAPON_CD - (now - self.lastIncendiaryAxe)
        -- Sword info (secondary timer) appended to name column if active.
        local swordPart = ""
        if self.lastCalamitousSword > 0 then
            swordPart = Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_sword")
                .. Fmt.timer(math.max(0, WEAPON_CD - (now - self.lastCalamitousSword))))
        end
        if T > 0 then
            alerts:setRow(4, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_axe")) .. swordPart, T)
        else
            alerts:setRow(4,
                Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_axe")) .. " " .. Fmt.c(Fmt.RED, "INC") .. swordPart, nil)
        end
    else
        local fireImminT = self.fireImminent:remaining()
        local iceImminT  = self.iceImminent:remaining()
        if fireImminT > 0 then
            alerts:setRow(4,
                Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_imm_blister")
                    .. " (" .. (self.fireImminent:playerName() or "?") .. ")"), fireImminT)
        elseif iceImminT > 0 then
            alerts:setRow(4,
                Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_imm_chill")
                    .. " (" .. (self.iceImminent:playerName() or "?") .. ")"), iceImminT)
        else
            alerts:clearRow(4)
        end
    end
end

function Lylanar:onWipe()
    self.fireImminent:clear();  self.fireFragility:clear()
    self.iceImminent:clear();   self.iceFragility:clear()
    self.cinderSurgeActive      = false
    self.lastMagmaSpike         = 0;    self.lastIncendiaryAxe    = 0
    self.destructiveEmberStacks = 0;    self.lastDestructiveEmber = 0
    self.destructiveEmberName   = false
    self.firebrandTracker       = {};   self.lastBrandMatchFire   = 0
    self.flameHounds            = 0
    self.numbingShardsActive    = false
    self.lastGlacialSpike       = 0;    self.lastCalamitousSword  = 0
    self.piercingHailstacks     = 0;    self.lastPiercingHail     = 0
    self.piercingHailName       = false
    self.frostbrandTracker      = {};   self.lastBrandMatchIce    = 0
    self.frostHounds            = 0
    self.lastBrandMatch         = 0
end

-- -- 200 ms display loop ---------------------------------------------------
function Lylanar:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showFireBubbleLine(self, alerts, now, isHM)
    showIceBubbleLine(self, alerts, now, isHM)
    showFragilityLine(self, alerts)
    showSpikeLine(self, alerts, now, isHM)
end

package.loaded["trial.dsr.boss.Lylanar"] = Lylanar
return Lylanar
