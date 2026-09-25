--- ui/Panel.lua  —  Two-panel overlay: Alert (centre screen) + Tracker (corner table).
---
--- Alert panel  (Incha_Alert)
---   Fires for immediate player actions: "Block!", "Enter Tomb!", "Dodge!".
---   Auto-clears after ALERT_AUTO_CLEAR_MS.  Manually dismissed by hideAction() / clear().
---   Draggable; position saved in Settings.overlay.{alertX,alertY}.
---
--- Tracker panel  (Incha_Panel)
---   Structured table of upcoming events.
---   Each row: [20×20 icon (optional)] [event label] [ETA countdown]
---   ETA colour: grey >10 s · orange 3–10 s · red <3 s.
---   Draggable; position saved in Settings.overlay.{offsetX,offsetY}.
---
--- AlertSink vocabulary handled here:
---   header(text)         – boss name / HM status (tracker top)
---   action(text)         – immediate call-out (alert panel); auto-clears 5 s
---   hideAction()         – force-clear alert panel before timeout
---   setRow(key, name, eta, priority, iconTexture)
---                        – tracker row keyed by key; priority (default 0) controls
---                          display order when more keys than slots exist.
---                          Numeric keys reproduce the old positional layout
---                          (key 1 before key 2, etc.) without changing call sites.
---                          iconTexture: optional DDS path for the 20×20 slot (nil = hidden).
---   clearRow(key)        – remove keyed row; blanks the slot it occupied
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
-- Default to "shown" so panels are visible from first boss detection forward,
-- even if the callbacks haven't fired yet since load.
local hudState   = "shown"
local hudUiState = "shown"

-- ── Tracker panel state ───────────────────────────────────────────────────────

local ctrl = nil   -- populated exactly once by build()

local function isHudVisible(state)
    return state == "showing" or state == "shown"
end

local function applyTrackerVisibility()
    if not ctrl then return end
    local visible = isHudVisible(hudState) or isHudVisible(hudUiState)
    Log.debug("Panel.vis: active=%s hud=%s hudui=%s → visible=%s",
        tostring(ctrl.active), hudState, hudUiState, tostring(visible))
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

local function applyAlertPosition(panel)
    local sv = Settings.get().overlay
    panel:ClearAnchors()
    if sv.alertX >= 0 then
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.alertX, sv.alertY)
    else
        panel:SetAnchor(CENTER, GuiRoot, CENTER, 0, -120)
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
    local visible = isHudVisible(hudState) or isHudVisible(hudUiState)
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

        -- 20×20 icon slot.  Hidden until a setRow caller supplies an iconTexture.
        local icon = WINDOW_MANAGER:CreateControl(nil, panel, CT_TEXTURE)
        icon:SetAnchor(TOPLEFT, panel, TOPLEFT, ICON_X, y + math.floor((TRACKER_ROW_H - ICON_H) / 2))
        icon:SetDimensions(ICON_W, ICON_H)
        icon:SetHidden(true)

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
            icon       = icon,
            nameLbl    = nameLbl,
            etaLbl     = etaLbl,
            nameText   = "",
            nameBucket = 0,    -- 0=empty 1=inactive(dim) 2=far 3=orange 4=red
            etaCeil    = 0,    -- last displayed whole second; 0 = blank
            etaBucket  = 0,    -- 0=none 1=red 2=orange 3=grey
            iconPath   = nil,  -- last texture applied; nil = icon hidden
        }
    end

    ctrl = {
        panel      = panel,
        header     = header,
        headerText = "",
        rows       = rows,
        -- Keyed row data.  key → { name, eta, priority }.
        -- rowOrder is the sorted key list; rebuilt only when rowDirty is true
        -- (new key added, key removed, or priority changed).  Plain eta updates
        -- leave rowOrder intact and skip the sort entirely.
        rowData    = {},
        rowOrder   = {},
        rowDirty   = false,
        active     = false,
    }

    -- Hide/show both panels when the HUD scene changes.
    -- Two separate callbacks so each updates only its own state variable;
    -- a shared callback lets the last-firing scene overwrite the result of
    -- the first (race when "hud→showing" fires before "hudui→hiding").
    -- why: ESO kills a scene StateChange callback that raises an error and
    -- leaves it unregistered for the rest of the session — a throw inside the
    -- apply* calls would silently freeze overlay visibility until a /ui reload.
    -- pcall wraps the body (Xalvakka.lua:106 pattern) so a failure logs and the
    -- callback stays alive for the next scene transition.
    SCENE_MANAGER:GetScene("hud"):RegisterCallback("StateChange", function(_, newState)
        local ok, err = pcall(function()
            hudState = newState
            applyTrackerVisibility()
            applyAlertVisibility()
        end)
        if not ok then Log.warn("Panel hud StateChange: %s", tostring(err)) end
    end)
    SCENE_MANAGER:GetScene("hudui"):RegisterCallback("StateChange", function(_, newState)
        local ok, err = pcall(function()
            hudUiState = newState
            applyTrackerVisibility()
            applyAlertVisibility()
        end)
        if not ok then Log.warn("Panel hudui StateChange: %s", tostring(err)) end
    end)
