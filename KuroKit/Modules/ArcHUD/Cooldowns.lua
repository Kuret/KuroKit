-- Arc HUD part: the Cooldown Manager on the HUD's curves (option
-- "cooldowns"): its Essential cooldowns along the outside of your arc (from
-- below the level badge down), its tracked buffs / procs (Buff Icons) along
-- the inside of your arc, its Utility cooldowns along the inside of your
-- target's; each in one row, the icons shrunk to fit it. Blizzard's icons
-- themselves, re-placed after each of the viewer's layouts and whenever an
-- icon shows or hides (shown ones only, packed); Edit Mode's icon size and
-- padding still apply, its position for these three doesn't. They fade with
-- their HUD side (essentials and procs with yours, utility with your
-- target's): the viewer's alpha is Blizzard's times the side's. The rails
-- move out of the class trims' way (Trims.lua A.RailEdge).
-- Essential cooldowns coming off cooldown: a gold ring swelling off the
-- icon, and the icon pulsing big above your character. The pulse queue is
-- shared (the lockouts' ready icon, Trims.lua) and there with the option
-- off too.
local _, ns = ...
local A = ns.ArcHUD
local M, T, sides = A.M, A.T, A.sides
local MEDIA, SCALE, SIDE_W = A.MEDIA, A.SCALE, A.SIDE_W
local ARC_CX, ARC_CY, ARC_HALF = A.ARC_CX, A.ARC_CY, A.ARC_HALF

local RAIL_GAP = 4              -- UI units between the arc and its icons
local RAIL_START = -0.45        -- inside: just below the portrait
local OUTSIDE_RAIL_START = -0.33 -- outside: just below the level badge
local RAIL_END = 0.8            -- the last icon's centre: clear of the numbers under the arcs
local CDM_GAP = 4               -- extra space between icons along a curve
local CDM_LAYOUTS = {
    { viewer = "EssentialCooldownViewer", side = "player", outside = true, flash = true },
    { viewer = "BuffIconCooldownViewer", side = "player" },
    { viewer = "UtilityCooldownViewer", side = "target" },
}

local hookedItems = setmetatable({}, { __mode = "k" })
local queued = {}

-- The viewer's shown icons in their order (Blizzard's list: shown ones,
-- sorted by layout index).
local function ShownItems(viewer)
    local items = viewer:GetItemFrames()
    return type(items) == "table" and items or {}
end

-- All its icons, hidden ones too (to hook their show / hide).
local function AllItems(viewer)
    local all = {}
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child.layoutIndex then all[#all + 1] = child end
    end
    return all
end

-- An icon centred on (x, y) of `anchor`'s top left, in the anchor's units.
local function PlaceItem(item, anchor, x, y)
    local k = anchor:GetEffectiveScale() / item:GetEffectiveScale()
    item:ClearAllPoints()
    item:SetPoint("CENTER", anchor, "TOPLEFT", x * k, y * k)
end

local function ItemSize(item, anchor)
    return item:GetWidth() * item:GetEffectiveScale() / anchor:GetEffectiveScale()
end

-- Edit Mode's icon scale for the viewer's icons.
local function EditScale(viewer)
    return type(viewer.iconScale) == "number" and viewer.iconScale or 1
end

-- The largest icon size (UI units) for `n` icons in a row on a rail along
-- the arc edge at radius `edge` (`sign` -1 inside, +1 outside), their centres
-- spread over `span` radians.
local function FitSize(n, edge, sign, span)
    if n < 2 then return math.huge end
    -- (n - 1) * (size + gap) = (edge + sign * (size / 2 + RAIL_GAP)) * span
    local size = ((edge + sign * RAIL_GAP) * span - (n - 1) * CDM_GAP) / ((n - 1) - sign * span / 2)
    return math.max(8, size)
end

local function ArrangeRail(viewer, layout)
    local s = sides[layout.side]
    local items = ShownItems(viewer)
    if #items == 0 or not s then return end
    local left = layout.side == "player"
    local sign = layout.outside and 1 or -1
    local edge = A.RailEdge(layout) * SCALE
    local start = ARC_HALF * (layout.outside and OUTSIDE_RAIL_START or RAIL_START)
    -- Shrink the icons to fit the row (Edit Mode's size at most).
    local editScale = EditScale(viewer)
    local natural = ItemSize(items[1], s.frame) / items[1]:GetScale() * editScale
    local fit = math.min(1, FitSize(#items, edge, sign, ARC_HALF * RAIL_END - start) / natural)
    for _, item in ipairs(items) do
        if math.abs(item:GetScale() - editScale * fit) > 0.001 then item:SetScale(editScale * fit) end
    end
    local size = natural * fit
    local r = edge + sign * (size / 2 + RAIL_GAP)
    local angle = start
    for _, item in ipairs(items) do
        local x = ARC_CX * SCALE - r * math.cos(angle)
        if not left then x = SIDE_W - x end
        PlaceItem(item, s.frame, x, -(ARC_CY * SCALE + r * math.sin(angle)))
        angle = angle + (size + CDM_GAP) / r
    end
end

-- Edit Mode: Blizzard's own icon size back.
local function RestoreScale(viewer)
    local editScale = EditScale(viewer)
    for _, item in ipairs(ShownItems(viewer)) do
        if item:GetScale() ~= editScale then item:SetScale(editScale) end
    end
end

local function Arrange(layout)
    local viewer = _G[layout.viewer]
    if not viewer or not viewer.GetItemFrames then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then RestoreScale(viewer) return end
    -- Icons show and hide on their own (procs): re-place then too.
    for _, item in ipairs(AllItems(viewer)) do
        if not hookedItems[item] then
            hookedItems[item] = true
            local function Again() A.QueueArrange(layout) end
            item:HookScript("OnShow", Again)
            item:HookScript("OnHide", Again)
            if layout.flash then A.AddReadyFlash(item) end
        end
    end
    ArrangeRail(viewer, layout)
end

-- An icon pulse: an icon popping in big at (x, y) from the HUD's centre,
-- in the action bar icon look with a glow (`color`, or each entry's own),
-- holding, then fading out; queued when several come at once. Built when
-- first played. Returns { Queue(texture, color) }: the texture may be secret
-- (only handed to SetTexture).
function A.NewIconPulse(x, y, size, color, holdTime)
    local pulse, playing
    local queue = {}
    local self = {}

    local function Build()
        local frame = CreateFrame("Frame", nil, sides.player.frame)
        frame:SetSize(size, size)
        frame:SetPoint("CENTER", A.hud, "CENTER", x, y)
        frame:SetFrameLevel(sides.player.id:GetFrameLevel() + 10)
        local glow = frame:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("CENTER")
        glow:SetSize(size * 2.35, size * 2.35)
        glow:SetTexture(MEDIA .. "ArcGlow")
        glow:SetBlendMode("ADD")
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        local mask = frame:CreateMaskTexture()
        mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
        mask:SetPoint("CENTER", icon, "CENTER")
        mask:SetSize(size * 1.5, size * 1.5)
        icon:AddMaskTexture(mask)
        local border = frame:CreateTexture(nil, "OVERLAY")
        border:SetAtlas("UI-HUD-ActionBar-IconFrame")
        border:SetPoint("TOPLEFT", icon, "TOPLEFT")
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", size / 45, 0)
        frame:SetAlpha(0)
        local group = frame:CreateAnimationGroup()
        local function Anim(kind, order, duration, smoothing)
            local a = group:CreateAnimation(kind)
            a:SetOrder(order)
            a:SetDuration(duration)
            if smoothing then a:SetSmoothing(smoothing) end
            return a
        end
        local inAlpha = Anim("Alpha", 1, T.PULSE_IN, "OUT")
        inAlpha:SetFromAlpha(0)
        inAlpha:SetToAlpha(1)
        local inScale = Anim("Scale", 1, T.PULSE_IN, "OUT")
        inScale:SetScaleFrom(0.5, 0.5)
        inScale:SetScaleTo(1, 1)
        local hold = Anim("Alpha", 2, holdTime or T.PULSE_HOLD)
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        local outAlpha = Anim("Alpha", 3, T.PULSE_OUT, "IN")
        outAlpha:SetFromAlpha(1)
        outAlpha:SetToAlpha(0)
        local outScale = Anim("Scale", 3, T.PULSE_OUT, "IN")
        outScale:SetScaleFrom(1, 1)
        outScale:SetScaleTo(1.35, 1.35)
        pulse = { frame = frame, icon = icon, glow = glow, group = group }
        group:SetScript("OnFinished", function()
            playing = false
            C_Timer.After(T.PULSE_GAP, self.Next)
        end)
    end

    function self.Next()
        if playing then return end
        local entry = table.remove(queue, 1)
        if entry == nil then return end
        if not pulse then Build() end
        if not pcall(pulse.icon.SetTexture, pulse.icon, entry.texture) then return self.Next() end
        local c = entry.color or color
        pulse.glow:SetVertexColor(c[1], c[2], c[3])
        playing = true
        pulse.group:Stop()
        pulse.group:Play()
    end

    function self.Queue(texture, entryColor)
        queue[#queue + 1] = { texture = texture, color = entryColor }
        self.Next()
    end

    return self
end

-- The cooldown pulse: the icon big above your character, a gold glow.
do
    local pulse = A.NewIconPulse(0, T.PULSE_Y, T.PULSE_SIZE, T.READY_COLOR_CD)
    -- `color`: the glow's (default: the cooldowns' gold).
    function A.QueuePulse(texture, color) pulse.Queue(texture, color) end
end

-- A cooldown icon coming off cooldown: a gold ring swelling off it. Timed by
-- its cooldown swipe (shown at the start, done at the end); only cooldowns
-- of READY_MIN seconds or more (not the global cooldown).
function A.AddReadyFlash(item)
    local cd = item.Cooldown or (item.GetCooldownFrame and item:GetCooldownFrame())
    if not cd then return end
    local frame = CreateFrame("Frame", nil, item)
    frame:SetAllPoints()
    frame:SetFrameLevel(item:GetFrameLevel() + 10)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "ArcGlow")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(T.READY_COLOR_CD[1], T.READY_COLOR_CD[2], T.READY_COLOR_CD[3])
    frame:SetAlpha(0)
    local group = frame:CreateAnimationGroup()
    local grow = group:CreateAnimation("Scale")
    grow:SetScaleFrom(T.READY_FROM, T.READY_FROM)
    grow:SetScaleTo(T.READY_TO, T.READY_TO)
    grow:SetOrigin("CENTER", 0, 0)
    grow:SetDuration(T.READY_TIME)
    grow:SetSmoothing("OUT")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(T.READY_TIME)
    fade:SetSmoothing("IN")
    local startedAt
    cd:HookScript("OnShow", function() startedAt = GetTime() end)
    cd:HookScript("OnCooldownDone", function()
        if startedAt and GetTime() - startedAt >= T.READY_MIN then
            group:Stop()
            group:Play()
            local icon = item.Icon or (item.GetIconTexture and item:GetIconTexture())
            if icon and icon.GetTexture then
                local ok, texture = pcall(icon.GetTexture, icon)
                if ok and texture ~= nil and not (A.LockedOut and A.LockedOut(texture)) then
                    A.QueuePulse(texture)
                end
            end
        end
        startedAt = nil
    end)
end

function A.QueueArrange(layout)
    if queued[layout] then return end
    queued[layout] = true
    C_Timer.After(0, function()
        queued[layout] = nil
        ns.safecall(Arrange, layout)
    end)
end

-- The viewers' alpha: Blizzard's own (kept from its SetAlpha calls) times
-- their HUD side's.
local viewerBase, viewerShown = {}, {}
local settingViewerAlpha = false

local function ApplyViewerAlpha(viewer, sideAlpha)
    if viewerShown[viewer] == sideAlpha then return end
    viewerShown[viewer] = sideAlpha
    settingViewerAlpha = true
    viewer:SetAlpha((viewerBase[viewer] or 1) * sideAlpha)
    settingViewerAlpha = false
end

function A.UpdateViewerAlphas()
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    for _, layout in ipairs(CDM_LAYOUTS) do
        local viewer = _G[layout.viewer]
        local side = sides[layout.side]
        if viewer and side then ApplyViewerAlpha(viewer, editing and 1 or side.alpha) end
    end
end

local function HookCooldownManager()
    for _, layout in ipairs(CDM_LAYOUTS) do
        local viewer = _G[layout.viewer]
        if viewer then
            viewerBase[viewer] = viewer:GetAlpha()
            hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
                if settingViewerAlpha then return end
                viewerBase[self] = alpha
                viewerShown[self] = nil -- re-apply ours on the next update
            end)
        end
        if viewer and type(viewer.Layout) == "function" then
            hooksecurefunc(viewer, "Layout", function() A.QueueArrange(layout) end)
            A.QueueArrange(layout)
        end
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", function()
            for _, layout in ipairs(CDM_LAYOUTS) do A.QueueArrange(layout) end
        end)
    end
end

A.AddPart({
    Update = function()
        if M.db.cooldowns then A.UpdateViewerAlphas() end
    end,
    Enable = function()
        if M.db.cooldowns then HookCooldownManager() end
    end,
})
