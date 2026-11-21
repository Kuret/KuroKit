-- MenuTray: the micro menu and bag bar stay hidden and slide in from a screen edge
-- while the mouse is over their spot (horizontal strip: from the nearer of top /
-- bottom; vertical: left / right). Optionally the bag bar shrinks to just the
-- backpack, styled like a micro menu button and auto-aligned to the menu.
--
-- Edit Mode stays in charge of where they are: place both with Edit Mode (snap
-- them together for one strip). We never move or re-anchor the Edit Mode system
-- frames. On Forever the main action bar is anchored to MicroMenuContainer, so we
-- only animate MicroMenu (the button strip inside it) and BagsBar, which nothing
-- else is anchored to (checked against Blizzard's exported UI code).
--
-- Performance: while hidden nothing runs. An invisible hover sensor (mouse
-- motion only, clicks pass through) covers the spot; entering it reveals the
-- frames and starts a 20 Hz check that only runs while they're visible. The
-- check allocates nothing.
--
-- Left alone:
--  * Edit Mode open: everything shown.
--  * Vehicle / pet battle: Blizzard borrows MicroMenu (OverrideMicroMenuPosition);
--    then it's shown normally until ResetMicroMenuPosition.
--  * Gamepad UI: Blizzard hides both frames itself.
local _, ns = ...

local M = ns:NewModule("MenuTray", {
    title = "Micro Menu & Bags",
    group = "Interface",
    desc = "Hide the micro menu and bag bar until you hover their spot; they slide in from the screen edge. Place them with Edit Mode.",
    defaults = { bagStyle = "micro", hideMicroArt = true, animation = "auto", hideDelay = 0.5 },
    options = {
        { type = "dropdown", key = "bagStyle", name = "Bag bar", reload = true,
          tooltip = "How the bag bar looks.",
          values = {
              { "micro", "Micro menu style", "Only the backpack, styled and sized like a micro menu button, lined up with the menu." },
              { "single", "Single bag button", "Only the backpack button: bag slots, reagent bag slot and keyring hidden." },
              { "full", "Full bag bar", "Blizzard's bag bar, unchanged." },
          } },
        { type = "checkbox", key = "hideMicroArt", name = "Hide micro menu frame", reload = true,
          tooltip = "Remove the frame and background drawn around the micro menu buttons." },
        { type = "dropdown", key = "animation", name = "Animation",
          tooltip = "How they appear and disappear.",
          values = {
              { "auto", "Slide (automatic)", "A horizontal strip slides up/down to the nearest top or bottom edge; a vertical one slides left/right." },
              { "down", "Slide from the bottom" },
              { "up", "Slide from the top" },
              { "left", "Slide from the left" },
              { "right", "Slide from the right" },
              { "fade", "Fade only" },
          } },
        { type = "slider", key = "hideDelay", name = "Hide delay", min = 0, max = 3, step = 0.1,
          format = function(v) return ("%.1f s"):format(v) end,
          tooltip = "How long they stay visible after the mouse leaves." },
    },
})

local DURATION = 0.18      -- seconds per slide/fade
local EDGE_SNAP = 64       -- a spot this close to a screen edge counts as touching it
local ZONE_PAD = 6         -- extra hover margin around the frames
local POLL = 0.05          -- check interval while visible

local frames = {}          -- the frames we fade: MicroMenu, BagsBar
local anims = {}           -- [frame] = { show, hide, jump, slideIn, slideOut }
local microButtons = {}    -- cached visible micro buttons (refreshed on reveal / layout)
local zone = { valid = false, l = 0, b = 0, r = 0, t = 0, dx = 0, dy = 0 }
local editMode = false
local visible = true
local leftAt
local sensor, poller
local Refresh -- forward

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ScreenCenter(f)
    local x, y = f:GetCenter()
    if not x then return end
    local s = f:GetEffectiveScale()
    return x * s, y * s
end

-- Rect in UIParent units.
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not l then return end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

local function IsBorrowed()
    return MicroMenu:GetParent() ~= MicroMenuContainer
end

local function IsManaged(f)
    if not f:IsShown() then return false end
    if f == MicroMenu then return not IsBorrowed() end
    return true
end

local function RefreshMicroButtons()
    wipe(microButtons)
    for _, child in ipairs({ MicroMenu:GetChildren() }) do
        if child.layoutIndex and child:IsShown() then microButtons[#microButtons + 1] = child end
    end
end

---------------------------------------------------------------------------
-- Single bag button
---------------------------------------------------------------------------
local BAG_SLOTS = {
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "KeyRingButton",
}

-- Micro menu style: the backpack keeps being Blizzard's button (clicks, tooltip,
-- free-slot count, Baganator's hooks all still work); we only change its size and
-- textures. Blizzard resets the textures in UpdateTextures() on bag updates, so
-- this re-applies after every call.
local styling = false
local bgUp, bgDown -- our own background textures, under the icon

local function StyleBackpack()
    local b, ref = MainMenuBarBackpackButton, MainMenuMicroButton or CharacterMicroButton
    if styling or not ref then return end
    styling = true

    -- Same on-screen size as a micro button, whatever each one's Edit Mode size is.
    local k = ref:GetEffectiveScale() / b:GetEffectiveScale()
    local w, h = ref:GetWidth() * k, ref:GetHeight() * k
    b:SetSize(w, h)

    -- Blizzard's normal/pushed textures draw *over* the icon (they're the item
    -- border), so they go invisible and our background sits underneath instead,
    -- at the exact size the micro buttons draw theirs (atlas size, centred).
    b:GetNormalTexture():SetAlpha(0)
    b:GetPushedTexture():SetAlpha(0)
    if not bgUp then
        bgUp = b:CreateTexture(nil, "BACKGROUND")
        bgUp:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Up")
        bgDown = b:CreateTexture(nil, "BACKGROUND")
        bgDown:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Down")
        bgDown:Hide()
        b:HookScript("OnMouseDown", function() bgDown:Show(); bgUp:Hide() end)
        b:HookScript("OnMouseUp", function() bgUp:Show(); bgDown:Hide() end)
    end
    local refBG = ref.Background
    local bw, bh = w, h
    if refBG then bw, bh = refBG:GetWidth() * k, refBG:GetHeight() * k end
    bgUp:ClearAllPoints(); bgUp:SetPoint("CENTER", b, "CENTER"); bgUp:SetSize(bw, bh)
    bgDown:ClearAllPoints(); bgDown:SetPoint("CENTER", b, "CENTER"); bgDown:SetSize(bw, bh)

    -- Square icon inside the background, centred like the micro button icons.
    local size = math.min(bw, bh) * 0.72
    b.icon:ClearAllPoints()
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon:SetSize(size, size)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetAlpha(1)

    -- Hover and "bags open" glow: the icon itself, added on top.
    local hl, slot = b:GetHighlightTexture(), b.SlotHighlightTexture
    for _, tex in ipairs({ hl, slot }) do
        tex:ClearAllPoints()
        tex:SetAllPoints(b.icon)
        tex:SetTexture(b.icon:GetTexture())
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetBlendMode("ADD")
    end
    hl:SetAlpha(0.35)
    slot:SetAlpha(0.25)

    if b.IconBorder then b.IconBorder:SetAlpha(0) end
    if b.IconOverlay then b.IconOverlay:SetAlpha(0) end
    if b.Count then
        b.Count:ClearAllPoints(); b.Count:SetPoint("BOTTOM", b, "BOTTOM", 0, h * 0.08)
        b.Count:SetFontObject(NumberFontNormalSmall)
    end
    if b.FreeSlots then
        b.FreeSlots:ClearAllPoints(); b.FreeSlots:SetPoint("BOTTOM", b, "BOTTOM", 0, h * 0.08)
        b.FreeSlots:SetFontObject(NumberFontNormalSmall)
    end
    if BagsBar.BorderArt then BagsBar.BorderArt:Hide() end

    styling = false
end

-- Auto-align: Edit Mode snaps the bag bar edge-to-edge with MicroMenuContainer,
-- but micro buttons overlap each other (MicroMenu.childXPadding = -5), so the bag
-- ends up with a bigger gap than its neighbours. When the bag sits next to the
-- menu (any side, any orientation), move the backpack inside BagsBar so it's
-- exactly one micro-button step from the nearest button and lined up with it.
-- Edit Mode's saved position is untouched.
local alignX, alignY -- current offset of the backpack from BagsBar's centre

local function InsideMicroMenu(x, y)
    local l, b, w, h = MicroMenu:GetRect()
    if not l then return false end
    local s = MicroMenu:GetEffectiveScale()
    return x > l * s and x < (l + w) * s and y > b * s and y < (b + h) * s
end

local function AlignBackpack()
    local ox, oy = 0, 0
    local barX, barY = ScreenCenter(BagsBar)
    if barX and BagsBar:IsShown() and MicroMenu:IsShown() and not IsBorrowed() then
        local best, bestDist, bx, by
        for i = 1, #microButtons do
            local x, y = ScreenCenter(microButtons[i])
            if x then
                local d = (x - barX) ^ 2 + (y - barY) ^ 2
                if not bestDist or d < bestDist then best, bestDist, bx, by = microButtons[i], d, x, y end
            end
        end
        if best then
            local s = best:GetEffectiveScale()
            local stepX = (best:GetWidth() + (MicroMenu.childXPadding or 0)) * s
            local stepY = (best:GetHeight() + (MicroMenu.childYPadding or 0)) * s
            local dx, dy = barX - bx, barY - by
            local tx, ty
            if math.abs(dx) >= math.abs(dy) then
                tx, ty = bx + (dx >= 0 and stepX or -stepX), by
            else
                tx, ty = bx, by + (dy >= 0 and stepY or -stepY)
            end
            -- Only when the bag was placed next to the menu, and never on top of it.
            local reach = math.max(best:GetWidth(), best:GetHeight()) * s
            if math.abs(tx - barX) <= reach and math.abs(ty - barY) <= reach and not InsideMicroMenu(tx, ty) then
                local barScale = BagsBar:GetEffectiveScale()
                ox, oy = (tx - barX) / barScale, (ty - barY) / barScale
            end
        end
    end
    if alignX and math.abs(ox - alignX) < 0.05 and math.abs(oy - alignY) < 0.05 then return end
    alignX, alignY = ox, oy
    local b = MainMenuBarBackpackButton
    b:ClearAllPoints()
    b:SetPoint("CENTER", BagsBar, "CENTER", ox, oy)
end

-- Shrink the bar to the backpack (so Edit Mode snapping and centering use the
-- real size), drop dividers, restyle and re-align. Runs after BagsBar:Layout();
-- note Blizzard also calls Layout through references taken at load time
-- (expand-changed callback), which a hook can't see, so we listen for that too.
local function FitBagsBar()
    if M.db.bagStyle == "micro" then StyleBackpack() end
    for _, pool in ipairs({ BagsBar.HorizontalDividersPool, BagsBar.VerticalDividersPool }) do
        if pool then
            for divider in pool:EnumerateActive() do divider:Hide() end
        end
    end
    local w, h = MainMenuBarBackpackButton:GetSize()
    BagsBar:SetSize(w, h)
    alignX = nil -- Layout re-anchored the backpack; re-apply our offset
    if M.db.bagStyle == "micro" then AlignBackpack() end
    if Refresh then Refresh() end
end

local function BagsBarNeedsFit()
    return math.abs(BagsBar:GetWidth() - MainMenuBarBackpackButton:GetWidth()) > 0.5
end

local function SetupSingleBag()
    if not (BagsBar and MainMenuBarBackpackButton) then return end
    for _, name in ipairs(BAG_SLOTS) do
        local slot = _G[name]
        if slot then
            slot:Hide()
            slot:HookScript("OnShow", slot.Hide) -- Blizzard re-shows some (keyring) on events
        end
    end
    hooksecurefunc(BagsBar, "Layout", FitBagsBar)
    -- Blizzard's own expand-changed callback runs the original Layout (fires e.g.
    -- when you pick up an item); re-fit right after it.
    EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", function()
        RunNextFrame(FitBagsBar)
    end, M)
    if M.db.bagStyle == "micro" then
        hooksecurefunc(MainMenuBarBackpackButton, "UpdateTextures", StyleBackpack)
        if MicroMenu.UpdateScale then hooksecurefunc(MicroMenu, "UpdateScale", FitBagsBar) end
    end
    FitBagsBar()
