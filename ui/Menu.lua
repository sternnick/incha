--- Settings UI entry point.
---
--- Registers an in-game settings panel via LibAddonMenu-2.0 (LAM) when it
--- is present, and always registers ADDON_SLASH as a slash-command fallback.
---
--- LAM panel ID: ADDON_LAM  (set in bootstrap.lua)
--- Slash command: ADDON_SLASH  (debug | lock | scale <n> | reset | dp | preview <sub>)

local Log         = require("lib.Log")
local Panel       = require("ui.Panel")
local Preview     = require("ui.Preview")
local Settings    = require("core.Settings")
local Fmt         = require("core.Fmt")
local DebugPanel  = require("ui.DebugPanel")
local Thresholds  = require("ui.Thresholds")
local ZoneManager = require("core.ZoneManager")

local Menu = {}

-- Trial "Enable" checkboxes write the flag and then ask ZoneManager to
-- re-evaluate, so toggling a trial while already standing in its zone takes
-- effect immediately instead of on the next zone change.
local function setTrialEnabled(trialId, v)
    Settings.get().trials[trialId].enabled = v
    ZoneManager.refresh()
end

-- Dispatch table for /incha preview <sub> and /ip <sub>.
-- Keys match the sub-command strings; values are the Preview functions to call.
local function resetOverlay()
    local sv = Settings.get()
    sv.overlay.offsetX = -1
    sv.overlay.offsetY = -1
    sv.overlay.alertX  = -1
    sv.overlay.alertY  = -1
    sv.overlay.scale   = 1.0
    Panel.refresh()
    Log.print("Overlay positions reset")
end

local PREVIEW_CMDS = {
    panel  = Preview.showPanel,
    inst   = Preview.showInstability,
    border = Preview.showCaBorder,
    alert  = Preview.showCaAlert,
    clear  = Preview.clear,
    reset  = resetOverlay,
}

local PANEL_ID = ADDON_LAM

-- -- LAM panel descriptor ---------------------------------------------------
local PANEL = {
    type                = "panel",
    name                = ADDON_TITLE,
    displayName         = Fmt.c(Fmt.GOLD, ADDON_TITLE),
    author              = "Oseias",
    version             = ADDON_VERSION,
    slashCommand        = ADDON_SLASH,
    registerForRefresh  = false,
    registerForDefaults = false,
}

-- -- Options schema ---------------------------------------------------------
-- Each entry is a LAM control descriptor.  getFunc/setFunc read and write
-- directly into the live Settings table so no extra glue is needed.
-- Keep in sync with the defaults in core/Settings.lua.