end

-- ── Alert panel builder ───────────────────────────────────────────────────────

local function buildAlert()
    if alertCtrl then return end

    local sv = Settings.get().overlay

    local panel = WINDOW_MANAGER:CreateControl("Incha_Alert", GuiRoot, CT_CONTROL)
    panel:SetDimensions(ALERT_W, ALERT_H)
    panel:SetClampedToScreen(true)
    panel:SetMouseEnabled(not sv.locked)
    panel:SetMovable(not sv.locked)
    panel:SetHidden(true)
    panel:SetScale(sv.scale)
    applyAlertPosition(panel)

    panel:SetHandler("OnMoveStop", function(c)
        local s = Settings.get().overlay
        s.alertX = c:GetLeft()
        s.alertY = c:GetTop()
        Log.debug("alert: saved offset %d, %d (scale %.2f)", s.alertX, s.alertY, s.scale)
    end)

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
    ctrl.rowData  = {}
    ctrl.rowOrder = {}
    ctrl.rowDirty = false
    for i = 1, TRACKER_ROW_COUNT do
        local row = ctrl.rows[i]
        if row.nameText ~= "" then
            row.nameText = ""
            row.nameLbl:SetText("")
        end
        if row.iconPath ~= nil then
            row.iconPath = nil
            row.icon:SetHidden(true)
        end
        if row.etaCeil ~= 0 then
            row.etaCeil = 0
            row.etaLbl:SetText("")
        end
    end
    ctrl.active = false
    applyTrackerVisibility()
end

-- ── Internal: keyed row renderer ─────────────────────────────────────────────

