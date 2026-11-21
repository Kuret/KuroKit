-- MenuTray: the micro menu and bag bar stay hidden and slide in from a screen edge
-- while the mouse is over their spot (Core/HoverReveal.lua does the hiding and
-- sliding). The bag bar shrinks to just the backpack, styled like a micro menu
-- button and auto-aligned to the menu, and the micro menu's frame art is hidden.
--
-- Edit Mode stays in charge of where they are: place both with Edit Mode (snap
-- them together for one strip). We never move or re-anchor the Edit Mode system
-- frames. On Forever the main action bar is anchored to MicroMenuContainer, so we
-- only animate MicroMenu (the button strip inside it) and BagsBar, which nothing
-- else is anchored to (checked against Blizzard's exported UI code).
--
-- Left alone:
--  * Edit Mode open: everything shown (HoverReveal).
--  * Vehicle / pet battle: Blizzard borrows MicroMenu (OverrideMicroMenuPosition);
--    then it's shown normally until ResetMicroMenuPosition.
--  * Gamepad UI: Blizzard hides both frames itself.
local _, ns = ...

local M = ns:NewModule("MenuTray", {
    title = "Micro Menu & Bags",
    group = "Interface",
    desc = "Hide the micro menu and bag bar until you hover their spot; they slide in from the screen edge. Place them with Edit Mode.",
})

local reveal               -- HoverReveal group
local microButtons = {}    -- cached visible micro buttons (refreshed on reveal / layout)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ScreenCenter(f)
    local x, y = f:GetCenter()
    if not x then return end
    local s = f:GetEffectiveScale()
    return x * s, y * s
end

local function IsBorrowed()
    return MicroMenu:GetParent() ~= MicroMenuContainer
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
    StyleBackpack()
    for _, pool in ipairs({ BagsBar.HorizontalDividersPool, BagsBar.VerticalDividersPool }) do
        if pool then
            for divider in pool:EnumerateActive() do divider:Hide() end
        end
    end
    local w, h = MainMenuBarBackpackButton:GetSize()
    BagsBar:SetSize(w, h)
    alignX = nil -- Layout re-anchored the backpack; re-apply our offset
    AlignBackpack()
    if reveal then reveal:Refresh() end
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
    hooksecurefunc(MainMenuBarBackpackButton, "UpdateTextures", StyleBackpack)
    if MicroMenu.UpdateScale then hooksecurefunc(MicroMenu, "UpdateScale", FitBagsBar) end
    FitBagsBar()
end

-- These used to be options; now fixed. Drop their stored values.
function M:OnLoad()
    local db = self.db
    db.singleBag, db.slide, db.bagStyle, db.hideMicroArt, db.animation, db.hideDelay = nil, nil, nil, nil, nil, nil
end

local function HideMicroArt()
    if MicroMenu.BorderArt then MicroMenu.BorderArt:SetAlpha(0) end
    if MicroMenu.BackgroundArt then MicroMenu.BackgroundArt:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Hover reveal
---------------------------------------------------------------------------
local function KeepBagFitted()
    if BagsBarNeedsFit() then FitBagsBar() end
    AlignBackpack() -- follows Edit Mode drags
end

function M:OnEnable()
    if not (MicroMenu and MicroMenuContainer and BagsBar) then return end

    reveal = ns.NewHoverReveal({
        targets = function(list)
            if MicroMenu:IsShown() and not IsBorrowed() then list[#list + 1] = MicroMenu end
            if BagsBar:IsShown() then list[#list + 1] = BagsBar end
        end,
        zone = function(list)
            if MicroMenu:IsShown() and not IsBorrowed() then list[#list + 1] = MicroMenu end
            if BagsBar:IsShown() then
                -- The backpack may sit a few px outside BagsBar after auto-align.
                list[#list + 1] = MainMenuBarBackpackButton
            end
        end,
        onShow = function()
            RefreshMicroButtons()
            KeepBagFitted()
        end,
        onPoll = KeepBagFitted,
    })

    RefreshMicroButtons()
    SetupSingleBag()
    HideMicroArt()

    -- Vehicle / pet battle: Blizzard borrows the micro menu; show it normally.
    hooksecurefunc(MicroMenu, "OverrideMicroMenuPosition", function()
        reveal:Release(MicroMenu)
        reveal:Refresh()
    end)
    hooksecurefunc(MicroMenu, "ResetMicroMenuPosition", function()
        RefreshMicroButtons()
        reveal:Reapply()
        reveal:Refresh()
    end)
    -- Buttons appear/disappear (level-ups, game rules), scale or screen changes.
    hooksecurefunc(MicroMenu, "Layout", function()
        RefreshMicroButtons()
        reveal:Refresh()
    end)
    ns:On("UI_SCALE_CHANGED", function() reveal:Refresh() end)
    ns:On("DISPLAY_SIZE_CHANGED", function() reveal:Refresh() end)

    reveal:Start()
end
