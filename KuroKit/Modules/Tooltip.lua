-- Tooltip: default-positioned tooltips follow the mouse cursor, below-right of
-- the cursor icon.
--
-- Every default-anchored tooltip (units, world objects, action buttons, bags...)
-- goes through GameTooltip_SetDefaultAnchor; after Blizzard's version runs we
-- re-anchor the tooltip to a 1x1 frame that sits on the cursor. That frame only
-- updates while a tooltip is shown, and only moves when the cursor moved.
-- Tooltips an addon positions itself are left alone.
--
-- Details:
--  * The tooltip's top-left corner sits just past the cursor icon's bottom-right
--    corner (cursor size from the Accessibility setting), so it never covers it.
--  * Forbidden owners (e.g. Blizzard's nameplate aura buttons) can't be touched
--    from addon code; those keep Blizzard's anchor.
--  * World-unit tooltips normally fade out over ~1-2 s; riding the cursor that
--    fade trails behind the pointer, so they hide instantly instead.
--  * Stand-in tooltips flagged LIKE_GLOBAL_GAMETOOLTIP count as the main one.
--  * Gamepad UI, or the last input came from a controller (Core/Input.lua):
--    the mouse cursor isn't where you're looking, so Blizzard's normal
--    position is kept.
local _, ns = ...

local M = ns:NewModule("Tooltip", {
    title = "Tooltip at Cursor",
    group = "Interface",
    desc = "Tooltips follow the mouse cursor, just below and to the right of it, instead of sitting in the corner.",
})

-- Position and offsets used to be options; now fixed. Drop their stored values.
function M:OnLoad()
    local db = self.db
    db.position, db.offsetX, db.offsetY, db.cursorAwareOffsets = nil, nil, nil, nil
end

-- Cursor icons (arrow, loot bag, speech bubble...) fill roughly this much of
-- their square image; the tooltip goes just past that box.
local ICON_BOX = 0.6
local GAP = 4 -- pixels between the cursor icon and the tooltip (tuned in game)

-- Cursor sizes from the Accessibility setting "cursorSizePreferred".
local CURSOR_SIZES = { [0] = 32, [1] = 48, [2] = 64, [3] = 96, [4] = 128 }

-- Cursor size in pixels. "Default" (-1) is sized for the display; use the step
-- closest to 32 px at 1080p scaled to the screen height.
local function CursorPixels()
    local px = CURSOR_SIZES[tonumber(GetCVar("cursorSizePreferred")) or -1]
    if px then return px end
    local _, physH = GetPhysicalScreenSize()
    local want = 32 * (physH or 1080) / 1080
    local best = 32
    for _, size in pairs(CURSOR_SIZES) do
        if math.abs(size - want) < math.abs(best - want) then best = size end
    end
    return best
end

-- Pixels -> units of a frame with effective scale `scale` (the UI is 768 units
-- tall at effective scale 1).
local function PixelsToUnits(px, scale)
    local _, physH = GetPhysicalScreenSize()
    return px * 768 / ((physH or 768) * scale)
end

local follower          -- 1x1 frame on the cursor
local lastX, lastY
local riding = false    -- GameTooltip is currently anchored to the cursor by us

local function MoveToCursor()
    local x, y = GetCursorPosition()
    if x == lastX and y == lastY then return end
    lastX, lastY = x, y
    local s = UIParent:GetEffectiveScale()
    follower:ClearAllPoints()
    follower:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end

local function IsMainTooltip(tooltip)
    return tooltip == GameTooltip or (type(tooltip) == "table" and tooltip.LIKE_GLOBAL_GAMETOOLTIP == true)
end

-- A forbidden frame only allows IsForbidden(); ask that first, touch nothing else.
local function UsableOwner(owner)
    if not owner then return false end
    local isForbidden = owner.IsForbidden
    return not (type(isForbidden) == "function" and isForbidden(owner))
end

local function OnDefaultAnchor(tooltip, owner)
    if not IsMainTooltip(tooltip) then return end
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then return end
    if ns.PadActive() then return end -- playing with a controller: the cursor isn't where you look
    if not UsableOwner(owner) or tooltip:IsForbidden() then return end

    -- Position the follower *now*: its OnUpdate only runs next frame, and a
    -- tooltip shown this frame needs a valid anchor immediately.
    lastX = nil
    follower:Show()
    MoveToCursor()

    local scale = tooltip:GetEffectiveScale()
    local box = PixelsToUnits(CursorPixels() * ICON_BOX, scale)
    local gap = PixelsToUnits(GAP, scale)
    tooltip:SetOwner(owner, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", follower, "CENTER", box + gap, -box - gap)
    if tooltip == GameTooltip then riding = true end
end

function M:OnEnable()
    follower = CreateFrame("Frame", nil, UIParent)
    follower:SetSize(1, 1)
    follower:SetFrameStrata("TOOLTIP")
    follower:SetScript("OnUpdate", MoveToCursor)
    follower:Hide()

    hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
    GameTooltip:HookScript("OnHide", function()
        riding = false
        follower:Hide() -- stops the OnUpdate until the next tooltip
    end)
    if GameTooltip.FadeOut then
        hooksecurefunc(GameTooltip, "FadeOut", function(self)
            if riding and self == GameTooltip then self:Hide() end
        end)
    end
end