-- Rebuild the sorted display order from rowData keys.  Called only when the
-- key set or a priority value changes; skipped on plain eta/name updates.
-- Sort: higher priority first; among equal-priority keys, numbers before
-- strings, then natural ascending order within each type.
-- With all-default priority and numeric keys 1–7, this reproduces the old
-- positional layout exactly — row 1 at the top, row 7 at the bottom — so
-- existing setRow(n, …) call sites need no changes.
local function rebuildRowOrder(c)
    local order = {}
    for k in pairs(c.rowData) do order[#order + 1] = k end
    table.sort(order, function(a, b)
        local pa = c.rowData[a].priority
        local pb = c.rowData[b].priority
        if pa ~= pb then return pa > pb end
        local ta, tb = type(a), type(b)
        if ta == tb then return a < b end
        return ta == "number"   -- numbers before strings
    end)
    c.rowOrder = order
    c.rowDirty = false
end

-- Render keyed row data into the fixed physical slot controls.
-- Hot path: called from setRow and clearRow.  Guards every SetText / SetColor
-- call behind a string-compare so only real changes touch the UI.
local function renderTrackerRows(c)
    if c.rowDirty then rebuildRowOrder(c) end

    for i = 1, TRACKER_ROW_COUNT do
        local key = c.rowOrder[i]
        local row = c.rows[i]
        local d   = key and c.rowData[key]

        -- Icon column ────────────────────────────────────────────────────────
        local iconPath = d and d.icon or nil
        if row.iconPath ~= iconPath then
            row.iconPath = iconPath
            if iconPath then
                row.icon:SetTexture(iconPath)
                row.icon:SetHidden(false)
            else
                row.icon:SetHidden(true)
            end
        end

        -- Name column ────────────────────────────────────────────────────────
        local nameStr = d and d.name or ""
        if row.nameText ~= nameStr then
            row.nameText = nameStr
            row.nameLbl:SetText(nameStr)
        end

        -- ETA column ─────────────────────────────────────────────────────────
        -- Compare the integer ceiling and the colour bucket as numbers first;
        -- the "Ns" string is only built when the displayed second changes, so
        -- a steady countdown allocates one string per second, not per tick.
        -- nameBucket mirrors etaBucket (0=empty, 1=inactive/dim, 2=far, 3=orange, 4=red)
        -- so both labels always share the same colour state.
        local eta = d and d.eta
        local etaCeil, etaBucket, nameBucket
        if not d then
            etaCeil, etaBucket, nameBucket = 0, 0, 0      -- empty slot
        elseif eta and eta > 0 then
            etaCeil = math.ceil(eta)
            if     eta < 3  then etaBucket = 1; nameBucket = 4   -- red
            elseif eta < 10 then etaBucket = 2; nameBucket = 3   -- orange
            else                 etaBucket = 3; nameBucket = 2   -- far (grey)
            end
        else
            etaCeil, etaBucket, nameBucket = 0, 0, 1      -- inactive: dim grey
        end
        if row.etaCeil ~= etaCeil then
            row.etaCeil = etaCeil
            row.etaLbl:SetText(etaCeil > 0 and (etaCeil .. "s") or "")
        end
        if row.etaBucket ~= etaBucket then
            row.etaBucket = etaBucket
            if     etaBucket == 1 then row.etaLbl:SetColor(1.00, 0.27, 0.27, 1)
            elseif etaBucket == 2 then row.etaLbl:SetColor(1.00, 0.52, 0.00, 1)
            elseif etaBucket == 3 then row.etaLbl:SetColor(0.67, 0.67, 0.67, 1)
            end
        end
        -- Name colour mirrors the activity state so label and ETA read together.
        --   0 = empty           → no text, no colour change needed
        --   1 = inactive / dim  → dim grey (row present, not imminent)
        --   2 = far (> 10 s)    → normal grey
        --   3 = orange          → matches ETA
        --   4 = red             → matches ETA
        if row.nameBucket ~= nameBucket then
            row.nameBucket = nameBucket
            if     nameBucket == 1 then row.nameLbl:SetColor(0.42, 0.42, 0.42, 1)
            elseif nameBucket == 2 then row.nameLbl:SetColor(0.82, 0.82, 0.82, 1)
            elseif nameBucket == 3 then row.nameLbl:SetColor(1.00, 0.52, 0.00, 1)
            elseif nameBucket == 4 then row.nameLbl:SetColor(1.00, 0.27, 0.27, 1)
            end
        end
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

    -- setRow(key, name, eta, priority, iconTexture)  –  update or insert a keyed tracker row.
    -- key:         opaque row identifier (number or string).  Numeric keys ≤ 7
    --              reproduce the old positional layout; no call-site changes needed.
    -- name:        display label (may include |c colour codes).
    -- eta:         remaining seconds (number > 0), or nil for a static / timer-free row.
    -- priority:    optional sort weight (default 0).  Higher values sort to the top.
    --              When more keys than slots exist, lower-priority rows are clipped.
    -- iconTexture: optional DDS path shown in the 20×20 icon slot.  nil = hidden.
    setRow = function(key, name, eta, priority, iconTexture)
        if not ctrl then return end
        priority = priority or 0
        local d = ctrl.rowData[key]
        if d then
            -- Update in place.  Boss onUpdate loops call setRow for every
            -- timer row on every 200 ms tick, so a fresh record per call
            -- would be the single largest GC source in the addon.
            if d.priority ~= priority then
                d.priority = priority
                ctrl.rowDirty = true
            end
            d.name = name or ""
            d.eta  = eta
            d.icon = iconTexture
        else
            ctrl.rowData[key] = { name = name or "", eta = eta, priority = priority, icon = iconTexture }
            ctrl.rowDirty = true
        end
        renderTrackerRows(ctrl)
        if not ctrl.active then
            ctrl.active = true
            applyTrackerVisibility()
        end
    end,

    -- clearRow(key)  –  remove a keyed row and re-render.
    clearRow = function(key)
        if not ctrl or not ctrl.rowData[key] then return end
        ctrl.rowData[key] = nil
        ctrl.rowDirty = true
        renderTrackerRows(ctrl)
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
        Log.debug("Panel.onBossEnter: ctrl=%s", tostring(ctrl ~= nil))
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
    local sv = Settings.get().overlay
    if ctrl then
        ctrl.panel:SetMouseEnabled(not sv.locked)
        ctrl.panel:SetMovable(not sv.locked)
        ctrl.panel:SetScale(sv.scale)
        applyPosition(ctrl.panel)
    end
    if alertCtrl then
        alertCtrl.panel:SetMouseEnabled(not sv.locked)
        alertCtrl.panel:SetMovable(not sv.locked)
        alertCtrl.panel:SetScale(sv.scale)
        applyAlertPosition(alertCtrl.panel)
    end
end

-- Diagnostic dump for `/incha status`.  Reports what Lua believes about the
-- tracker so an in-game "A3 never shows" report can be split into
-- "never written" (ctrl nil / rows empty), "written but hidden" (active or
-- HUD state false) and "shown but not drawn" (everything true - a control
-- placement problem).  Emits through Log.print so it works without debug on.
function Panel.status()
    Log.print("panel: hud=%s hudui=%s", hudState, hudUiState)
    if not ctrl then
        Log.print("tracker: NOT BUILT (bridge.onEnable never ran)")
    else
        local p = ctrl.panel
        Log.print("tracker: active=%s hidden=%s pos=%s,%s size=%sx%s scale=%.2f",
            tostring(ctrl.active), tostring(p:IsHidden()),
            tostring(p:GetLeft()), tostring(p:GetTop()),
            tostring(p:GetWidth()), tostring(p:GetHeight()), p:GetScale())
        Log.print("tracker: header=%q", ctrl.headerText)
        for i = 1, TRACKER_ROW_COUNT do
            local row = ctrl.rows[i]
            if row.nameText ~= "" or row.etaCeil ~= 0 then
                Log.print("tracker: row %d  %q  eta=%s", i, row.nameText,
                    row.etaCeil > 0 and (row.etaCeil .. "s") or "-")
            end
        end
    end
    if not alertCtrl then
        Log.print("alert: NOT BUILT")
    else
        Log.print("alert: active=%s hidden=%s text=%q",
            tostring(alertCtrl.active), tostring(alertCtrl.panel:IsHidden()), alertCtrl.text)
    end
end

-- Test hook (test/checks/lifecycle.lua): read-only access to the tracker
-- state so the offline check can assert on row records and control calls.
-- Not used by production code.
function Panel._inspect()
    return ctrl
end

package.loaded["ui.Panel"] = Panel
return Panel
