--- ui/Preview.lua  -  in-game preview helpers for the Incha overlay.
--- Called from LAM panel buttons in ui/Menu.lua; no dependency on combat state.
---
--- Each function is self-contained: it builds the Panel if not already built,
--- fires the relevant UI element, then returns.  Preview.clear() undoes all
--- of them at once.

local Panel         = require("ui.Panel")
local CA            = require("external-api.CombatAlerts")
local MechanicIcons = require("external-api.MechanicIcons")

local Preview = {}

-- -- Instability animated icon -----------------------------------------------
-- Mirrors the pattern in trial/ka/boss/Falgravn.lua so the preview uses the
-- same frame sequence and timing without coupling to that module.

local INST_FRAMES   = 40
local INST_INTERVAL = 50           -- ms per frame  (2 s full loop)
local INST_KEY      = "Incha_PreviewInstAnim"

local _instFrame  = 0
local _instActive = false
local _instDn     = nil            -- display name of the target (local player)

local function instAnimTick()
    if not _instDn then return end
    _instFrame = (_instFrame % INST_FRAMES) + 1
    local tex = string.format("Incha/resources/instability/frame_%02d.dds",
                              _instFrame)
    MechanicIcons.set(_instDn, tex, { 1.0, 0.6, 0.0 })
end

local function stopInstAnim()
    if _instActive then
        EVENT_MANAGER:UnregisterForUpdate(INST_KEY)
        _instActive = false
    end
    if _instDn then
        MechanicIcons.remove(_instDn)
    end
    _instDn = nil
end

-- -- Helpers -----------------------------------------------------------------

-- Ensure the Panel controls exist (safe no-op if already built, i.e. the
-- player has already visited a trial zone this session).
local function ensurePanel()
    Panel.bridge.onEnable()
end

-- -- Public API --------------------------------------------------------------

--- Fill the overlay with realistic sample data so you can check position,
--- scale, and readability without entering combat.
function Preview.showPanel()
    ensurePanel()
    Panel.alerts.header("Falgravn [HM]")
    Panel.alerts.setRow(1, "Instability", 12)
    Panel.alerts.setRow(2, "Blood Ball",   8)
    Panel.alerts.action("Prison on Oseias!")
end

--- Start the animated instability icon on the local player's head.
--- Requires OdySupportIcons; silently no-ops if OSI is not installed.
function Preview.showInstability()
    ensurePanel()
    Panel.alerts.action("Instability!")
    local dn = GetUnitDisplayName and GetUnitDisplayName("player") or nil
    if not dn or dn == "" then return end
    stopInstAnim()
    _instDn    = dn
    _instFrame = 0
    EVENT_MANAGER:RegisterForUpdate(INST_KEY, INST_INTERVAL, instAnimTick)
    _instActive = true
end

--- Flash a red CombatAlerts screen-edge border for 3 s.
--- Requires CombatAlerts; silently no-ops if CA is not installed.
function Preview.showCaBorder()
    CA.border(true, 3000, "red")
end

--- Fire a CombatAlerts text flash for 3 s.
--- Requires CombatAlerts; silently no-ops if CA is not installed.
function Preview.showCaAlert()
    CA.alert(nil, "Preview Alert!", 0xFF8800FF, SOUNDS.NONE, 3000)
end

--- Reset all preview state: stop the animation, clear the overlay,
--- and dismiss the CA border.
function Preview.clear()
    stopInstAnim()
    if Panel.bridge then Panel.bridge.onDisable() end
    CA.border(false, 0, "red")
end

package.loaded["ui.Preview"] = Preview
return Preview