local OPTIONS = {
    -- Section: general
    {
        type    = "header",
        name    = "General",
    },
    {
        type     = "checkbox",
        name     = "Debug logging",
        tooltip  = "Print internal state to chat. Leave off in normal play.",
        getFunc  = function() return Settings.get().debug end,
        setFunc  = function(v)
            Settings.get().debug = v
            Log.setEnabled(v)
        end,
    },

    -- Section: overlay
    {
        type = "header",
        name = "Overlay",
    },
    {
        type    = "checkbox",
        name    = "Lock position",
        tooltip = "Prevent the overlay from being dragged.",
        getFunc = function() return Settings.get().overlay.locked end,
        setFunc = function(v)
            Settings.get().overlay.locked = v
            Panel.refresh()
        end,
    },
    {
        type        = "slider",
        name        = "Scale",
        tooltip     = "Resize the overlay panel.",
        min         = 0.5,
        max         = 3.0,
        step        = 0.05,
        decimals    = 2,
        getFunc     = function() return Settings.get().overlay.scale end,
        setFunc     = function(v)
            Settings.get().overlay.scale = v
            Panel.refresh()
        end,
    },

    -- Section: Kyne's Aegis
    {
        type = "header",
        name = "Kyne's Aegis",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Yandir totem/gryphon timers, Vrol fog/portal/conduit timers, and Falgravn stage mechanics.",
        getFunc = function() return Settings.get().trials.ka.enabled end,
        setFunc = function(v) setTrialEnabled("ka", v) end,
    },
    {
        type    = "checkbox",
        name    = "Yandir the Butcher",
        getFunc = function() return Settings.get().trials.ka.bosses.yandir end,
        setFunc = function(v) Settings.get().trials.ka.bosses.yandir = v end,
    },
    {
        type    = "checkbox",
        name    = "Captain Vrol",
        getFunc = function() return Settings.get().trials.ka.bosses.vrol end,
        setFunc = function(v) Settings.get().trials.ka.bosses.vrol = v end,
    },
    {
        type    = "checkbox",
        name    = "Lord Falgravn",
        getFunc = function() return Settings.get().trials.ka.bosses.falgravn end,
        setFunc = function(v) Settings.get().trials.ka.bosses.falgravn = v end,
    },
    {
        type    = "checkbox",
        name    = "Show % milestones",
        tooltip = "Show action alerts at key health thresholds (Falgravn etc.)",
        getFunc = function() return Settings.get().trials.ka.showPercent end,
        setFunc = function(v) Settings.get().trials.ka.showPercent = v end,
    },
    {
        type    = "checkbox",
        name    = "Vrol portal icon",
        tooltip = "Show a floor marker when Vrol's portal spawns.",
        getFunc = function() return Settings.get().trials.ka.portalIconVrol end,
        setFunc = function(v) Settings.get().trials.ka.portalIconVrol = v end,
    },
    {
        type    = "checkbox",
        name    = "Falgravn floor icons",
        tooltip = "Show connection-node, blood-ball, and torturer position icons on Falgravn (requires OdySupportIcons).",
        getFunc = function() return Settings.get().trials.ka.posIconsFalgravn end,
        setFunc = function(v) Settings.get().trials.ka.posIconsFalgravn = v end,
    },

    -- Section: Sunspire
    {
        type = "header",
        name = "Sunspire",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Lokke laser/tomb timers, Yolna/Nahvii mechanics, and shared-add alerts.",
        getFunc = function() return Settings.get().trials.ss.enabled end,
        setFunc = function(v) setTrialEnabled("ss", v) end,
    },
    {
        type    = "checkbox",
        name    = "Lokkestiiz",
        getFunc = function() return Settings.get().trials.ss.bosses.lokke end,
        setFunc = function(v) Settings.get().trials.ss.bosses.lokke = v end,
    },
    {
        type    = "checkbox",
        name    = "Yolnahkriin",
        getFunc = function() return Settings.get().trials.ss.bosses.yolna end,
        setFunc = function(v) Settings.get().trials.ss.bosses.yolna = v end,
    },
    {
        type    = "checkbox",
        name    = "Nahviintaas",
        getFunc = function() return Settings.get().trials.ss.bosses.nahvii end,
        setFunc = function(v) Settings.get().trials.ss.bosses.nahvii = v end,
    },

    -- Section: Rockgrove
    {
        type = "header",
        name = "Rockgrove",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        getFunc = function() return Settings.get().trials.rg.enabled end,
        setFunc = function(v) setTrialEnabled("rg", v) end,
    },
    {
        type    = "checkbox",
        name    = "Oaxiltso",
        getFunc = function() return Settings.get().trials.rg.bosses.oaxiltso end,
        setFunc = function(v) Settings.get().trials.rg.bosses.oaxiltso = v end,
    },
    {
        type    = "checkbox",
        name    = "Bahsei the Unyielding",
        getFunc = function() return Settings.get().trials.rg.bosses.bahsei end,
        setFunc = function(v) Settings.get().trials.rg.bosses.bahsei = v end,
    },
    {
        type    = "checkbox",
        name    = "Xalvakka",
        getFunc = function() return Settings.get().trials.rg.bosses.xalvakka end,
        setFunc = function(v) Settings.get().trials.rg.bosses.xalvakka = v end,
    },

    -- Section: Dreadsail Reef
    {
        type = "header",
        name = "Dreadsail Reef",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        getFunc = function() return Settings.get().trials.dsr.enabled end,
        setFunc = function(v) setTrialEnabled("dsr", v) end,
    },
    {
        type    = "checkbox",
        name    = "Lylanar and Oraneth",
        getFunc = function() return Settings.get().trials.dsr.bosses.lylanar end,
        setFunc = function(v) Settings.get().trials.dsr.bosses.lylanar = v end,
    },
    {
        type    = "checkbox",
        name    = "The Reef Guardian",
        getFunc = function() return Settings.get().trials.dsr.bosses.reef_guardian end,
        setFunc = function(v) Settings.get().trials.dsr.bosses.reef_guardian = v end,
    },
    {
        type    = "checkbox",
        name    = "Taleria",
        getFunc = function() return Settings.get().trials.dsr.bosses.taleria end,
        setFunc = function(v) Settings.get().trials.dsr.bosses.taleria = v end,
    },

    -- Section: Asylum Sanctorium
    {
        type = "header",
        name = "Asylum Sanctorium",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Olms timers, Llothis/Felms dormant state, and Protector shield.",
        getFunc = function() return Settings.get().trials.as.enabled end,
        setFunc = function(v) setTrialEnabled("as", v) end,
    },
    {
        type    = "checkbox",
        name    = "Olms the Consummate",
        getFunc = function() return Settings.get().trials.as.bosses.olms end,
        setFunc = function(v) Settings.get().trials.as.bosses.olms = v end,
    },
    {
        type    = "checkbox",
        name    = "Show % milestones",
        tooltip = "Pre-warn at each Olms health threshold where Gusts of Steam (Jump!) is expected.",
        getFunc = function() return Settings.get().trials.as.showPercent end,
        setFunc = function(v) Settings.get().trials.as.showPercent = v end,
    },

    -- Section: Cloudrest
    {
        type = "header",
        name = "Cloudrest",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track mini-boss timers (Siroria/Relequen/Galenwe), portal countdown, and Z'Maja mechanics.",
        getFunc = function() return Settings.get().trials.cr.enabled end,
        setFunc = function(v) setTrialEnabled("cr", v) end,
    },
    {
        type    = "checkbox",
        name    = "Z'Maja",
        getFunc = function() return Settings.get().trials.cr.bosses.zmaja end,
        setFunc = function(v) Settings.get().trials.cr.bosses.zmaja = v end,
    },
    {
        type    = "checkbox",
        name    = "Show mechanic icons",
        tooltip = "Show OdySupportIcons player markers for Frost/Gale debuffs on Z'Maja (requires OdySupportIcons).",
        getFunc = function() return Settings.get().trials.cr.posIconsZmaja end,
        setFunc = function(v) Settings.get().trials.cr.posIconsZmaja = v end,
    },

    -- Section: Sanity's Edge
    {
        type = "header",
        name = "Sanity's Edge",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Yaseyla bomb timers, Chimera despawn/chain lightning, and Ansuul calamity/phase alerts.",
        getFunc = function() return Settings.get().trials.se.enabled end,
        setFunc = function(v) setTrialEnabled("se", v) end,
    },
    {
        type    = "checkbox",
        name    = "Yaseyla",
        getFunc = function() return Settings.get().trials.se.bosses.yaseyla end,
        setFunc = function(v) Settings.get().trials.se.bosses.yaseyla = v end,
    },
    {
        type    = "checkbox",
        name    = "The Chimera",
        getFunc = function() return Settings.get().trials.se.bosses.chimera end,
        setFunc = function(v) Settings.get().trials.se.bosses.chimera = v end,
    },
    {
        type    = "checkbox",
        name    = "Ansuul the Tormentor",
        getFunc = function() return Settings.get().trials.se.bosses.ansuul end,
        setFunc = function(v) Settings.get().trials.se.bosses.ansuul = v end,
    },
    {
        type    = "checkbox",
        name    = "Show % milestones",
        tooltip = "Alert at Yaseyla health thresholds when Wamasu, Archer, portal, and Shrapnel waves are expected.",
        getFunc = function() return Settings.get().trials.se.showPercent end,
        setFunc = function(v) Settings.get().trials.se.showPercent = v end,
    },

    -- Section: Lucent Citadel
    {
        type = "header",
        name = "Lucent Citadel",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track side assignment (Ryelaz/Zilyesset), Orphic Xoryn jump/cone timers, Xynizata interrupt CDs, and Xoryn current/knot alerts.",
        getFunc = function() return Settings.get().trials.lc.enabled end,
        setFunc = function(v) setTrialEnabled("lc", v) end,
    },
    {
        type    = "checkbox",
        name    = "Ryelaz",
        getFunc = function() return Settings.get().trials.lc.bosses.ryelaz end,
        setFunc = function(v) Settings.get().trials.lc.bosses.ryelaz = v end,
    },
    {
        type    = "checkbox",
        name    = "Sahdina Dariel",
        getFunc = function() return Settings.get().trials.lc.bosses.dariel end,
        setFunc = function(v) Settings.get().trials.lc.bosses.dariel = v end,
    },
    {
        type    = "checkbox",
        name    = "Orphic Xoryn",
        getFunc = function() return Settings.get().trials.lc.bosses.orphic end,
        setFunc = function(v) Settings.get().trials.lc.bosses.orphic = v end,
    },
    {
        type    = "checkbox",
        name    = "Xynizata",
        getFunc = function() return Settings.get().trials.lc.bosses.xynizata end,
        setFunc = function(v) Settings.get().trials.lc.bosses.xynizata = v end,
    },
    {
        type    = "checkbox",
        name    = "Xoryn the Unbound",
        getFunc = function() return Settings.get().trials.lc.bosses.xoryn end,
        setFunc = function(v) Settings.get().trials.lc.bosses.xoryn = v end,
    },

    -- Section: Ossein Cage
    {
        type = "header",
        name = "Ossein Cage",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Jynorah dragon leap/clash phases, Kazpian chain/portal/channeler alerts, and Shaper of Flesh shield status.",
        getFunc = function() return Settings.get().trials.oc.enabled end,
        setFunc = function(v) setTrialEnabled("oc", v) end,
    },
    {
        type    = "checkbox",
        name    = "Jynorah",
        getFunc = function() return Settings.get().trials.oc.bosses.jynorah end,
        setFunc = function(v) Settings.get().trials.oc.bosses.jynorah = v end,
    },
    {
        type    = "checkbox",
        name    = "Kazpian",
        getFunc = function() return Settings.get().trials.oc.bosses.kazpian end,
        setFunc = function(v) Settings.get().trials.oc.bosses.kazpian = v end,
    },
    {
        type    = "checkbox",
        name    = "Shaper of Flesh",
        getFunc = function() return Settings.get().trials.oc.bosses.shaper end,
        setFunc = function(v) Settings.get().trials.oc.bosses.shaper = v end,
    },

    -- Section: Preview --------------------------------------------------------
    -- Lets you fire each UI element from the settings panel without entering
    -- combat.  Useful for checking overlay position, scale, and readability.
    {
        type = "header",
        name = "Preview",
    },
    {
        type    = "description",
        title   = "",
        text    = "Fire UI elements without entering combat.  Use Clear when done.",
    },
    {
        type = "button",
        name = "Panel: sample data",
        tooltip = "Fill the overlay with a realistic header, two timer lines, and an action alert.",
        func = function() Preview.showPanel() end,
    },
    {
        type = "button",
        name = "Instability icon",
        tooltip = "Start the animated instability head-icon on your own character (requires OdySupportIcons).",
        func = function() Preview.showInstability() end,
    },
    {
        type = "button",
        name = "CA: border flash",
        tooltip = "Flash the red screen-edge danger border for 3 s (requires CombatAlerts).",
        func = function() Preview.showCaBorder() end,
    },
    {
        type = "button",
        name = "CA: text alert",
        tooltip = "Fire a CombatAlerts text flash for 3 s (requires CombatAlerts).",
        func = function() Preview.showCaAlert() end,
    },
    {
        type = "button",
        name = "Clear all",
        tooltip = "Stop the animation, clear the overlay, and dismiss the CA border.",
        func = function() Preview.clear() end,
    },
}

