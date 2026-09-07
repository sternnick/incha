--- ui/Panel.lua  —  Two-panel overlay: Alert (centre screen) + Tracker (corner table).
---
--- Alert panel  (Incha_Alert)
---   Fires for immediate player actions: "Block!", "Enter Tomb!", "Dodge!".
---   Auto-clears after ALERT_AUTO_CLEAR_MS.  Manually dismissed by hideAction() / clear().
---   Draggable; position is NOT persisted (resets to centre on reload).
---
--- Tracker panel  (Incha_Panel)
---   Structured table of upcoming events.
---   Each row: [20×20 icon placeholder] [event label] [ETA countdown]
---   ETA colour: grey >10 s · orange 3–10 s · red <3 s.
---   Draggable; position saved in Settings.overlay.{offsetX,offsetY}.
---
--- AlertSink vocabulary handled here:
---   header(text)         – boss name / HM status (tracker top)
---   action(text)         – immediate call-out (alert panel); auto-clears 5 s
---   hideAction()         – force-clear alert panel before timeout
---   setRow(n, name, eta) – tracker row n: label + seconds remaining (nil = static)
---   clearRow(n)          – blank tracker row n
---   clear()              – clear both panels and deactivate
---
--- Design rules:
---   - Controls are built ONCE on first enable, never per event.
---   - All steady-state updates are :SetText() / :SetColor() / :SetHidden() only.
---   - No per-tick allocations anywhere in this file.

local BridgeBase = require("core.Bridge")
local Log        = require("lib.Log")
local Settings   = require("core.Settings")

local Panel = {}

-- ── Tracker panel dimensions ──────────────────────────────────────────────────

local TRACKER_ROW_COUNT = 7       -- max visible event rows
local TRACKER_W         = 320
local TRACKER_HEADER_H  = 32      -- gold boss-name header
local TRACKER_ROW_H     = 26      -- height of each event row
local TRACKER_PAD_BTM   = 8
local TRACKER_H = TRACKER_HEADER_H + TRACKER_ROW_COUNT * TRACKER_ROW_H + TRACKER_PAD_BTM

-- Row column geometry (x from panel left edge; panel width = 320)
local ICON_X = 8                              -- icon left edge
local ICON_W = 20
local ICON_H = 20
local NAME_X = ICON_X + ICON_W + 6           -- = 34  name label left edge
local ETA_W  = 74
local ETA_X  = TRACKER_W - 8 - ETA_W         -- = 238 ETA label left edge
local NAME_W = ETA_X - NAME_X - 4            -- = 200 name label width

-- ── Alert panel dimensions ────────────────────────────────────────────────────

local ALERT_W              = 400
local ALERT_H              = 56
local ALERT_AUTO_CLEAR_MS  = 5000

-- ── Shared HUD scene state ────────────────────────────────────────────────────

-- Updated by both scene callbacks; controls both panels via applyXxxVisibility().
local hudState   = "showing"
local hudUiState = "showing"

-- ── Tracker panel state ───────────────────────────────────────────────────────

local ctrl = nil   -- populated exactly once by build()

local function applyTrackerVisibility()
    if not ctrl then return end
    local visible = (hudState == "showing") or (hudUiState == "showing")
    ctrl.panel:SetHidden(not (ctrl.active and visible))
end

local function applyPosition(panel)
    local sv = Settings.get().overlay
    panel:ClearAnchors()
    if sv.offsetX >= 0 then
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.offsetX, sv.offsetY)
    else
        local screenW = GuiRoot:GetWidth()
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, (screenW - TRACKER_W) / 2, 150)
    end
end

-- ── Alert panel state ─────────────────────────────────────────────────────────

local alertCtrl = nil   -- populated exactly once by buildAlert()

-- Incremented each time a new alert fires.  The deferred auto-clear closure
-- captures its own copy of alertSeq and bails out if it has since changed.
-- No cancellation API needed: the deferred call is simply a no-op if stale.
local alertSeq = 0