end

-- Earlier versions had checkboxes; fold them into the dropdowns.
function M:OnLoad()
    local db = self.db
    if db.singleBag ~= nil then
        db.bagStyle = db.singleBag and "micro" or "full"
        db.singleBag = nil
    end
    if db.slide ~= nil then
        db.animation = db.slide and "auto" or "fade"
        db.slide = nil
    end
end

local function HideMicroArt()
    if MicroMenu.BorderArt then MicroMenu.BorderArt:SetAlpha(0) end
    if MicroMenu.BackgroundArt then MicroMenu.BackgroundArt:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Slide / fade animations (one set per frame)
---------------------------------------------------------------------------
local function MakeAnims(f)
    local a = {}

    -- Show: instantly jump to the hidden offset (invisible), then slide back + fade in.
    a.show = f:CreateAnimationGroup()
    a.jump = a.show:CreateAnimation("Translation")
    a.jump:SetDuration(0.001)
    a.jump:SetOrder(1)
    local blank = a.show:CreateAnimation("Alpha")
    blank:SetFromAlpha(0); blank:SetToAlpha(0); blank:SetDuration(0.001); blank:SetOrder(1)
    a.slideIn = a.show:CreateAnimation("Translation")
    a.slideIn:SetDuration(DURATION); a.slideIn:SetOrder(2); a.slideIn:SetSmoothing("OUT")
    local fadeIn = a.show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(DURATION); fadeIn:SetOrder(2)

    -- Hide: slide toward the edge + fade out; ends invisible at the normal spot.
    a.hide = f:CreateAnimationGroup()
    a.slideOut = a.hide:CreateAnimation("Translation")
    a.slideOut:SetDuration(DURATION); a.slideOut:SetSmoothing("IN")
    local fadeOut = a.hide:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(DURATION)
    a.hide:SetToFinalAlpha(true)
    a.hide:SetScript("OnFinished", function() f:SetAlpha(0) end)

    anims[f] = a
    return a