-- -- Slash command fallback ------------------------------------------------

local function printHelp()
    Log.print("Commands:")
    Log.print("  %s debug          -  toggle debug logging",    ADDON_SLASH)
    Log.print("  %s lock           -  toggle overlay drag lock", ADDON_SLASH)
    Log.print("  %s scale <n>      -  set overlay scale (0.5 - 3.0)", ADDON_SLASH)
    Log.print("  %s reset          -  reset both overlay panels to default position", ADDON_SLASH)
    Log.print("  %s status         -  dump trial / boss / tracker panel state", ADDON_SLASH)
    Log.print("  %s thresholds     -  HM health-threshold inventory + live samples", ADDON_SLASH)
    Log.print("  %s dp             -  toggle the debug replay panel (also /idp)", ADDON_SLASH)
    Log.print("  /ip panel          -  show sample panel data (use /ip, not /incha)")
    Log.print("  /ip inst           -  animate instability head icon")
    Log.print("  /ip border         -  flash CA border")
    Log.print("  /ip alert          -  show CA text alert")
    Log.print("  /ip reset          -  reset both overlay panels to default position")
    Log.print("  /ip clear          -  clear all preview effects")
    Log.print("  /ip <log line>     -  replay a raw encounter-log line (BEGIN_CAST / COMBAT_EVENT / EFFECT_CHANGED)")
