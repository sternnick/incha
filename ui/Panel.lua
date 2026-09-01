--- Default overlay panel  -  implements the AlertSink handler vocabulary
--- using plain WINDOW_MANAGER controls owned entirely by Incha.
---
--- Design rules (from Phase 0 analysis):
---   - Controls are built ONCE on first enable, never per event.
---   - All steady-state updates are :SetText() / :SetHidden() only.
---   - No per-tick allocations anywhere in this file.
---
--- Alert vocabulary:
---   header(text)     -  boss name / HM status, small gold line at top
---   info(n, text)    -  timer countdown lines (grey, small)
---   action(text)     -  prominent mid-fight call-out (orange, bold)
---   hideAction()     -  clears action without hiding panel
---   clear()          -  clears all text and hides the panel
---
--- Used by ka/rg/dsr.

local BridgeBase = require("core.Bridge")
local Settings   = require("core.Settings")

local Panel = {}

-- Control bundle  -  nil until first build(), populated exactly once.
local ctrl = nil

-- Track each HUD scene's state separately to avoid callback-order races.
-- When chat/inventory closes, ESO fires both "hud → showing" and
-- "hudui → hiding" in the same frame.  The one that fires last overwrites
-- the shared variable, so the panel could end up hidden while the HUD is
-- fully visible.  OR logic avoids the race: the panel is live whenever
-- either scene is "showing".
local hudState   = "showing"   -- most recent state of the "hud" scene
local hudUiState = "showing"   -- most recent state of the "hudui" scene

-- Panel dimensions (points, scales with ctrl.panel:SetScale).
-- H=200 accommodates the info lines (each 18 px) + header (26 px) + action (38 px bottom).
local INFO_LINE_COUNT = 10
local W, H = 320, 260

-- Show or hide the panel based on two independent gates:
--   ctrl.active    -  trial/boss content should be on screen
--   hudVisible     -  the hud/hudui scene allows it
-- Call this instead of SetHidden directly so both gates stay in sync.
local function applyVisibility()
    if not ctrl then return end
    local hudVisible = (hudState == "showing") or (hudUiState == "showing")
    ctrl.panel:SetHidden(not (ctrl.active and hudVisible))
end

local function applyPosition(panel)
    local sv = Settings.get().overlay
    panel:ClearAnchors()
    if sv.offsetX >= 0 then
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.offsetX, sv.offsetY)
    else
        local screenW = GuiRoot:GetWidth()
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, (screenW - W) / 2, 150)
    end
end

-- Clear all panel text and deactivate.
-- Callers must guard with `if not ctrl then return end` before calling.
local function panel_clear()
    ctrl.header:SetText("") ; ctrl.headerText = ""
    ctrl.action:SetText("") ; ctrl.actionText = ""
    for i = 1, INFO_LINE_COUNT do
        ctrl.info[i]:SetText("")
        ctrl.infoText[i] = ""
    end
    ctrl.active = false
    applyVisibility()
end