end

local function AnyAnimating()
    for _, a in pairs(anims) do
        if a.show:IsPlaying() or a.hide:IsPlaying() then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Hover zone: union of the managed frames, grown to touch nearby screen edges.
-- Only recomputed while nothing is animating. Reuses one table.
---------------------------------------------------------------------------
local function UpdateZone()
    if AnyAnimating() then return end
    local l, b, r, t
    for i = 1, #frames do
        local f = frames[i]
        if IsManaged(f) then
            -- The backpack may sit a few px outside BagsBar after auto-align.
            local visual = (f == BagsBar and M.db.bagStyle ~= "full") and MainMenuBarBackpackButton or f
            local fl, fb, fr, ft = Rect(visual)
            if fl then
                l = l and math.min(l, fl) or fl
                b = b and math.min(b, fb) or fb
                r = r and math.max(r, fr) or fr
                t = t and math.max(t, ft) or ft
            end
        end
    end
    if not l then zone.valid = false; return end

    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local dLeft, dRight, dBottom, dTop = l, W - r, b, H - t

    -- Slide direction: a horizontal strip goes to the nearer of top/bottom, a
    -- vertical one to the nearer of left/right; or whatever the user picked.
    local edge = M.db.animation
    if edge == "auto" or edge == "fade" then
        if (r - l) >= (t - b) then
            edge = dBottom <= dTop and "down" or "up"
        else
            edge = dLeft <= dRight and "left" or "right"
        end
    end

    zone.l = dLeft <= EDGE_SNAP and 0 or (l - ZONE_PAD)
    zone.r = dRight <= EDGE_SNAP and W or (r + ZONE_PAD)
    zone.b = dBottom <= EDGE_SNAP and 0 or (b - ZONE_PAD)
    zone.t = dTop <= EDGE_SNAP and H or (t + ZONE_PAD)

    -- Hidden offset: far enough to slide fully past that edge.
    zone.dx, zone.dy = 0, 0
    if edge == "left" then zone.dx = -(r + 4)
    elseif edge == "right" then zone.dx = (W - l) + 4
    elseif edge == "down" then zone.dy = -(t + 4)
    else zone.dy = (H - b) + 4 end
    zone.valid = true