end

local function handleDebugPanel()
    zo_callLater(DebugPanel.toggle, 200)
end

local function handleSlash(text)
    local cmd, arg = (text or ""):lower():match("^%s*(%S*)%s*(.*)")
    local sv = Settings.get()

    if cmd == "dp" then
        handleDebugPanel()

    elseif cmd == "debug" then
        sv.debug = not sv.debug
        Log.setEnabled(sv.debug)
        Log.print("Debug %s", sv.debug and Fmt.c(Fmt.GREEN, "ON") or Fmt.c("FF4444", "OFF"))

    elseif cmd == "lock" then
        sv.overlay.locked = not sv.overlay.locked
        Panel.refresh()
        Log.print("Overlay %s", sv.overlay.locked and "locked" or "unlocked")

    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 3.0 then
            sv.overlay.scale = n
            Panel.refresh()
            Log.print("Scale -> %s", n)
        else
            Log.print("Usage: %s scale <0.5 - 3.0>", ADDON_SLASH)
        end

    elseif cmd == "reset" then
        resetOverlay()

    elseif cmd == "status" then
        local trial = ZoneManager.getActiveTrial()
        Log.print("zone %s  trial=%s enabled=%s",
            tostring(GetZoneId(GetUnitZoneIndex("player"))),
            trial and trial.id or "none", trial and tostring(trial.enabled) or "-")
        local boss = trial and trial:getActiveBoss()
        Log.print("boss=%s injected=%s inCombat=%s",
            boss and boss.key or "none",
            trial and tostring(trial._injected) or "-",
            trial and tostring(trial.context.inCombat) or "-")
        Panel.status()

    elseif cmd == "thresholds" then
        Thresholds.dump()

    elseif cmd == "preview" then
        local sub = arg:match("^%s*(%S*)")
        local fn  = PREVIEW_CMDS[sub]
        if fn then
            zo_callLater(fn, 200)
        else
            Log.print("preview: panel | inst | border | alert | clear")
        end

    else
        printHelp()
    end