local function applyAlertVisibility()
    if not alertCtrl then return end
    local visible = (hudState == "showing") or (hudUiState == "showing")
    alertCtrl.panel:SetHidden(not (alertCtrl.active and visible))
end

local function clearAlertContent()
    if not alertCtrl then return end
    alertCtrl.label:SetText("")
    alertCtrl.text   = ""
    alertCtrl.active = false
    applyAlertVisibility()
end

-- ── Tracker panel builder ─────────────────────────────────────────────────────

local function build()
    if ctrl then return end

    local sv = Settings.get().overlay

    -- Root control: draggable, saves position on move-stop.
    local panel = WINDOW_MANAGER:CreateControl("Incha_Panel", GuiRoot, CT_CONTROL)
    panel:SetDimensions(TRACKER_W, TRACKER_H)
    panel:SetClampedToScreen(true)
    panel:SetMouseEnabled(not sv.locked)
    panel:SetMovable(not sv.locked)
    panel:SetHidden(true)
    panel:SetScale(sv.scale)
    applyPosition(panel)

    panel:SetHandler("OnMoveStop", function(c)
        local s = Settings.get().overlay
        s.offsetX = c:GetLeft()
        s.offsetY = c:GetTop()
        Log.debug("tracker: saved offset %d, %d (scale %.2f)", s.offsetX, s.offsetY, s.scale)
    end)

    -- Background
    local bg = WINDOW_MANAGER:CreateControl(nil, panel, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(0.04, 0.04, 0.04, 0.82)
    bg:SetEdgeColor(0.35, 0.35, 0.35, 0.90)

    -- Header: boss name / HM status.  Gold, centred.
    local header = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    header:SetFont("EsoUI/Common/Fonts/univers67.otf|20|soft-shadow-thick")
    header:SetColor(1, 0.82, 0.22, 1)
    header:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    header:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    header:SetAnchor(TOPLEFT, panel, TOPLEFT, 0, 0)
    header:SetDimensions(TRACKER_W, TRACKER_HEADER_H)
    header:SetText("")

    -- Event rows.  Each row: icon placeholder (texture) + name (left) + ETA (right).
    local rows = {}
    for i = 1, TRACKER_ROW_COUNT do
        local y = TRACKER_HEADER_H + (i - 1) * TRACKER_ROW_H

        -- 20×20 icon placeholder.  Initially hidden; a future patch will set textures.
        local icon = WINDOW_MANAGER:CreateControl(nil, panel, CT_TEXTURE)
        icon:SetAnchor(TOPLEFT, panel, TOPLEFT, ICON_X, y + math.floor((TRACKER_ROW_H - ICON_H) / 2))
        icon:SetDimensions(ICON_W, ICON_H)
        icon:SetHidden(true)   -- no texture assigned yet; hidden until icons are added

        -- Name label: event label, left-aligned, grey.
        local nameLbl = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
        nameLbl:SetFont("EsoUI/Common/Fonts/univers67.otf|18|soft-shadow-thick")
        nameLbl:SetColor(0.80, 0.80, 0.80, 1)
        nameLbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        nameLbl:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        nameLbl:SetAnchor(TOPLEFT, panel, TOPLEFT, NAME_X, y)
        nameLbl:SetDimensions(NAME_W, TRACKER_ROW_H)
        nameLbl:SetText("")

        -- ETA label: countdown, right-aligned, colour varies by urgency.
        local etaLbl = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
        etaLbl:SetFont("EsoUI/Common/Fonts/univers67.otf|18|soft-shadow-thick")
        etaLbl:SetColor(0.67, 0.67, 0.67, 1)
        etaLbl:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
        etaLbl:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        etaLbl:SetAnchor(TOPLEFT, panel, TOPLEFT, ETA_X, y)
        etaLbl:SetDimensions(ETA_W, TRACKER_ROW_H)
        etaLbl:SetText("")

        rows[i] = {
            icon     = icon,
            nameLbl  = nameLbl,
            etaLbl   = etaLbl,
            nameText = "",
            etaText  = "",
        }
    end

    ctrl = {
        panel      = panel,
        header     = header,
        headerText = "",
        rows       = rows,
        active     = false,
    }

    -- Hide/show both panels when the HUD scene changes.
    -- Two separate callbacks so each updates only its own state variable;
    -- a shared callback lets the last-firing scene overwrite the result of
    -- the first (race when "hud→showing" fires before "hudui→hiding").
    SCENE_MANAGER:GetScene("hud"):RegisterCallback("StateChange", function(_, newState)
        hudState = newState
        applyTrackerVisibility()
        applyAlertVisibility()
    end)
    SCENE_MANAGER:GetScene("hudui"):RegisterCallback("StateChange", function(_, newState)
        hudUiState = newState
        applyTrackerVisibility()
        applyAlertVisibility()
    end)
end

-- ── Alert panel builder ───────────────────────────────────────────────────────

local function buildAlert()
    if alertCtrl then return end

    local panel = WINDOW_MANAGER:CreateControl("Incha_Alert", GuiRoot, CT_CONTROL)
    panel:SetDimensions(ALERT_W, ALERT_H)
    panel:SetClampedToScreen(true)
    panel:SetMouseEnabled(true)
    panel:SetMovable(true)
    panel:SetHidden(true)
    -- Default: screen centre, above the player character.
    -- The player can drag it; position is not persisted in this version.
    panel:SetAnchor(CENTER, GuiRoot, CENTER, 0, -120)

    -- Subtle dark background with a warm edge.
    local bg = WINDOW_MANAGER:CreateControl(nil, panel, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(0.03, 0.01, 0.00, 0.65)
    bg:SetEdgeColor(0.55, 0.18, 0.04, 0.80)

    -- Main alert label.  Large, orange.
    local lbl = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    lbl:SetFont("EsoUI/Common/Fonts/univers67.otf|36|soft-shadow-thick")
    lbl:SetColor(1, 0.42, 0.08, 1)
    lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    lbl:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    lbl:SetAnchorFill()
    lbl:SetText("")

    alertCtrl = {
        panel  = panel,
        label  = lbl,
        text   = "",
        active = false,
    }
end

-- ── Internal: tracker clear ───────────────────────────────────────────────────

local function tracker_clear()
    if not ctrl then return end
    ctrl.header:SetText(""); ctrl.headerText = ""
    for i = 1, TRACKER_ROW_COUNT do
        local row = ctrl.rows[i]
        row.nameLbl:SetText(""); row.nameText = ""
        row.etaLbl:SetText("");  row.etaText  = ""
    end
    ctrl.active = false
    applyTrackerVisibility()
end

-- ── Internal: setRow core ─────────────────────────────────────────────────────

-- Hot path: called up to TRACKER_ROW_COUNT × per 200 ms tick.
-- Guards every SetText / SetColor call behind a string-compare to avoid
-- redundant draws (LuaJIT interns strings so ~= is a pointer compare).
local function setRowInternal(n, name, eta)
    if not ctrl then return end
    local row = ctrl.rows[n]
    if not row then return end

    -- Name column ────────────────────────────────────────────────────────────
    local nameStr = name or ""
    if row.nameText ~= nameStr then
        row.nameText = nameStr
        row.nameLbl:SetText(nameStr)
    end

    -- ETA column ─────────────────────────────────────────────────────────────
    local etaStr
    if eta and eta > 0 then
        etaStr = math.ceil(eta) .. "s"
        local r, g, b
        if     eta < 3  then r, g, b = 1.00, 0.27, 0.27   -- red    (< 3 s)
        elseif eta < 10 then r, g, b = 1.00, 0.52, 0.00   -- orange (3–10 s)
        else                 r, g, b = 0.67, 0.67, 0.67   -- grey   (> 10 s)
        end
        -- SetColor is cheap but still skip it when value hasn't changed.
        -- We use etaText as the colour proxy: a colour only changes when the
        -- ceiling bucket changes, which is rare, so this under-fires slightly.
        -- Accept the minor inaccuracy to keep the hot path allocation-free.
        if row.etaText ~= etaStr then
            row.etaLbl:SetColor(r, g, b, 1)
        end
    else
        etaStr = ""
    end
    if row.etaText ~= etaStr then
        row.etaText = etaStr
        row.etaLbl:SetText(etaStr)
    end

    if not ctrl.active then
        ctrl.active = true
        applyTrackerVisibility()
    end
end

-- ── AlertSink handler table ───────────────────────────────────────────────────

Panel.alerts = {

    -- header(text)  –  boss name / HM status line at the top of the tracker.
    header = function(text)
        if not ctrl then return end
        local s = text or ""
        if ctrl.headerText ~= s then
            ctrl.headerText = s
            ctrl.header:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyTrackerVisibility()
        end
    end,

    -- action(text)  –  immediate call-out on the alert panel.
    -- Auto-clears after ALERT_AUTO_CLEAR_MS.  A new call before the timeout
    -- replaces the previous alert and restarts the timer.
    action = function(text)
        if not alertCtrl then buildAlert() end
        local s = text or ""
        alertSeq = alertSeq + 1
        local seq = alertSeq
        if alertCtrl.text ~= s then
            alertCtrl.text = s
            alertCtrl.label:SetText(s)
        end
        alertCtrl.active = (s ~= "")
        applyAlertVisibility()
        if s ~= "" then
            zo_callLater(function()
                if alertSeq == seq then clearAlertContent() end
            end, ALERT_AUTO_CLEAR_MS)
        end
    end,

    -- hideAction()  –  force-clear the alert panel before the auto-clear fires.
    hideAction = function()
        alertSeq = alertSeq + 1   -- invalidate any pending deferred clear
        clearAlertContent()
    end,

    -- setRow(n, name, eta)  –  update tracker row n.
    -- name: display label (may include |c colour codes).
    -- eta:  remaining seconds (number > 0), or nil for a static / timer-free row.
    setRow = function(n, name, eta)
        setRowInternal(n, name, eta)
    end,

    -- clearRow(n)  –  blank out tracker row n.
    clearRow = function(n)
        setRowInternal(n, "", nil)
    end,

    -- clear()  –  clear both panels and deactivate.
    clear = function()
        alertSeq = alertSeq + 1
        clearAlertContent()
        tracker_clear()
    end,
}

-- ── Bridge lifecycle ──────────────────────────────────────────────────────────

Panel.bridge = BridgeBase.extend({
    onEnable = function()
        build()       -- idempotent; registers scene callbacks on first call
        buildAlert()  -- idempotent
    end,

    onDisable = function()
        alertSeq = alertSeq + 1
        clearAlertContent()
        tracker_clear()
    end,

    onBossEnter = function(boss, context)
        if ctrl then
            ctrl.active = true
            applyTrackerVisibility()
        end
    end,

    onBossExit = function()
        alertSeq = alertSeq + 1
        clearAlertContent()
        tracker_clear()
    end,
    -- checkHardmode: inherited no-op from BridgeBase (Panel has no HM logic)
})

-- ── Settings refresh ──────────────────────────────────────────────────────────

function Panel.refresh()
    if not ctrl then return end
    local sv = Settings.get().overlay
    ctrl.panel:SetMouseEnabled(not sv.locked)
    ctrl.panel:SetMovable(not sv.locked)
    ctrl.panel:SetScale(sv.scale)
    applyPosition(ctrl.panel)
end

package.loaded["ui.Panel"] = Panel
return Panel
