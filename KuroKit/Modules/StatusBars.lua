-- StatusBars: the experience / reputation bars stay hidden and slide in from a
-- screen edge while the mouse is over their spot (Core/HoverReveal.lua), and
-- the experience bar is kept in Status Bar 1.
--
-- Edit Mode stays in charge of where they are. Blizzard manages the containers'
-- own alpha (fade in/out when a bar appears, max level) and reads it in its logic
-- (SetShownBar checks GetAlpha), so we never touch the containers themselves:
-- only their contents (the bar frames, divider ticks and the border texture).
-- Nothing else is anchored to these containers (default bottom bars stack from
-- the screen bottom), so sliding them can't drag other bars along.
--
-- XP in Status Bar 1: Blizzard fills the slots by a fixed priority (on Forever
-- Reputation 2 > Experience 0), so tracking a reputation moves XP to slot 2.
-- Changing Blizzard's priorities or slot assignment from addon code would taint
-- a path that ends in Edit Mode moving the (protected) action bars, so instead we
-- only swap where the two bars are *drawn*: each slot owns a copy of every bar,
-- anchored once at creation (BOTTOMLEFT +1,+2) and never re-anchored by Blizzard.
local _, ns = ...

local M = ns:NewModule("StatusBars", {
    title = "XP & Reputation Bars",
    group = "Interface",
    desc = "Hide the experience and reputation bars until you hover their spot; they slide in from the screen edge. "
        .. "Experience always stays in Status Bar 1. Place them with Edit Mode.",
})

-- These used to be options; now fixed. Drop their stored values.
function M:OnLoad()
    self.db.xpFirst, self.db.animation, self.db.hideDelay = nil, nil, nil
end

local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local containers = {}
local reveal

-- A container's contents: bar frames + divider ticks + its border texture
-- (not Edit Mode's selection overlay).
local function AddContents(list, container)
    for _, child in ipairs({ container:GetChildren() }) do
        if child ~= container.Selection then list[#list + 1] = child end
    end
    if container.BarFrameTexture then list[#list + 1] = container.BarFrameTexture end
end

---------------------------------------------------------------------------
-- Experience bar in Status Bar 1
---------------------------------------------------------------------------
local drawnIn = {} -- [bar] = container it's currently anchored to (only bars we moved)

local function AnchorBar(bar, container)
    if (drawnIn[bar] or bar:GetParent()) == container then return end
    bar:ClearAllPoints()
    -- Same spot Blizzard uses inside a slot (InitializeBars).
    bar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 1, (STATUS_BAR_SIZE_ADJUSTMENT or 3) - 1)
    drawnIn[bar] = container ~= bar:GetParent() and container or nil
end

local function ArrangeBars()
    local main, second = MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not (main and second and main.bars and second.bars and enum) then return end

    local swap = main:IsShown() and second:IsShown()
        and second.shownBarIndex == enum.Experience
        and main.shownBarIndex ~= enum.Experience
        and main.shownBarIndex ~= enum.None

    local mainBar, secondBar = main.bars[main.shownBarIndex], second.bars[second.shownBarIndex]
    for _, container in ipairs({ main, second }) do
        for _, bar in pairs(container.bars) do
            local target = container
            if swap and bar == mainBar then target = second
            elseif swap and bar == secondBar then target = main end
            AnchorBar(bar, target)
        end
    end
end

---------------------------------------------------------------------------
function M:OnEnable()
    for _, name in ipairs(CONTAINERS) do
        if _G[name] then containers[#containers + 1] = _G[name] end
    end
    if #containers == 0 then return end

    reveal = ns.NewHoverReveal({
        targets = function(list)
            for i = 1, #containers do
                if containers[i]:IsShown() then AddContents(list, containers[i]) end
            end
        end,
        zone = function(list)
            for i = 1, #containers do
                if containers[i]:IsShown() then list[#list + 1] = containers[i] end
            end
        end,
    })

    -- New bar shown, dividers rebuilt or a container appearing while hidden:
    -- re-arrange, hide the new parts too and update the hover spot.
    local function Changed()
        ArrangeBars()
        reveal:Reapply()
        reveal:Refresh()
    end
    for _, container in ipairs(containers) do
        container:HookScript("OnShow", Changed)
        container:HookScript("OnHide", function()
            ArrangeBars()
            reveal:Refresh()
        end)
        if container.UpdateDividers then hooksecurefunc(container, "UpdateDividers", Changed) end
        if container.ApplyPendingBarToShow then hooksecurefunc(container, "ApplyPendingBarToShow", Changed) end
    end
    -- Blizzard re-evaluates which bars to show on many events (XP, reputation,
    -- level, entering the world); re-apply after each pass.
    if StatusTrackingBarManager and StatusTrackingBarManager.UpdateBarsShown then
        hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", Changed)
    end
    ns:On("UI_SCALE_CHANGED", function() reveal:Refresh() end)
    ns:On("DISPLAY_SIZE_CHANGED", function() reveal:Refresh() end)

    ArrangeBars()
    reveal:Start()
end
