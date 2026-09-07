local Location    = require("core.Location")
local HealthRules = require("core.HealthRules")
local Settings    = require("core.Settings")
local Timer       = require("lib.Timer")
local Lang        = require("core.Lang")

local CA            = require("external-api.CombatAlerts")
local MechanicIcons = require("external-api.MechanicIcons")
local PositionIcons = require("external-api.PositionIcons")
local BossBase      = require("lib.BossBase")
local CastDur       = require("lib.CastDur")
local Log           = require("lib.Log")
local Colors = require("core.Colors")

-- -- OSI helpers (OdySupportIcons, optional) -------------------------------
-- Textures: pulled from the live ability data so they always match the
-- icon players see in their buff bar.  Evaluated once at load time.
local ICON_PRISON      = GetAbilityIcon(132473)   -- FALGRAVN_PRISON
-- GetAbilityIcon(140944) (ICON_INSTABILITY)  -- reference: instability buff icon (unrouted)
local ICON_SYNERGY     = GetAbilityIcon(129936)   -- FALGRAVN_BLOPSYNERGIE


-- -- Instability animated head-icon ------------------------------------------
-- 40 DDS frames exported to resources/instability/; cycled at 50 ms/frame
-- (2s loop) via a single RegisterForUpdate event that runs only while at
-- least one player carries the debuff.
local INST_ANIM_FRAMES   = 40
local INST_ANIM_INTERVAL = 50   -- ms per frame
local INST_ANIM_KEY      = "Incha_FalgravnInstAnim"

-- Module-level so the state survives boss-instance re-creation on wipe.
local _instAnim   = {}   -- [unitTag] = { dn = displayName, frame = 0 }
local _instActive = false

local function instAnimTick()
    for _, state in pairs(_instAnim) do
        state.frame = (state.frame % INST_ANIM_FRAMES) + 1
        local tex = string.format("Incha/resources/instability/frame_%02d.dds",
                                  state.frame)
        MechanicIcons.set(state.dn, tex, Colors.FLYZONE)
    end
end

local function startInstAnim(unitTag, displayName)
    _instAnim[unitTag] = { dn = displayName, frame = 0 }
    if not _instActive then
        EVENT_MANAGER:RegisterForUpdate(INST_ANIM_KEY, INST_ANIM_INTERVAL,
                                        instAnimTick)
        _instActive = true
    end
end

-- Stops the frame-cycle for unitTag and clears its entry.
-- Does NOT call osiRemove - callers are responsible for icon removal so
-- this function stays above the osiRemove/osiSet local declarations.
local function stopInstAnim(unitTag)
    _instAnim[unitTag] = nil
    if next(_instAnim) == nil and _instActive then
        EVENT_MANAGER:UnregisterForUpdate(INST_ANIM_KEY)
        _instActive = false
    end
end

-- -- OSI world-coordinate position icons -----------------------------------
-- Connection node positions: 4 lines x 5 nodes (wall=1 -> boss=5).
-- Shown when Lightning fires (90%/80% connect), hidden when Pulse fades.
local CONN_NODES = {
    LN1={ 23311, 21700,  8270 }, LN2={ 23647, 21672,  8594 },
    LN3={ 23931, 21670,  8901 }, LN4={ 24254, 21670,  9200 },
    LN5={ 24546, 21670,  9530 },
    LS1={ 23165, 21700, 11754 }, LS2={ 23521, 21672, 11378 },
    LS3={ 23832, 21670, 11079 }, LS4={ 24138, 21670, 10786 },
    LS5={ 24488, 21670, 10457 },
    RN1={ 26800, 21700,  8315 }, RN2={ 26486, 21672,  8627 },
    RN3={ 26169, 21670,  8939 }, RN4={ 25865, 21670,  9236 },
    RN5={ 25513, 21670,  9517 },
    RS1={ 26718, 21700, 11705 }, RS2={ 26404, 21672, 11409 },
    RS3={ 26115, 21670, 11104 }, RS4={ 25822, 21670, 10828 },
    RS5={ 25483, 21670, 10509 },
}
local CONN_TEX = {
    [1] = "odysupporticons/icons/squares/squaretwo_red_one.dds",
    [2] = "odysupporticons/icons/squares/squaretwo_red_two.dds",
    [3] = "odysupporticons/icons/squares/squaretwo_red_three.dds",
    [4] = "odysupporticons/icons/squares/squaretwo_red_four.dds",
    [5] = "odysupporticons/icons/squares/squaretwo_red_five.dds",
}

-- Blood-ball positions: 4 nodes at a lower floor level, stage 2 only.
local BLOOD_NODES = {
    { x=24546, y=14570, z= 9530, tex="odysupporticons/icons/squares/squaretwo_orange_one.dds"   },
    { x=24488, y=14570, z=10457, tex="odysupporticons/icons/squares/squaretwo_orange_two.dds"   },
    { x=25483, y=14570, z=10509, tex="odysupporticons/icons/squares/squaretwo_orange_three.dds" },
    { x=25513, y=14570, z= 9517, tex="odysupporticons/icons/squares/squaretwo_orange_four.dds"  },
}