end

local function CursorInZone()
    if not zone.valid then return false end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    x, y = x / s, y / s
    return x >= zone.l and x <= zone.r and y >= zone.b and y <= zone.t
end

-- The sensor sits over the hidden frames; it only notices the mouse entering
-- (motion), clicks pass through to whatever is underneath.
local function PlaceSensor()
    if visible or not zone.valid then sensor:Hide(); return end
    sensor:ClearAllPoints()
    sensor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", zone.l, zone.b)
    sensor:SetSize(math.max(1, zone.r - zone.l), math.max(1, zone.t - zone.b))
    sensor:Show()
end

-- Something moved or resized: keep zone and sensor right while hidden.
Refresh = function()
    if visible then return end
    UpdateZone()
    PlaceSensor()
end

---------------------------------------------------------------------------
-- Show / hide
---------------------------------------------------------------------------
local function SetOffsets(f, a)
    local dx, dy = 0, 0
    if M.db.animation ~= "fade" and zone.valid then
        -- Translation offsets are in the frame's own (scaled) units.
        local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
        dx, dy = zone.dx * k, zone.dy * k
    end
    a.jump:SetOffset(dx, dy)
    a.slideIn:SetOffset(-dx, -dy)
    a.slideOut:SetOffset(dx, dy)
end

