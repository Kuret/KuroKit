-- Tooltip: default-positioned tooltips follow the mouse cursor.
--
-- Every default-anchored tooltip (units, world objects, action buttons, bags...)
-- goes through GameTooltip_SetDefaultAnchor; after Blizzard's version runs we
-- re-anchor the tooltip to a 1x1 frame that sits on the cursor. That frame only
-- updates while a tooltip is shown, and only moves when the cursor moved.
-- Tooltips an addon positions itself are left alone.
--
-- Details:
--  * Forbidden owners (e.g. Blizzard's nameplate aura buttons) can't be touched
--    from addon code; those keep Blizzard's anchor.
--  * World-unit tooltips normally fade out over ~1-2 s; riding the cursor that
--    fade trails behind the pointer, so they hide instantly instead.
--  * Stand-in tooltips flagged LIKE_GLOBAL_GAMETOOLTIP count as the main one.
--  * Gamepad UI: the mouse cursor isn't where you're looking, so Blizzard's
--    normal position is kept.
local _, ns = ...

local M = ns:NewModule("Tooltip", {
    title = "Tooltip at Cursor",
    group = "Interface",
    desc = "Tooltips follow the mouse cursor instead of sitting in the corner.",
    defaults = { position = "bottomright", offsetX = 0, offsetY = 0 },
    options = {
        { type = "dropdown", key = "position", name = "Position",
          tooltip = "Where the tooltip sits relative to the cursor.",
          values = {
              { "bottomright", "Below right" }, { "bottomleft", "Below left" },
              { "topright", "Above right" }, { "topleft", "Above left" },
              { "right", "Right" }, { "left", "Left" },
              { "top", "Above" }, { "bottom", "Below" },
          } },
        { type = "slider", key = "offsetX", name = "Horizontal offset", min = -64, max = 64, step = 1,
          tooltip = "Extra space to the right (negative: left). 0 = right next to the cursor; "
              .. "the cursor's own size is already skipped." },
        { type = "slider", key = "offsetY", name = "Vertical offset", min = -64, max = 64, step = 1,
          tooltip = "Extra space upward (negative: downward). 0 = right next to the cursor; "
              .. "the cursor's own size is already skipped." },
    },
})

-- Until v0.2 the offsets were measured from the cursor tip (seeded 24, -24);
-- they're now extra space beyond the cursor, so start those over at 0.
function M:OnLoad()
    if not self.db.cursorAwareOffsets then
        self.db.offsetX, self.db.offsetY = 0, 0
        self.db.cursorAwareOffsets = true
    end
end

-- Each position hangs off the cursor *icon's box*, not its tip. The box hangs
-- down-right from the tip (the hotspot): x from 0 to +W, y from 0 to -H.
--   corner = the tooltip's corner/edge that touches the box
--   box    = the point on the box, as fractions of (W, H)
--   gap    = extra space in pixels, pointing away from the cursor
-- Tuned in game; edit the numbers here to move one position independently.
local LAYOUT = {
    bottomright = { corner = "TOPLEFT",     box = { 1, -1 },   gap = { 4, -4 } },
    bottomleft  = { corner = "TOPRIGHT",    box = { 0, -1 },   gap = { -4, -4 } },
    topright    = { corner = "BOTTOMLEFT",  box = { 1, 0 },    gap = { 4, 4 } },
    topleft     = { corner = "BOTTOMRIGHT", box = { 0, 0 },    gap = { -11, 11 } },
    right       = { corner = "LEFT",        box = { 1, -0.5 }, gap = { 6, 0 } },
    left        = { corner = "RIGHT",       box = { 0, -0.5 }, gap = { -12, 0 } },
    top         = { corner = "BOTTOM",      box = { 0, 0 },    gap = { 0, 11 } },
    bottom      = { corner = "TOP",         box = { 0.5, -1 }, gap = { 0, -6 } },
}

-- Icon box size as a fraction of the cursor image: cursor icons (arrow, loot
-- bag, speech bubble...) fill roughly this much of their square image.
local ICON_BOX = 0.6

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

-- Current cursor anchor, so it can be re-applied when the health bar appears.
local anchor = { tooltip = nil, corner = "TOPLEFT", x = 0, y = 0, above = false }

-- Unit tooltips have a health bar hanging *below* the tooltip frame (shown once
-- the unit is known, i.e. after anchoring). Above the cursor, lift the tooltip
-- by the bar's real extent so the bar doesn't cover the cursor either.
local function BarExtent(tooltip)
    local bar = tooltip.StatusBar
    if not (anchor.above and bar and bar:IsShown()) then return 0 end
    local tooltipBottom, barBottom = tooltip:GetBottom(), bar:GetBottom()
    if tooltipBottom and barBottom and tooltipBottom > barBottom then
        return tooltipBottom - barBottom
    end
    return (bar:GetHeight() or 8) + 1
end

local function PlaceTooltip()
    local tooltip = anchor.tooltip
    if not tooltip then return end
    tooltip:ClearAllPoints()
    tooltip:SetPoint(anchor.corner, follower, "CENTER", anchor.x, anchor.y + BarExtent(tooltip))
end

local function OnDefaultAnchor(tooltip, owner)
    if not IsMainTooltip(tooltip) then return end
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then return end
    if not UsableOwner(owner) or tooltip:IsForbidden() then return end

    -- Position the follower *now*: its OnUpdate only runs next frame, and a
    -- tooltip shown this frame needs a valid anchor immediately.
    lastX = nil
    follower:Show()
    MoveToCursor()

    local db = M.db
    local layout = LAYOUT[db.position] or LAYOUT.bottomright
    local scale = tooltip:GetEffectiveScale()
    local box = PixelsToUnits(CursorPixels() * ICON_BOX, scale)
    local x = db.offsetX + layout.box[1] * box + PixelsToUnits(layout.gap[1], scale)
    local y = db.offsetY + layout.box[2] * box + PixelsToUnits(layout.gap[2], scale)

    anchor.tooltip, anchor.corner, anchor.x, anchor.y = tooltip, layout.corner, x, y
    anchor.above = layout.gap[2] > 0
    tooltip:SetOwner(owner, "ANCHOR_NONE")
    PlaceTooltip()
    if tooltip == GameTooltip then riding = true end
end

function M:OnEnable()
    follower = CreateFrame("Frame", nil, UIParent)
    follower:SetSize(1, 1)
    follower:SetFrameStrata("TOOLTIP")
    follower:SetScript("OnUpdate", MoveToCursor)
    follower:Hide()

    hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
    local bar = GameTooltip.StatusBar
    if bar then
        local function OnBarToggled()
            if riding and anchor.above and anchor.tooltip == GameTooltip then PlaceTooltip() end
        end
        bar:HookScript("OnShow", OnBarToggled)
        bar:HookScript("OnHide", OnBarToggled)
    end
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
