--- Settings UI entry point.
---
--- Registers an in-game settings panel via LibAddonMenu-2.0 (LAM) when it
--- is present, and always registers ADDON_SLASH as a slash-command fallback.
---
--- LAM panel ID: ADDON_LAM  (set in bootstrap.lua)
--- Slash command: ADDON_SLASH  (debug | lock | scale <n> | reset)

local Log      = require("lib.Log")
local Panel    = require("ui.Panel")
local Preview  = require("ui.Preview")
local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

local Menu = {}

local PANEL_ID = ADDON_LAM

-- -- LAM panel descriptor ---------------------------------------------------
local PANEL = {
    type                = "panel",
    name                = ADDON_TITLE,
    displayName         = "|cFFD700" .. ADDON_TITLE .. "|r",
    author              = "Oseias",
    version             = "0.1.0",
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
        tooltip = "Track Yandir/Vrol/Falgravn mechanics and the overlay for this trial.",
        getFunc = function() return Settings.get().trials.ka.enabled end,
        setFunc = function(v)
            Settings.get().trials.ka.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.ka.showBossUI end,
        setFunc = function(v) Settings.get().trials.ka.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.ss.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.ss.showBossUI end,
        setFunc = function(v) Settings.get().trials.ss.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.rg.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.rg.showBossUI end,
        setFunc = function(v) Settings.get().trials.rg.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.dsr.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.dsr.showBossUI end,
        setFunc = function(v) Settings.get().trials.dsr.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.as.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.as.showBossUI end,
        setFunc = function(v) Settings.get().trials.as.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.cr.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.cr.showBossUI end,
        setFunc = function(v) Settings.get().trials.cr.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.se.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.se.showBossUI end,
        setFunc = function(v) Settings.get().trials.se.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.lc.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.lc.showBossUI end,
        setFunc = function(v) Settings.get().trials.lc.showBossUI = v end,
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
        setFunc = function(v)
            Settings.get().trials.oc.enabled = v
            ZoneManager.refresh()
        end,
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.oc.showBossUI end,
        setFunc = function(v) Settings.get().trials.oc.showBossUI = v end,
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
    d(ADDON_TAG .. " Commands:")
    d("  " .. ADDON_SLASH .. " debug          -  toggle debug logging")
    d("  " .. ADDON_SLASH .. " lock           -  toggle overlay drag lock")
    d("  " .. ADDON_SLASH .. " scale <n>      -  set overlay scale (0.5 - 3.0)")
    d("  " .. ADDON_SLASH .. " reset          -  reset overlay to default position")
    d("  /ip panel          -  show sample panel data (use /ip, not /incha)")
    d("  /ip inst           -  animate instability head icon")
    d("  /ip border         -  flash CA border")
    d("  /ip alert          -  show CA text alert")
    d("  /ip clear          -  clear all preview effects")
end

local function handleSlash(text)
    local cmd, arg = (text or ""):lower():match("^%s*(%S*)%s*(.*)")
    local sv = Settings.get()

    if cmd == "debug" then
        sv.debug = not sv.debug
        Log.setEnabled(sv.debug)
        d("|cFFD700[Incha]|r Debug " .. (sv.debug and "|c00FF00ON|r" or "|cFF4444OFF|r"))

    elseif cmd == "lock" then
        sv.overlay.locked = not sv.overlay.locked
        Panel.refresh()
        d("|cFFD700[Incha]|r Overlay " .. (sv.overlay.locked and "locked" or "unlocked"))

    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 3.0 then
            sv.overlay.scale = n
            Panel.refresh()
            d("|cFFD700[Incha]|r Scale -> " .. n)
        else
            d(ADDON_TAG .. " Usage: " .. ADDON_SLASH .. " scale <0.5 - 3.0>")
        end

    elseif cmd == "reset" then
        sv.overlay.offsetX = -1
        sv.overlay.offsetY = -1
        sv.overlay.scale   = 1.0
        Panel.refresh()
        d("|cFFD700[Incha]|r Overlay position reset")

    elseif cmd == "preview" then
        local sub = arg:match("^%s*(%S*)")
        if     sub == "panel"  then Preview.showPanel()
        elseif sub == "inst"   then Preview.showInstability()
        elseif sub == "border" then Preview.showCaBorder()
        elseif sub == "alert"  then Preview.showCaAlert()
        elseif sub == "clear"  then Preview.clear()
        else
            d(ADDON_TAG .. " preview: panel | inst | border | alert | clear")
        end

    else
        printHelp()
    end
end

-- -- Public API -------------------------------------------------------------

local function handlePreviewSlash(text)
    local sub = (text or ""):lower():match("^%s*(%S*)")
    -- Confirm the command was received immediately (visible in chat).
    -- The actual effect is deferred 200 ms so the HUD scene has time to
    -- return to "showing" after the chat input closes before we call
    -- applyVisibility() inside Panel.alerts / Preview.  Without the
    -- delay the command runs while the chat "hudui" overlay is still
    -- transitioning and hudVisible may still be false, which hides the
    -- panel immediately after showing it.
    if sub == "panel" or sub == "inst" or sub == "border"
                     or sub == "alert" or sub == "clear" then
        d(ADDON_TAG .. " /ip " .. sub)
        zo_callLater(function()
            if     sub == "panel"  then Preview.showPanel()
            elseif sub == "inst"   then Preview.showInstability()
            elseif sub == "border" then Preview.showCaBorder()
            elseif sub == "alert"  then Preview.showCaAlert()
            elseif sub == "clear"  then Preview.clear()
            end
        end, 200)
    else
        d(ADDON_TAG .. " /ip  panel | inst | border | alert | clear")
    end
end

function Menu.init()
    -- /incha — LAM intercepts this when the panel is registered below,
    -- so also register a standalone /ip command that LAM never touches.
    -- /ip can be used to fire preview effects while the game UI is visible.
    SLASH_COMMANDS[ADDON_SLASH] = handleSlash
    SLASH_COMMANDS["/ip"]       = handlePreviewSlash

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