local function build()
    if ctrl then return end

    local sv = Settings.get().overlay

    -- Outer container  -  the draggable root.
    local panel = WINDOW_MANAGER:CreateControl("Incha_Panel", GuiRoot, CT_CONTROL)
    panel:SetDimensions(W, H)
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
        applyPosition(c)
    end)

    -- Semi-transparent dark background.
    local bg = WINDOW_MANAGER:CreateControl(nil, panel, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(0.04, 0.04, 0.04, 0.82)
    bg:SetEdgeColor(0.35, 0.35, 0.35, 0.9)

    -- Header  -  boss name / HM status.  Small, gold.
    local header = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    header:SetFont("ZoFontGameSmall")
    header:SetColor(1, 0.82, 0.22, 1)
    header:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    header:SetAnchor(TOPLEFT, panel, TOPLEFT, 8, 8)
    header:SetDimensions(W - 16, 18)
    header:SetText("")

    -- Info lines  -  timer countdowns.  Small, grey.
    -- Stacked below the header with 2px gaps.
    local info = {}
    for i = 1, INFO_LINE_COUNT do
        local lbl = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
        lbl:SetFont("ZoFontGameSmall")
        lbl:SetColor(0.75, 0.75, 0.75, 1)
        lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        lbl:SetAnchor(TOPLEFT, panel, TOPLEFT, 8, 28 + (i - 1) * 18)
        lbl:SetDimensions(W - 16, 16)
        lbl:SetText("")
        info[i] = lbl
    end

    -- Action  -  the prominent mid-fight call-out.  Larger, orange.
    local action = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    action:SetFont("ZoFontGameBold")
    action:SetColor(1, 0.42, 0.08, 1)
    action:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    action:SetAnchor(BOTTOM, panel, BOTTOM, 0, -10)
    action:SetDimensions(W - 16, 28)
    action:SetText("")

    -- Text caches: last string passed to each SetText call.
    -- Compared on every hot-path tick to skip redundant SetText + applyVisibility
    -- calls when the displayed value hasn't changed.
    local infoText = {}
    for i = 1, INFO_LINE_COUNT do infoText[i] = "" end

    ctrl = {
        panel      = panel,
        header     = header,
        info       = info,
        action     = action,
        active     = false,  -- gates applyVisibility()
        infoText   = infoText,
        actionText = "",
        headerText = "",
    }

    -- Hide the panel when neither HUD scene is active (escape menu, loading
    -- screen, etc.) and restore it when either returns to "showing".
    -- Separate callbacks per scene so each updates only its own state variable;
    -- a shared callback would let the last-firing scene overwrite the result of
    -- the first, causing spurious hide when callback order is "hud→showing"
    -- then "hudui→hiding" (which leaves hudVisible false while HUD is visible).
    SCENE_MANAGER:GetScene("hud"):RegisterCallback("StateChange", function(_, newState)
        hudState = newState
        applyVisibility()
    end)
    SCENE_MANAGER:GetScene("hudui"):RegisterCallback("StateChange", function(_, newState)
        hudUiState = newState
        applyVisibility()
    end)
end

-- -- AlertSink handler table ------------------------------------------------

Panel.alerts = {
    header = function(text)
        if not ctrl then return end
        local s = text or ""
        if ctrl.headerText ~= s then
            ctrl.headerText = s
            ctrl.header:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    -- info(n, text)  -  timer countdown for slot n (1-7).
    -- Hot path: called up to 7x per 200 ms onUpdate tick.  Skip SetText when
    -- the string is unchanged (LuaJIT interns all strings, so ~= is a pointer
    -- compare).  Skip applyVisibility when the panel is already active.
    info = function(n, text)
        if not ctrl then return end
        local lbl = ctrl.info[n]
        if not lbl then return end
        local s = text or ""
        if ctrl.infoText[n] ~= s then
            ctrl.infoText[n] = s
            lbl:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    action = function(text)
        if not ctrl then return end
        local s = text or ""
        if ctrl.actionText ~= s then
            ctrl.actionText = s
            ctrl.action:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    hideAction = function()
        if not ctrl then return end
        ctrl.action:SetText("")
        -- Clear the diff cache too: action() above compares against ctrl.actionText
        -- and skips SetText when the strings match, so leaving the old text cached
        -- makes the next identical callout a no-op. Mirrors panel_clear().
        ctrl.actionText = ""
        -- leave panel visible  -  info lines may still carry timer data
    end,

    clear = function()
        if not ctrl then return end
        panel_clear()
    end,
}

-- -- Bridge lifecycle table -------------------------------------------------
-- Wrapped with BridgeBase so checkHardmode (and any future hook) falls back
-- to the documented no-op rather than silently being absent.

Panel.bridge = BridgeBase.extend({
    onEnable = function()
        build()  -- no-op after first call; safe on every zone enter
    end,

    onDisable = function()
        if not ctrl then return end
        panel_clear()
    end,

    onBossEnter = function(boss, context)
        if ctrl then
            ctrl.active = true
            applyVisibility()
        end
    end,

    onBossExit = function()
        if not ctrl then return end
        panel_clear()
    end,
    -- checkHardmode: inherited no-op from BridgeBase (Panel has no HM logic)
})

-- -- Settings refresh -------------------------------------------------------

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