-- Torturer anchor positions (8 torturers around the arena perimeter).
local TORTURER_NODES = {
    Brekalda   ={ 25069, 7722,  7114 },
    Thjorlak   ={ 27000, 7711,  8062 },
    Aevar      ={ 27796, 7710, 10040 },
    Triveta    ={ 26966, 7715, 12008 },
    Skormgondar={ 24944, 7703, 12970 },
    Irthrig    ={ 22966, 7718, 12034 },
    Ama        ={ 22300, 7742, 10000 },
    Sislea     ={ 23133, 7733,  8085 },
}
local TORTURER_TEX = {
    blue   = "odysupporticons/icons/squares/square_blue.dds",
    yellow = "odysupporticons/icons/squares/square_yellow.dds",
    green  = "odysupporticons/icons/squares/square_green.dds",
    red    = "odysupporticons/icons/squares/square_red.dds",
}

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 2000   -- Cleave (FALGRAVN_M_CLEAVE): empirical

-- World-coordinate position icon handles.  Stored at module level so they
-- survive across boss-instance replacements (which happen after each wipe).
-- Created in onEnter once per zone visit; discarded in onLeave on zone exit.
local _posIconConn     = false
local _posIconBlood    = false
local _posIconTorturer = false

local osiSet    = MechanicIcons.set
local osiRemove = MechanicIcons.remove

-- createConnIcons / createBloodIcons / createTorturerIcons:
--   Called once in onEnter (inside a zo_callLater); icons start hidden.
--   Returns a table of icon handles keyed by node name, or false when
--   PositionIcons is not configured.
local function createConnIcons()
    if not PositionIcons.isAvailable() then return false end
    local icons = {}
    for name, pos in pairs(CONN_NODES) do
        local idx  = tonumber(string.sub(name, -1)) or 1
        local icon = PositionIcons.create(pos[1], pos[2], pos[3],
                         CONN_TEX[idx], 60, Colors.PINK)
        if icon then icon.use = false; icons[name] = icon end
    end
    return icons
end

local function createBloodIcons()
    if not PositionIcons.isAvailable() then return false end
    local icons = {}
    for i, node in ipairs(BLOOD_NODES) do
        local icon = PositionIcons.create(node.x, node.y, node.z,
                         node.tex, 60, Colors.AMBER)
        if icon then icon.use = false; icons[i] = icon end
    end
    return icons
end

local function createTorturerIcons()
    if not PositionIcons.isAvailable() then return false end
    local icons = {}
    for name, pos in pairs(TORTURER_NODES) do
        local icon = PositionIcons.create(pos[1], pos[2], pos[3],
                         TORTURER_TEX.blue, 60, Colors.ICE)
        if icon then icon.use = false; icons[name] = icon end
    end
    return icons
end

-- discardPosIcons: discard every icon handle in a table via the gateway.
local discardPosIcons = PositionIcons.discardAll

-- showPosIcons: toggle .use flag on every icon in a table.
local function showPosIcons(iconTable, visible)
    if not iconTable then return end
    for _, icon in pairs(iconTable) do icon.use = visible end
end

-- updateTorturerIcon: swap texture + color for one named torturer icon.
local function updateTorturerIcon(iconTable, name, tex, color)
    if not (iconTable and iconTable[name]) then return end
    PositionIcons.update(iconTable[name], tex, color)
end

-- -- Ability IDs (from BSCHTKA_Falgraven.lua) ------------------------------
-- Combat event IDs
local INFUSER_CASTS         = 137289  -- Trash infuser cast
local INFUSER_BUFF          = 139961  -- Infuser buff gained by ally
local FALGRAVN_LIGHTNING    = 133428  -- Connect mechanic (90%/80%); OSI floor icons need world coords
local FALGRAVN_OPEN_DOOR    = 136693  -- Open the gates cast
local FALGRAVN_TUT_FEED     = 137314  -- Torturer feeding prisoner
local FALGRAVN_M_MOVE       = 136965  -- Njordal ground move AoE
local FALGRAVN_M_BLOCK      = 136953  -- Njordal charge (triggers heavy; use 137499 for the bar)
local FALGRAVN_M_BLOCK_HEAVY = 137499 -- "Bloody Frenzy"  -  the actual heavy-attack ability
local FALGRAVN_M_CLEAVE     = 136976  -- Njordal blood cleave
local FALGRAVN_BLOOD_FOUNT  = 140294  -- Blood Fountain cast
local FALGRAVN_TORTURER_ESC = 139633  -- Torturer coming down
local FALGRAVN_START_STAGE2 = 135271  -- Stage 2 start channel
local FALGRAVN_SHATTER_MID  = 136727  -- Floor shatters -> Stage 3
local FALGRAVN_INSTABILITY  = 140944  -- Instability cast / effect
local FALGRAVN_UNW_POWER    = 139378  -- Unwavering Power (Falgravn landing)
local FALGRAVN_BLOOTBALL    = 136548  -- Blood Ball effect
local FALGRAVN_PULSE        = 134854  -- Connection pulse (fades -> clear icons)
local FALGRAVN_HM           = 137215  -- HM confirmation ability
local FALGRAVN_SACRIFICE    = 139620  -- Prisoner saved
local FALGRAVN_TORTURER_LA  = 136958  -- Torturer light attack (non-tank dodge)