end

-- -- Public API -------------------------------------------------------------

local function handlePreviewSlash(text)
    local trimmed = (text or ""):match("^%s*(.-)%s*$") or ""

    -- Log-line replay: if the argument starts with a digit it looks like a raw
    -- encounter-log line (e.g. "225534,BEGIN_CAST,...").  Dispatch to Playback
    -- instead of the preview sub-commands.  Playback is loaded after Menu in
    -- incha.txt, so grab it lazily from package.loaded at call time.
    if trimmed:match("^%d") then
        local Playback = package.loaded["lib.Playback"]
        if not Playback then
            Log.print("/ip replay: Playback module not loaded")
            return
        end
        local status = Playback.injectLine(trimmed)
        Log.print("/ip replay: %s", status)
        return
    end

    local sub = trimmed:lower():match("^%s*(%S*)")
    -- Confirm the command was received immediately (visible in chat).
    -- The actual effect is deferred 200 ms so the HUD scene has time to
    -- return to "showing" after the chat input closes before we call
    -- applyVisibility() inside Panel.alerts / Preview.  Without the
    -- delay the command runs while the chat "hudui" overlay is still
    -- transitioning and hudVisible may still be false, which hides the
    -- panel immediately after showing it.
    local fn = PREVIEW_CMDS[sub]
    if fn then
        Log.print("/ip %s", sub)
        zo_callLater(fn, 200)
    else
        Log.print("/ip  panel | inst | border | alert | clear")
        Log.print("/ip  <encounter-log line>  — replay event (BEGIN_CAST, EFFECT_CHANGED)")
    end
end

function Menu.init()
    -- /incha — LAM intercepts this when the panel is registered below,
    -- so also register a standalone /ip command that LAM never touches.
    -- /ip can be used to fire preview effects while the game UI is visible.
    SLASH_COMMANDS[ADDON_SLASH] = handleSlash
    SLASH_COMMANDS["/ip"]       = handlePreviewSlash
    SLASH_COMMANDS["/idp"]      = handleDebugPanel

    -- Wire to LibAddonMenu-2.0 when it is loaded.
    -- incha.txt declares ## OptionalDependsOn: LibAddonMenu-2.0 so ESO
    -- loads LAM before Incha when both are present.
    local LAM = LibAddonMenu2
    if LAM then
        LAM:RegisterAddonPanel(PANEL_ID, PANEL)
        LAM:RegisterOptionControls(PANEL_ID, OPTIONS)
    end
end

Menu.options = OPTIONS

package.loaded["ui.Menu"] = Menu
return Menu