local function ShowFrame(f, animate)
    local a = anims[f] or MakeAnims(f)
    if a.hide:IsPlaying() then
        a.hide:Stop() -- reverse mid-hide: just snap back
        f:SetAlpha(1)
        return
    end
    if f:GetAlpha() >= 1 or a.show:IsPlaying() then return end
    f:SetAlpha(1)
    if animate then
        SetOffsets(f, a)
        a.show:Play()
    end
end

local function HideFrame(f, animate)
    local a = anims[f] or MakeAnims(f)
    if a.show:IsPlaying() then a.show:Stop() end
    if f:GetAlpha() <= 0 or a.hide:IsPlaying() then return end
    if animate then
        SetOffsets(f, a)
        a.hide:Play()
    else
        f:SetAlpha(0)
    end
end

local function SetVisible(show, animate)
    if show then
        visible = true
        leftAt = nil
        sensor:Hide()
        RefreshMicroButtons()
        if M.db.bagStyle ~= "full" and BagsBarNeedsFit() then FitBagsBar() end
        if M.db.bagStyle == "micro" then AlignBackpack() end
        UpdateZone()
        for i = 1, #frames do
            if IsManaged(frames[i]) then ShowFrame(frames[i], animate) end
        end
        poller:Show() -- start the visible-only check
    else
        UpdateZone() -- frames are at rest here; this is the spot the sensor covers
        visible = false
        for i = 1, #frames do
            if IsManaged(frames[i]) then HideFrame(frames[i], animate) end
        end
        poller:Hide()
        PlaceSensor()
    end
end

-- Runs only while visible.
local elapsed = 0
local function OnPoll(_, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0

    if not AnyAnimating() then
        if M.db.bagStyle ~= "full" and BagsBarNeedsFit() then FitBagsBar() end
        if M.db.bagStyle == "micro" then AlignBackpack() end -- follows Edit Mode drags
        UpdateZone()
    end
    if editMode or CursorInZone() then
        leftAt = nil
    else
        leftAt = leftAt or GetTime()
        if GetTime() - leftAt >= (M.db.hideDelay or 0) then
            SetVisible(false, true)
        end
    end
end

function M:OnEnable()
    if not (MicroMenu and MicroMenuContainer and BagsBar) then return end
    frames[1], frames[2] = MicroMenu, BagsBar

    sensor = CreateFrame("Frame", nil, UIParent)
    sensor:SetFrameStrata("HIGH")
    sensor:SetMouseMotionEnabled(true)
    sensor:SetMouseClickEnabled(false)
    sensor:SetScript("OnEnter", function() SetVisible(true, true) end)
    sensor:Hide()

    poller = CreateFrame("Frame")
    poller:SetScript("OnUpdate", function(f, dt)
        if not ns.safecall(OnPoll, f, dt) then f:Hide() end -- report once, don't repeat per frame
    end)
    poller:Hide()

    RefreshMicroButtons()
    if self.db.bagStyle ~= "full" then SetupSingleBag() end
    if self.db.hideMicroArt then HideMicroArt() end

    -- Vehicle / pet battle: Blizzard borrows the micro menu; show it normally.
    hooksecurefunc(MicroMenu, "OverrideMicroMenuPosition", function()
        local a = anims[MicroMenu]
        if a then a.show:Stop(); a.hide:Stop() end
        MicroMenu:SetAlpha(1)
        Refresh()
    end)
    hooksecurefunc(MicroMenu, "ResetMicroMenuPosition", function()
        RefreshMicroButtons()
        if not visible then MicroMenu:SetAlpha(0) end
        Refresh()
    end)
    -- Buttons appear/disappear (level-ups, game rules), scale or screen changes.
    hooksecurefunc(MicroMenu, "Layout", function()
        RefreshMicroButtons()
        Refresh()
    end)
    ns:On("UI_SCALE_CHANGED", Refresh)
    ns:On("DISPLAY_SIZE_CHANGED", Refresh)

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        editMode = true
        SetVisible(true, false)
    end, M)
    EventRegistry:RegisterCallback("EditMode.Exit", function() editMode = false end, M)
    editMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false

    if editMode then SetVisible(true, false) else SetVisible(false, false) end
end