-- Effect change IDs
local FALGRAVN_PRISON       = 132473  -- Prison debuff on player
local FALGRAVN_INSTABILITY2 = 140941  -- Instability (non-HM variant)
local FALGRAVN_PRISONER_F   = 137315  -- Prisoner feeding stacks
local FALGRAVN_BLOPSYNERGIE = 129936  -- Execration synergy on player
local FALGRAVN_LINK_EFFECT  = 133433  -- Effect placed ON the Lightning Conduit OBJECT by Falgravn

-- -- Timer durations -------------------------------------------------------
local INSTABILITY_INITIAL_DELAY  = 10
local NEXT_INSTABILITY           = 22
local NEXT_BLOODBALL             = 45
local INITIAL_BLOODBALL_DELAY    = 20   -- after Falgravn lands (UNW_POWER fades)
local INITIAL_OPENGATE_TIME      = 40   -- from floor shatter to first gates
local NEXT_OPENGATE_TIME         = 45   -- recurring between Open Door casts
local NEXT_TORTURER_TP           = 25   -- torturer teleport countdown

-- -- Boss definition -------------------------------------------------------

local Falgravn = {}
Falgravn.__index = Falgravn
setmetatable(Falgravn, {__index = BossBase})   -- inherit cleanupAlertList, default onDied

Falgravn.key                  = "falgravn"
Falgravn.hmHealthThreshold    = 248386060

