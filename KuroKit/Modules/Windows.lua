-- Windows (replaces MoveAny's window moving): Blizzard's windows can be moved
-- and scaled, and keep their place.
--   * left-drag on empty window space: move (snaps to the screen edges and
--     other windows' edges when close, else to an 8 px grid)
--   * mouse wheel over the title bar: scale (50-200%)
--   * right-click on the title bar: scale back to 100%
--   * positions and scales are remembered (account-wide);
--     /kk windows reset forgets them
--
-- How: each window in WINDOWS gets HookScript'ed mouse handlers (never
-- replacing Blizzard's) once it exists (windows of load-on-demand addons when
-- they load). Saved spot: the window's top-left corner in UIParent
-- coordinates, plus its scale; applied when the window shows and whenever
-- something else positions it (a hooksecurefunc post-hook on the window's
-- SetPoint: Blizzard's panel manager places windows from its secure frame
-- after they show, and that frame must never be touched). Windows the game
-- protects aren't touched in combat (queued until it ends).
-- Cost: nothing while no window is dragged; one OnUpdate while dragging.
local _, ns = ...

local M = ns:NewModule("Windows", {
    title = "Movable Windows",
    group = "Interface",
    desc = "Drag Blizzard's windows by their empty space (they snap to edges), scroll on the title bar to scale, "
        .. "right-click the title bar for 100%. Positions are remembered. /kk windows reset forgets them.",
})

-- Blizzard windows (those that don't exist on this client are skipped).
local WINDOWS = {
    "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsBookFrame", "ProfessionsFrame",
    "TradeSkillFrame", "CraftFrame", "FriendsFrame", "CommunitiesFrame", "LFGParentFrame", "PVEFrame",
    "PVPParentFrame", "EncounterJournal", "AchievementFrame", "CollectionsJournal", "WorldMapFrame",
    "QuestLogFrame", "QuestFrame", "GossipFrame", "MerchantFrame", "ClassTrainerFrame", "TaxiFrame",
    "FlightMapFrame", "MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame",
    "AuctionFrame", "TradeFrame", "DressUpFrame", "TransmogFrame", "WardrobeFrame", "InspectFrame",
    "MacroFrame", "AddonList", "SettingsPanel", "GameMenuFrame", "ChatConfigFrame", "TimeManagerFrame",
    "CalendarFrame", "ItemTextFrame", "TabardFrame", "PetStableFrame", "StableFrame", "ItemSocketingFrame",
    "ItemUpgradeFrame", "HelpFrame", "QuickKeybindFrame", "ClickBindingFrame", "CooldownViewerSettings",
    "ScriptErrorsFrame", "ChannelFrame", "LegacySystemFrame", "SocialUIFrame", "ShardTransferImminentFrame",
    "GuildControlUI", "ArchaeologyFrame", "BlackMarketFrame",
}

local GRID = 8            -- px grid a dropped window snaps to
local SNAP = 10           -- px: closer than this to an edge snaps to it
local DRAG_START = 4      -- px the mouse moves before a press becomes a drag
local TITLE_HEIGHT = 24   -- px: the top of a window without a TitleContainer
local SCALE_STEP = 0.05
local SCALE_MIN, SCALE_MAX = 0.5, 2
local TOOLTIP_TIME = 1    -- seconds the scale tooltip stays

local managed = {}        -- [frame] = name
local placing = false     -- our own SetPoint calls (the SetPoint hook ignores them)
local queued = {}         -- [frame] = true: re-apply once combat ends
local drag                -- the drag under way
local tooltipTimer

local function Saved(name)
    M.db.windows = M.db.windows or {}
    return M.db.windows[name]
end

local function Save(name, x, y, scale)
    M.db.windows = M.db.windows or {}
    M.db.windows[name] = { x = x, y = y, scale = scale }
end

-- The window's scale relative to UIParent (what positions are measured in).
local function RelScale(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Blocked(frame)
    return InCombatLockdown() and frame:IsProtected()
end

-- Top-left corner in UIParent coordinates.
local function TopLeft(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return nil end
    local rel = RelScale(frame)
    return left * rel, top * rel
end

local function Place(frame, x, y)
    local rel = RelScale(frame)
    placing = true
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / rel, y / rel)
    placing = false
end

local function Apply(frame)
    local name = managed[frame]
    local saved = name and Saved(name)
    if not saved or frame.isMaximized then return end
    if Blocked(frame) then
        if not queued[frame] then
            queued[frame] = true
            ns:OutOfCombat(function() queued[frame] = nil; Apply(frame) end)
        end
        return
    end
    if saved.scale and math.abs(frame:GetScale() - saved.scale) > 0.001 then frame:SetScale(saved.scale) end
    if saved.x and saved.y then Place(frame, saved.x, saved.y) end
end

---------------------------------------------------------------------------
-- Dragging with snapping
---------------------------------------------------------------------------
local function Cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- Nearest of `candidates` within SNAP of `value`, else `value` on the grid.
local function SnapValue(value, candidates)
    local best, bestDistance = nil, SNAP
    for _, c in ipairs(candidates) do
        local d = math.abs(c - value)
        if d < bestDistance then best, bestDistance = c, d end
    end
    return best or math.floor(value / GRID + 0.5) * GRID
end

-- Snapped top-left for a window of size w x h dropped at x, y.
local function Snap(frame, x, y, w, h)
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local xs, ys = { 0, screenW - w }, { screenH, h }
    for other in pairs(managed) do
        if other ~= frame and other:IsVisible() then
            local ox, oy = TopLeft(other)
            if ox then
                local rel = RelScale(other)
                local ow, oh = other:GetWidth() * rel, other:GetHeight() * rel
                -- beside it, or edges lined up
                xs[#xs + 1] = ox + ow; xs[#xs + 1] = ox - w; xs[#xs + 1] = ox; xs[#xs + 1] = ox + ow - w
                ys[#ys + 1] = oy - oh; ys[#ys + 1] = oy + h; ys[#ys + 1] = oy; ys[#ys + 1] = oy - oh + h
            end
        end
    end
    x = SnapValue(x, xs)
    y = SnapValue(y, ys)
    -- keep it on screen
    x = math.max(0, math.min(x, screenW - w))
    y = math.min(screenH, math.max(y, h))
    return x, y
end

local dragFrame = CreateFrame("Frame")
dragFrame:Hide()

dragFrame:SetScript("OnUpdate", function()
    local d = drag
    if not d then dragFrame:Hide() return end
    if not IsMouseButtonDown("LeftButton") or not d.frame:IsVisible() or Blocked(d.frame) then
        drag = nil
        dragFrame:Hide()
        if d.moving then Save(d.name, d.x, d.y, d.frame:GetScale()) end
        return
    end
    local cx, cy = Cursor()
    if not d.moving then
        if math.abs(cx - d.startX) < DRAG_START and math.abs(cy - d.startY) < DRAG_START then return end
        d.moving = true
    end
    d.x, d.y = Snap(d.frame, d.originX + cx - d.startX, d.originY + cy - d.startY, d.w, d.h)
    Place(d.frame, d.x, d.y)
end)

---------------------------------------------------------------------------
-- Title bar: scale with the wheel, right-click for 100%
---------------------------------------------------------------------------
local function OverTitle(frame)
    local title = frame.TitleContainer
    if title and title:IsVisible() then return title:IsMouseOver() end
    local top = frame:GetTop()
    if not top then return false end
    local _, y = GetCursorPosition()
    return y / frame:GetEffectiveScale() >= top - TITLE_HEIGHT
end

local function ShowScale(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetText(("%d%%"):format(frame:GetScale() * 100 + 0.5), 1, 1, 1)
    if tooltipTimer then tooltipTimer:Cancel() end
    tooltipTimer = C_Timer.NewTimer(TOOLTIP_TIME, function()
        tooltipTimer = nil
        if GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
    end)
end

local function SetWindowScale(frame, scale)
    local name = managed[frame]
    if not name or Blocked(frame) then return end
    local x, y = TopLeft(frame)
    if not x then return end
    scale = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(scale / SCALE_STEP + 0.5) * SCALE_STEP))
    frame:SetScale(scale)
    Place(frame, x, y) -- the top-left corner stays put
    Save(name, x, y, scale)
    ShowScale(frame)
end

---------------------------------------------------------------------------
-- Setup per window
---------------------------------------------------------------------------
local function OnMouseDown(frame, button)
    if button ~= "LeftButton" or Blocked(frame) or frame.isMaximized then return end
    local x, y = TopLeft(frame)
    if not x then return end
    local rel = RelScale(frame)
    local cx, cy = Cursor()
    drag = {
        frame = frame, name = managed[frame], startX = cx, startY = cy, originX = x, originY = y,
        w = frame:GetWidth() * rel, h = frame:GetHeight() * rel,
    }
    dragFrame:Show()
end

local function OnMouseUp(frame, button)
    if button == "RightButton" and OverTitle(frame) then SetWindowScale(frame, 1) end
end

local function OnMouseWheel(frame, delta)
    if OverTitle(frame) then SetWindowScale(frame, frame:GetScale() + delta * SCALE_STEP) end
end

local function Setup(frame, name)
    if managed[frame] or frame:IsForbidden() then return end
    if frame:IsProtected() and InCombatLockdown() then
        ns:OutOfCombat(function() Setup(frame, name) end)
        return
    end
    managed[frame] = name
    if not frame:IsMouseEnabled() then frame:EnableMouse(true) end
    frame:EnableMouseWheel(true)
    frame:HookScript("OnMouseDown", OnMouseDown)
    frame:HookScript("OnMouseUp", OnMouseUp)
    frame:HookScript("OnMouseWheel", OnMouseWheel)
    frame:HookScript("OnShow", Apply)
    -- Someone else positioned the window (Blizzard's panel layout): back to
    -- the saved spot, unless it's being dragged.
    hooksecurefunc(frame, "SetPoint", function(f)
        if placing or (drag and drag.frame == f) then return end
        Apply(f)
    end)
    if frame:IsShown() then Apply(frame) end
end

local function Scan()
    for _, name in ipairs(WINDOWS) do
        local frame = _G[name]
        if type(frame) == "table" and frame.GetObjectType and not managed[frame] then
            Setup(frame, name)
        end
    end
end

function M:OnSlash(args)
    local cmd, name = (args or ""):match("^(%S*)%s*(%S*)")
    if cmd:lower() ~= "reset" then
        ns:Print("/kk windows reset [window name]: forget saved window positions and scales (all, or one)")
        return
    end
    M.db.windows = M.db.windows or {}
    if name ~= "" then
        M.db.windows[name] = nil
        ns:Print(name .. ": position forgotten; /reload to see Blizzard's default")
    else
        wipe(M.db.windows)
        ns:Print("all window positions forgotten; /reload to see Blizzard's defaults")
    end
end

function M:OnEnable()
    Scan()
    ns:On("ADDON_LOADED", Scan) -- windows of load-on-demand addons
end