-- UNVERIFIED COORDINATE SPACE  -  see checkNodeCoordSpace() below.
--
-- This AABB is the arena used to detect Falgravn, and it does not contain the
-- world positions used by the OSI floor markers in this same file:
--
--                       x                 y                z
--   arena AABB     73,700 - 84,500    6,000 - 22,500   50,200 - 61,900
--   CONN_NODES     23,311 - 26,800       21,670         8,270 - 11,754
--   BLOOD_NODES    24,488 - 25,513       14,570         9,517 - 10,509
--   TORTURER_NODES 22,300 - 27,796        7,703 -  7,742  7,114 - 12,970
--
-- Every node y falls inside the AABB's y range; no node x or z comes close.
-- The convention is right elsewhere in this trial (Vrol's portal icon at
-- 114,624 / 25,764 / 71,349 sits inside Vrol's own box), which suggests the
-- node tables carry a different origin, most likely inherited from BSCHTKA
-- without re-measurement. If so, every Falgravn floor marker is misplaced.
--
-- To settle it: enter the arena with `/incha debug` on and read the
-- "falgravn coords" line printed by onEnter.
Falgravn.location             = Location.new(73700, 84500, 6000, 22500, 50200, 61900)
Falgravn.hideActionWhenNoRule = true
Falgravn.healthRules          = HealthRules.register({
    {
        id   = "conga_90",
        min  = 90, max = 93,
        text = "Connect Soon! (90% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "conga_80",
        min  = 80, max = 83,
        text = "Connect Soon! (80% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "floor_shatter",
        min  = 70, max = 73,
        text = "Dont Ult (Floor Shatter)! (70% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "dont_ult",
        min  = 35, max = 38,
        text = "Dont Ult! (35% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI and boss.CURRENT_STAGE < 3 end,
    },
})

Falgravn.stateSchema = {
    -- Stage / mechanic state
    showPercentUI    = false,
    CURRENT_STAGE    = 1,
    bHM              = false,
    -- Dedup flags for Njordal's recurring mechanics (reset each encounter).
    bMove            = true,
    bBlock           = true,
    bConnect         = true,
    -- Torturer encounter state.
    bStartTorturerCD = true,
    torturerCount    = 8,
    -- [unitId] -> CA cast bar ID; cleared on leave/death.
    alertList        = function() return {} end,
    -- [unitTag] -> CA bar ID for the Prison debuff.  Keyed because Prison
    -- can be on several players at once; see handlePrisonEffect.
    prisonBars       = function() return {} end,
    -- zo_callLater handle for the 25 s Open Door heavy-attack alert.
    -- Stored so onWipe can cancel it if the next pull starts within that window.
    openGatesDelayTimer = false,
    -- Name of the torturer whose feed icon was last turned yellow (false = none).
    activeFeedTorturer = false,
    -- OSI mechanic icon tracking: [unitTag] -> displayName.
    osiPrison      = function() return {} end,
    osiInstability = function() return {} end,
    osiSynergy     = function() return {} end,
    -- Timers
    instabilityTimer = function() return Timer.new(INSTABILITY_INITIAL_DELAY) end,
    bloodBallTimer   = function() return Timer.new(NEXT_BLOODBALL) end,
    openGatesTimer   = function() return Timer.new(NEXT_OPENGATE_TIME) end,
    torturerTimer    = function() return Timer.new(NEXT_TORTURER_TP) end,
    -- Prisoner tracking: stack count per prisoner name.
    PRISONERS = function() return {
        Brekalda = 0, Thjorlak = 0, Aevar = 0, Triveta = 0,
        Skormgondar = 0, Irthrig = 0, Ama = 0, Sislea = 0,
    } end,
}

function Falgravn.new()
    return BossBase.fromSchema(Falgravn)
end

-- -- Lifecycle -------------------------------------------------------------

function Falgravn:onLeave(context)
    -- Stop all alertList bars via the BossBase helper, then any extra bars.
    self:cleanupAlertList()
    for _, cid in pairs(self.prisonBars) do CA.castAlertsStop(cid) end
    self.prisonBars = {}
    -- Remove any OSI mechanic icons.
    for _, dn in pairs(self.osiPrison)  do osiRemove(dn) end
    for unitTag, dn in pairs(self.osiInstability) do
        stopInstAnim(unitTag)
        osiRemove(dn)
    end
    for _, dn in pairs(self.osiSynergy) do osiRemove(dn) end
    -- Discard world-coordinate position icons (zone exit  -  module handles reset).
    discardPosIcons(_posIconConn)
    discardPosIcons(_posIconBlood)
    discardPosIcons(_posIconTorturer)
    _posIconConn     = false
    _posIconBlood    = false
    _posIconTorturer = false
end

-- -- Combat state ----------------------------------------------------------

function Falgravn:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.instabilityTimer:reset()
    end
end

-- Soft reset on wipe while still inside the Falgravn arena.
-- Stops active CA bars, clears per-player OSI mechanic icons (Prison /
-- Instability / Synergy), hides world-coord position icons without
-- discarding them (icons survive into the next pull), and resets all
-- per-pull flags so the fight can restart from Stage 1.
function Falgravn:onWipe(context, alerts)
    -- Stop all cast bars.
    self:cleanupAlertList()
    for _, cid in pairs(self.prisonBars) do CA.castAlertsStop(cid) end
    self.prisonBars = {}
    self:cancelAfter(self.openGatesDelayTimer)
    self.openGatesDelayTimer = false

    -- Remove per-player OSI mechanic icons that were showing during the pull.
    for _, dn in pairs(self.osiPrison)  do osiRemove(dn) end
    for unitTag, dn in pairs(self.osiInstability) do
        stopInstAnim(unitTag)
        osiRemove(dn)
    end
    for _, dn in pairs(self.osiSynergy) do osiRemove(dn) end
    -- Wipe the tracking tables so stale EFFECT_RESULT_FADED events fired
    -- after the wipe don't try to double-remove already-cleared icons.
    self.osiPrison      = {}
    self.osiInstability = {}
    self.osiSynergy     = {}

    -- Hide world-coord position icons without discarding the handles  -
    -- they will be shown again when the relevant mechanics fire next pull.
    showPosIcons(_posIconConn,  false)
    showPosIcons(_posIconBlood, false)
    -- Reset torturer icons to their idle (blue) state.
    if _posIconTorturer then
        for name in pairs(TORTURER_NODES) do
            updateTorturerIcon(_posIconTorturer, name,
                               TORTURER_TEX.blue, Colors.ICE)
        end
        showPosIcons(_posIconTorturer, false)
    end

    -- Reset stage and all per-pull mechanic flags.
    self.CURRENT_STAGE      = 1
    self.bMove              = true
    self.bBlock             = true
    self.bConnect           = true
    self.bStartTorturerCD   = true
    self.torturerCount      = 8
    self.activeFeedTorturer = false

    -- Reset prisoner feed-stack counters for all 8 torturers.
    for name in pairs(self.PRISONERS) do self.PRISONERS[name] = 0 end
end

-- Debug-gated coordinate report.  Prints the player's live world position
-- next to the arena AABB and one representative node from each marker table,
-- so a single visit to the arena settles whether the node tables share the
-- game's world-coordinate space.  Costs nothing when debug is off: Log.debug
-- early-returns, and the guard skips the formatting entirely.
--
-- Reading it: stand anywhere in the arena. `player` should fall inside the
-- AABB on all three axes.  If it does but the node x/z values are an order
-- of magnitude away, the node tables need re-deriving  -  stand on the first
-- connection node (wall end of the north-left line) and compare against LN1.
local function checkNodeCoordSpace()
    if not Log.isEnabled() then return end
    local _, px, py, pz = GetUnitWorldPosition("player")
    Log.debug("falgravn coords: player = %.0f / %.0f / %.0f", px, py, pz)
    Log.debug("  arena AABB   x 73700-84500  y 6000-22500  z 50200-61900")
    Log.debug("  CONN LN1     %d / %d / %d",
        CONN_NODES.LN1[1], CONN_NODES.LN1[2], CONN_NODES.LN1[3])
    Log.debug("  BLOOD #1     %d / %d / %d",
        BLOOD_NODES[1].x, BLOOD_NODES[1].y, BLOOD_NODES[1].z)
    Log.debug("  TORTURER Ama %d / %d / %d",
        TORTURER_NODES.Ama[1], TORTURER_NODES.Ama[2], TORTURER_NODES.Ama[3])

    local inX = px > 73700  and px < 84500
    local inY = py > 6000   and py < 22500
    local inZ = pz > 50200  and pz < 61900
    if not (inX and inY and inZ) then
        Log.warn("falgravn: player is OUTSIDE the detection AABB "
            .. "(x=%s y=%s z=%s)  -  the box itself needs re-measuring",
            tostring(inX), tostring(inY), tostring(inZ))
    end
end

function Falgravn:onEnter(context, alerts)
    checkNodeCoordSpace()
    self.showPercentUI = Settings.trial("ka").showPercent
    if Settings.trial("ka").posIconsFalgravn then
        -- Deferred so OSI has finished initialising.  Scheduled through
        -- :after so leaving the arena inside the 3.1 s window cancels it,
        -- rather than creating icons onLeave has already discarded.
        self:after(3100, function()
            if not _posIconConn     then _posIconConn     = createConnIcons()     end
            if not _posIconBlood    then _posIconBlood    = createBloodIcons()    end
            if not _posIconTorturer then _posIconTorturer = createTorturerIcons() end
        end)
    end
end

-- -- 200ms timer display ---------------------------------------------------
-- Layout matches BSCHTKA's Falg_UpdateUI:
--   Stage 1 -> info1=Instability
--   Stage 2 -> info1=Instability, info2=Blood Ball
--   Stage 3 -> info1=Open Gates, info2=Torturer TP countdown

function Falgravn:onUpdate(context, alerts)
    local stage = self.CURRENT_STAGE

    if stage == 1 then
        local ti = self.instabilityTimer:remaining()
        if ti > 0 then
            alerts:setRow(1, Lang.t("ka_falgravn_instability"), ti)
        else
            alerts:setRow(1, Lang.t("ka_falgravn_instability") .. " " .. Lang.t("common_up"), nil)
        end

    elseif stage == 2 then
        local ti  = self.instabilityTimer:remaining()
        local tbb = self.bloodBallTimer:remaining()
        if ti > 0 then
            alerts:setRow(1, Lang.t("ka_falgravn_instability"), ti)
        else
            alerts:setRow(1, Lang.t("ka_falgravn_instability") .. " " .. Lang.t("common_up"), nil)
        end
        if tbb > 0 then
            alerts:setRow(2, Lang.t("ka_falgravn_blood_ball"), tbb)
        else
            alerts:setRow(2, Lang.t("ka_falgravn_blood_ball") .. " " .. Lang.t("common_soon"), nil)
        end

    elseif stage == 3 then
        local tog = self.openGatesTimer:remaining()
        local ttp = self.torturerTimer:remaining()
        if tog > 0 then
            alerts:setRow(1, Lang.t("ka_falgravn_open_gates"), tog)
        else
            alerts:setRow(1, Lang.t("ka_falgravn_open_gates") .. " " .. Lang.t("common_soon"), nil)
        end
        if ttp > 0 then
            alerts:setRow(2, Lang.t("ka_falgravn_torturer_tp"), ttp)
        else
            alerts:clearRow(2)
        end
    end
end

-- -- Handlers ------------------------------------------------------------
-- (Falgravn has no shared common module.)

-- DIED: stop CA bars for the dead unit and its killer.
function Falgravn:onDied(context, alerts,
                          unitTag, sourceUnitTag, sourceUnitId, unitId,
                          sourceUnitName, unitName)
    if unitId then
        CA.castAlertsStop(self.alertList[unitId])
        self.alertList[unitId] = nil
    end
    if sourceUnitId then
        CA.castAlertsStop(self.alertList[sourceUnitId])
        self.alertList[sourceUnitId] = nil
    end
end

local function handleInfuserCasts(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    alerts:showAction(Lang.t("ka_falgravn_interrupt_inf"))
    local cid = CA.ranged(abilityId, sourceUnitName, 1000, Colors.BLUE)
    if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
end

local function handleInfuserBuff(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ka_falgravn_inf_buff"))
    CA.alert(nil, Lang.t("ka_falgravn_inf_buff"), 0xFF8800FF, SOUNDS.DUEL_START, 3000)
end

-- HM confirmation ability (plain entry: receives result).
local function handleFalgravnHm(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        self.bHM = true
        alerts:showHeader(GetUnitName("boss1") .. Lang.t("ka_falgravn_hm_suffix"))
    elseif result == ACTION_RESULT_EFFECT_FADED then
        alerts:showHeader(GetUnitName("boss1"))
        self:after(2000, function()
            if not IsUnitInCombat("player") then self.bHM = false end
        end)
    end
end

-- Njordal: Move AoE (plain entry; deduped via bMove flag).
local function handleNjordalMove(self, context, alerts, result, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_BEGIN and self.bMove then
        self.bMove = false
        alerts:showAction(Lang.t("ka_falgravn_move"))
        local cid = CA.bar(abilityId, GetAbilityName(abilityId),
            12000, 12000, Colors.FLYZONE, 0.5,
            { 12000, Lang.t("ka_falgravn_move"), 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bMove then
        self.bMove = true
    end
end

-- Njordal: Block Cast (plain entry; deduped; icon uses heavy-attack ID).
local function handleNjordalBlock(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_BEGIN and self.bBlock then
        self.bBlock = false
        alerts:showAction(Lang.t("ka_falgravn_block_cast"))
        local cid = CA.bar(FALGRAVN_M_BLOCK_HEAVY, "Bloody Frenzy",
            6500, 6500, Colors.FLYZONE, 0.5,
            { 6500, Lang.t("ka_falgravn_block_cast"), 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bBlock then
        self.bBlock = true
    end
end

local function handleBloodCleave(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    alerts:showAction(Lang.t("ka_falgravn_dodge"))
    local dur = CastDur.get(FALGRAVN_M_CLEAVE, FALLBACK_DUR)
    CA.bar(abilityId, sourceUnitName, dur, dur, Colors.MAGENTA, 0.4,
        { 700, Lang.t("ka_falgravn_dodge"), 1, 0, 0.6, 0.8, SOUNDS.CHAMPION_POINTS_COMMITTED })
end

local function handleBloodFountain(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    alerts:showAction(Lang.t("ka_falgravn_block_fountain"))
    CA.ranged(FALGRAVN_BLOOD_FOUNT, sourceUnitName, 3033, Colors.MAGENTA)
end

-- Lightning / connection (plain entry; deduped via bConnect flag).
-- BEGIN -> show connection-node floor icons so players can see which nodes to stand on.
local function handleLightning(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_BEGIN and self.bConnect then
        self.bConnect = false
        showPosIcons(_posIconConn, true)
        -- DEBUG: log Falgravn's world position when the conga-line mechanic fires
        -- so we can verify GetUnitWorldPosition("boss1") returns meaningful values.
        local _, bx, by, bz = GetUnitWorldPosition("boss1")
        Log.debug("[LN-DEBUG] Lightning BEGIN | boss1 world: x=%.0f y=%.0f z=%.0f",
            bx or -1, by or -1, bz or -1)
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bConnect then
        self.bConnect = true
    end
end

-- Pulse fades -> clear connection-node rows 2-4 and hide floor icons.
local function handlePulse(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_FADED then
        alerts:clearRow(2); alerts:clearRow(3); alerts:clearRow(4)
        showPosIcons(_posIconConn, false)
    end
end

-- Instability timer reset (plain entry: fires on EFFECT_GAINED_DURATION).
local function handleInstabilityCombat(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.instabilityTimer:reset(NEXT_INSTABILITY)
    end
end

local function handleUnwPower(self, context, alerts, abilityId, ...)
    self.bloodBallTimer:reset(INITIAL_BLOODBALL_DELAY)
    self.instabilityTimer:reset(INSTABILITY_INITIAL_DELAY)
end

-- Blood Ball (plain entry: updates Stage 2 state and bloodBallTimer).
-- EFFECT_GAINED_DURATION -> show blood-node floor icons; ensure torturer icons are up too.
local function handleBloodBall(self, context, alerts, result, abilityId, ...)
    if self.CURRENT_STAGE ~= 2 then self.CURRENT_STAGE = 2 end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.bloodBallTimer:reset(30)
        showPosIcons(_posIconBlood, true)
        showPosIcons(_posIconTorturer, true)   -- arm if handleStartStage2 didn't fire
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.bloodBallTimer:reset(NEXT_BLOODBALL)
    end
end

local function handleStartStage2(self, context, alerts, abilityId, ...)
    if self.CURRENT_STAGE ~= 2 then
        self.CURRENT_STAGE = 2
        showPosIcons(_posIconTorturer, true)
    end
end

local function handleShatterMid(self, context, alerts, abilityId, ...)
    if self.CURRENT_STAGE ~= 3 then
        self.CURRENT_STAGE = 3
        self.openGatesTimer:reset(INITIAL_OPENGATE_TIME)
        alerts:clearRow(2); alerts:clearRow(3); alerts:clearRow(4)
        -- Floor drops; connection/blood nodes no longer relevant.
        showPosIcons(_posIconConn,  false)
        showPosIcons(_posIconBlood, false)
    end
end

-- Open Gates: recurring timer + 25 s delayed heavy-attack alert for tanks.
local function handleOpenDoor(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    self.openGatesTimer:reset(NEXT_OPENGATE_TIME)
    self.torturerTimer:reset(NEXT_TORTURER_TP)
    alerts:showAction(Lang.t("ka_falgravn_open_gates_action"))
    CA.alert(nil, Lang.t("ka_falgravn_open_gates_action"), 0x991111FF,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
    local capturedSrc = sourceUnitName or ""
    -- Re-arming mechanic: drop the previous window before opening a new one.
    self:cancelAfter(self.openGatesDelayTimer)
    self.openGatesDelayTimer = self:after(25000, function()
        self.openGatesDelayTimer = false
        if not IsUnitInCombat("player") then return end
        CA.ranged(FALGRAVN_OPEN_DOOR, capturedSrc, 7500, Colors.BLUE)
    end)
end

-- Torturer feeding: kill countdown (plain entry; deduped per feed cycle).
-- EFFECT_GAINED -> mark the feeding torturer's floor icon yellow.
local function handleTorturerFeed(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if result == ACTION_RESULT_EFFECT_GAINED then
        if self.bStartTorturerCD then
            self.bStartTorturerCD = false
            alerts:showAction(Lang.t("ka_falgravn_kill_torturer"))
            local cid = CA.bar(abilityId, GetAbilityName(abilityId),
                10000, 10000, Colors.FLYZONE, 0.5,
                { 10000, Lang.t("ka_falgravn_kill_torturer"), 0.8, 0, 0, 0.9, SOUNDS.NONE })
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
        -- Turn the active torturer's icon yellow so raiders can see which one to kill.
        -- unitName is the prisoner (target of the feed ability), which keys TORTURER_NODES.
        local name = zo_strformat("<<1>>", unitName)
        if name and name ~= "" then
            self.activeFeedTorturer = name
            updateTorturerIcon(_posIconTorturer, name, TORTURER_TEX.yellow, Colors.YELLOW)
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.bStartTorturerCD  = true
        self.activeFeedTorturer = false
    end
end

-- Prisoner saved (plain entry; decrements torturer count).
-- Use unitName (the saved prisoner's name, which matches the torturer node
-- key) directly from the event, rather than relying on activeFeedTorturer
-- state  -  this avoids the stale-name risk when two feeds overlap in Stage 3.
local function handleSacrifice(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    self.torturerCount = self.torturerCount - 1
    local name = zo_strformat("<<1>>", unitName)
    if name and name ~= "" then
        updateTorturerIcon(_posIconTorturer, name,
                           TORTURER_TEX.green, Colors.GREEN)
    end
    self.activeFeedTorturer = false
end

local function handleTorturerEsc(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ka_falgravn_torturer_down"))
    CA.alert(nil, Lang.t("ka_falgravn_torturer_down"), 0xFF8800FF,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

local function handleTorturerLa(self, context, alerts, abilityId, unitTag, ...)
    if IsUnitPlayer(unitTag) and GetSelectedLFGRole() ~= LFG_ROLE_TANK then
        alerts:showAction(Lang.t("ka_falgravn_dodge_torturer"))
        CA.alert(Lang.t("ka_falgravn_torturer_la_label"), Lang.t("ka_falgravn_dodge"), 0xFF0000FF, SOUNDS.DUEL_START, 1000)
    end
end

-- Instability animated icon: shared handler for HM (140944) and non-HM (140941).
-- Starts the 40-frame animation cycle on EFFECT_GAINED; stops it on EFFECT_FADED.
local function handleInstabilityEffect(self, context, alerts, changeType, abilityId,
                                        unitTag, unitId, unitName, stackCount)
    if not IsUnitPlayer(unitTag) then return end
    if changeType == EFFECT_RESULT_GAINED then
        local dn = GetUnitDisplayName(unitTag)
        if dn and dn ~= "" then
            self.osiInstability[unitTag] = dn
            startInstAnim(unitTag, dn)
        end
    elseif changeType == EFFECT_RESULT_FADED then
        stopInstAnim(unitTag)
        osiRemove(self.osiInstability[unitTag])
        self.osiInstability[unitTag] = nil
    end
end

local function handlePrisonEffect(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    -- Prison can be active on more than one player at a time, so the bar id
    -- is keyed by unitTag alongside the OSI icon.  A single shared field
    -- meant the second GAINED overwrote the first player's id, leaving that
    -- bar running until its own duration expired while the following FADED
    -- stopped the second bar twice.
    if changeType == EFFECT_RESULT_GAINED then
        alerts:showAction(Lang.t("ka_falgravn_kill_prison"))
        local dur = 8000
        -- Re-application on the same player: drop the stale bar first.
        CA.castAlertsStop(self.prisonBars[unitTag])
        self.prisonBars[unitTag] = CA.bar(
            abilityId, GetAbilityName(abilityId),
            dur, dur, Colors.FLYZONE, 0.5,
            { dur, Lang.t("ka_falgravn_kill_prison"), 0.8, 0, 0, 0.9, SOUNDS.NONE })
        local dn = GetUnitDisplayName(unitTag)
        osiSet(dn, ICON_PRISON, Colors.PURPLE)
        if dn and dn ~= "" then self.osiPrison[unitTag] = dn end
    elseif changeType == EFFECT_RESULT_FADED then
        CA.castAlertsStop(self.prisonBars[unitTag])
        self.prisonBars[unitTag] = nil
        osiRemove(self.osiPrison[unitTag])
        self.osiPrison[unitTag] = nil
    end
end

local function handlePrisonerFeeding(self, context, alerts, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    local name = zo_strformat("<<1>>", unitName)
    if self.PRISONERS[name] ~= nil then
        self.PRISONERS[name] = self.PRISONERS[name] + 1
        if self.PRISONERS[name] == 11 then
            self.torturerCount = self.torturerCount - 1
            -- 11 stacks = prisoner dead; mark the torturer's icon red.
            updateTorturerIcon(_posIconTorturer, name, TORTURER_TEX.red, Colors.RED)
        end
    end
end

local function handleBlopSynergie(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    if not IsUnitPlayer(unitTag) then return end
    if changeType == EFFECT_RESULT_GAINED then
        local dn = GetUnitDisplayName(unitTag)
        osiSet(dn, ICON_SYNERGY, Colors.CRIMSON)
        if dn and dn ~= "" then self.osiSynergy[unitTag] = dn end
    elseif changeType == EFFECT_RESULT_FADED then
        osiRemove(self.osiSynergy[unitTag])
        self.osiSynergy[unitTag] = nil
    end
end

-- DEBUG: Lightning Conduit position probe.
-- FALGRAVN_LINK_EFFECT (133433) is placed on each Lightning Conduit OBJECT
-- when a conga line spawns (source = Falgravn, target = conduit unitTag).
-- This handler dumps the conduit's world position so we can verify:
--   a) GetUnitWorldPosition works on OBJECT-type units from effect events, and
--   b) the quadrant of the position (x vs 0.5 / y vs 0.5 on the normalised map)
--      reliably identifies which of the 4 lines (LN/LS/RN/RS) spawned.
-- Remove this once conduit identification is confirmed and the real routing is built.
local function handleLinkEffect(self, context, alerts, changeType, abilityId,
                                 unitTag, unitId, unitName, stackCount)
    if changeType ~= EFFECT_RESULT_GAINED then return end
    local valid = IsUnitValid(unitTag)
    local name  = GetUnitName(unitTag) or "?"
    local _, cx, cy, cz = GetUnitWorldPosition(unitTag)
    Log.debug("[LN-DEBUG] Conduit LINK_EFFECT gained | unitTag=%s unitId=%s valid=%s name=%s world=(%.0f,%.0f,%.0f)",
        tostring(unitTag), tostring(unitId), tostring(valid), tostring(name),
        cx or -1, cy or -1, cz or -1)
end

-- -- Routing tables (C3) --------------------------------------------------

Falgravn.combatRoutes = {
    -- -- Infuser trash ------------------------------------------------------
    [INFUSER_CASTS]        = { result = ACTION_RESULT_BEGIN,         fn = handleInfuserCasts },
    [INFUSER_BUFF]         = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleInfuserBuff },
    -- -- HM confirmation ability --------------------------------------------
    [FALGRAVN_HM]          = handleFalgravnHm,
    -- -- Njordal ------------------------------------------------------------
    [FALGRAVN_M_MOVE]      = handleNjordalMove,
    [FALGRAVN_M_BLOCK]     = handleNjordalBlock,
    [FALGRAVN_M_CLEAVE]    = { result = ACTION_RESULT_BEGIN,         fn = handleBloodCleave },
    [FALGRAVN_BLOOD_FOUNT] = { result = ACTION_RESULT_BEGIN,         fn = handleBloodFountain },
    -- -- Lightning / connection ---------------------------------------------
    [FALGRAVN_LIGHTNING]   = handleLightning,
    [FALGRAVN_PULSE]       = handlePulse,
    -- -- Instability --------------------------------------------------------
    [FALGRAVN_INSTABILITY] = handleInstabilityCombat,
    -- -- Stage 2 ------------------------------------------------------------
    [FALGRAVN_UNW_POWER]   = { result = ACTION_RESULT_EFFECT_FADED,  fn = handleUnwPower },
    [FALGRAVN_BLOOTBALL]   = handleBloodBall,
    [FALGRAVN_START_STAGE2]= { result = ACTION_RESULT_BEGIN,         fn = handleStartStage2 },
    -- -- Stage 3 ------------------------------------------------------------
    [FALGRAVN_SHATTER_MID] = { result = ACTION_RESULT_BEGIN,         fn = handleShatterMid },
    [FALGRAVN_OPEN_DOOR]   = { result = ACTION_RESULT_BEGIN,         fn = handleOpenDoor },
    -- -- Torturer ------------------------------------------------------------
    [FALGRAVN_TUT_FEED]    = handleTorturerFeed,
    [FALGRAVN_SACRIFICE]   = handleSacrifice,
    [FALGRAVN_TORTURER_ESC]= { result = ACTION_RESULT_BEGIN,         fn = handleTorturerEsc },
    [FALGRAVN_TORTURER_LA] = { result = ACTION_RESULT_BEGIN,         fn = handleTorturerLa },
}

-- -- Effect routing tables (C3) -------------------------------------------

Falgravn.effectRoutes = {
    [FALGRAVN_PRISON]       = handlePrisonEffect,
    [FALGRAVN_INSTABILITY]  = handleInstabilityEffect,
    [FALGRAVN_INSTABILITY2] = handleInstabilityEffect,
    [FALGRAVN_PRISONER_F]   = { changeType = EFFECT_RESULT_GAINED, fn = handlePrisonerFeeding },
    [FALGRAVN_BLOPSYNERGIE] = handleBlopSynergie,
    -- DEBUG: conduit position probe; remove after LN/LS/RN/RS identification is confirmed.
    [FALGRAVN_LINK_EFFECT]  = { changeType = EFFECT_RESULT_GAINED, fn = handleLinkEffect },
}

package.loaded["trial.ka.boss.Falgravn"] = Falgravn
return Falgravn
