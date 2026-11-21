-- HoverReveal: hide a set of UI regions until the mouse is over their spot, then
-- slide/fade them in from a screen edge; slide/fade out again as soon as the
-- mouse leaves.
-- Used by MenuTray (micro menu & bags), StatusBars (XP/reputation), ...
--
--   local group = ns.NewHoverReveal({
--       targets = function(list) ... end, -- add the regions (frames or textures) to fade/slide right now
--       zone    = function(list) ... end, -- optional: regions whose area is the hover spot (default: targets)
--       fade    = true,                   -- optional: fade only (default: slide to the nearest edge)
--       onShow  = function() end,         -- optional: just before revealing
--       onPoll  = function() end,         -- optional: every check while visible (not while animating)
--   })
--   group:Start()      -- create the sensor, start hidden (or shown in Edit Mode)
--   group:Refresh()    -- something moved/resized: recompute the hover spot (while hidden)
--   group:Reapply()    -- new regions appeared: hide them too if the group is hidden
--   group:Release(r)   -- stop animating r and show it normally (e.g. Blizzard borrowed it)
--
-- Slide direction: a horizontal spot slides to the nearer of top/bottom,
-- a vertical one to the nearer of left/right. The hover spot is the targets' area,
-- grown to touch screen edges they're close to.
--
-- Performance: while hidden nothing runs. An invisible sensor (mouse motion only,
-- clicks pass through) covers the spot; entering it reveals the group and starts a
-- 20 Hz check that runs only while visible. Per-check code allocates nothing.
-- Edit Mode open: every group is shown.
local _, ns = ...

local DURATION = 0.18      -- seconds per slide/fade
local EDGE_SNAP = 64       -- a spot this close to a screen edge counts as touching it
local ZONE_PAD = 6         -- extra hover margin around the regions
local POLL = 0.05          -- check interval while visible

local editMode = false
local groups = {}

local function EffectiveScale(region)
    if region.GetEffectiveScale then return region:GetEffectiveScale() end
    return region:GetParent():GetEffectiveScale()
end

-- Rect in UIParent units.
local function Rect(region)
    local l, b, w, h = region:GetRect()
    if not l then return end
    local s = EffectiveScale(region) / UIParent:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

---------------------------------------------------------------------------
-- Animations (one set per region)
---------------------------------------------------------------------------
local function MakeAnims(region)
    local a = {}
    -- Show: jump to the hidden offset (invisible), then slide back + fade in.
    a.show = region:CreateAnimationGroup()
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
    a.hide = region:CreateAnimationGroup()
    a.slideOut = a.hide:CreateAnimation("Translation")
    a.slideOut:SetDuration(DURATION); a.slideOut:SetSmoothing("IN")
    local fadeOut = a.hide:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(DURATION)
    a.hide:SetToFinalAlpha(true)
    a.hide:SetScript("OnFinished", function() region:SetAlpha(0) end)
    return a
end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
local Group = {}
Group.__index = Group

function ns.NewHoverReveal(opts)
    local g = setmetatable({
        opts = opts,
        anims = {},
        list = {},          -- reused scratch list
        visible = true,
        zone = { valid = false, l = 0, b = 0, r = 0, t = 0, dx = 0, dy = 0 },
        elapsed = 0,
    }, Group)
    groups[#groups + 1] = g
    return g
end

function Group:Anims(region)
    local a = self.anims[region]
    if not a then
        a = MakeAnims(region)
        self.anims[region] = a
    end
    return a
end

function Group:AnyAnimating()
    for _, a in pairs(self.anims) do
        if a.show:IsPlaying() or a.hide:IsPlaying() then return true end
    end
    return false
end

function Group:Targets()
    local list = self.list
    wipe(list)
    self.opts.targets(list)
    return list
end

-- Union of the zone regions, grown to touch nearby screen edges, plus the slide
-- offset. Only recomputed while nothing is animating.
function Group:UpdateZone()
    if self:AnyAnimating() then return end
    local list = self.list
    wipe(list)
    if self.opts.zone then self.opts.zone(list) else self.opts.targets(list) end
    local l, b, r, t
    for i = 1, #list do
        local rl, rb, rr, rt = Rect(list[i])
        if rl then
            l = l and math.min(l, rl) or rl
            b = b and math.min(b, rb) or rb
            r = r and math.max(r, rr) or rr
            t = t and math.max(t, rt) or rt
        end
    end
    local zone = self.zone
    if not l then zone.valid = false; return end

    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local dLeft, dRight, dBottom, dTop = l, W - r, b, H - t
    local edge
    if (r - l) >= (t - b) then
        edge = dBottom <= dTop and "down" or "up"
    else
        edge = dLeft <= dRight and "left" or "right"
    end

    -- A side near a screen edge reaches *past* it (unbounded): at the outermost
    -- pixel the cursor position can come out a hair beyond the UI's width/height.
    zone.l = dLeft <= EDGE_SNAP and -math.huge or (l - ZONE_PAD)
    zone.r = dRight <= EDGE_SNAP and math.huge or (r + ZONE_PAD)
    zone.b = dBottom <= EDGE_SNAP and -math.huge or (b - ZONE_PAD)
    zone.t = dTop <= EDGE_SNAP and math.huge or (t + ZONE_PAD)

    -- Hidden offset: far enough to slide fully past that edge.
    zone.dx, zone.dy = 0, 0
    if edge == "left" then zone.dx = -(r + 4)
    elseif edge == "right" then zone.dx = (W - l) + 4
    elseif edge == "down" then zone.dy = -(t + 4)
    else zone.dy = (H - b) + 4 end
    zone.valid = true
end

function Group:CursorInZone()
    local zone = self.zone
    if not zone.valid then return false end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    x, y = x / s, y / s
    return x >= zone.l and x <= zone.r and y >= zone.b and y <= zone.t
end

function Group:PlaceSensor()
    local sensor, zone = self.sensor, self.zone
    if self.visible or not zone.valid then sensor:Hide(); return end
    -- Unbounded sides end a little past the screen edge, so the outermost pixel
    -- is always inside the sensor.
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local l = math.max(zone.l, -10)
    local b = math.max(zone.b, -10)
    local r = math.min(zone.r, W + 10)
    local t = math.min(zone.t, H + 10)
    sensor:ClearAllPoints()
    sensor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    sensor:SetSize(math.max(1, r - l), math.max(1, t - b))
    sensor:Show()
end

function Group:SetOffsets(region, a)
    local dx, dy = 0, 0
    if not self.opts.fade and self.zone.valid then
        -- Translation offsets are in the region's own (scaled) units.
        local k = UIParent:GetEffectiveScale() / EffectiveScale(region)
        dx, dy = self.zone.dx * k, self.zone.dy * k
    end
    a.jump:SetOffset(dx, dy)
    a.slideIn:SetOffset(-dx, -dy)
    a.slideOut:SetOffset(dx, dy)
end

function Group:ShowRegion(region, animate)
    local a = self:Anims(region)
    if a.hide:IsPlaying() then
        a.hide:Stop() -- reverse mid-hide: just snap back
        region:SetAlpha(1)
        return
    end
    if region:GetAlpha() >= 1 or a.show:IsPlaying() then return end
    region:SetAlpha(1)
    if animate then
        self:SetOffsets(region, a)
        a.show:Play()
    end
end

function Group:HideRegion(region, animate)
    local a = self:Anims(region)
    if a.show:IsPlaying() then a.show:Stop() end
    if region:GetAlpha() <= 0 or a.hide:IsPlaying() then return end
    if animate then
        self:SetOffsets(region, a)
        a.hide:Play()
    else
        region:SetAlpha(0)
    end
end

function Group:SetVisible(show, animate)
    if not self.sensor then return end
    if show then
        self.visible = true
        self.sensor:Hide()
        if self.opts.onShow then ns.safecall(self.opts.onShow) end
        self:UpdateZone()
        local list = self:Targets()
        for i = 1, #list do self:ShowRegion(list[i], animate) end
        self.poller:Show() -- start the visible-only check
    else
        self:UpdateZone() -- regions are at rest here; this is the spot the sensor covers
        self.visible = false
        local list = self:Targets()
        for i = 1, #list do self:HideRegion(list[i], animate) end
        self.poller:Hide()
        self:PlaceSensor()
    end
end

-- Runs only while visible.
function Group:Poll(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < POLL then return end
    self.elapsed = 0

    if not self:AnyAnimating() then
        if self.opts.onPoll then self.opts.onPoll() end
        self:UpdateZone()
    end
    if not (editMode or self:CursorInZone()) then
        self:SetVisible(false, true)
    end
end

function Group:Refresh()
    if not self.sensor or self.visible then return end
    self:UpdateZone()
    self:PlaceSensor()
end

function Group:Reapply()
    if not self.sensor or self.visible then return end
    local list = self:Targets()
    for i = 1, #list do
        local region = list[i]
        local a = self.anims[region]
        if not (a and a.hide:IsPlaying()) and region:GetAlpha() > 0 then region:SetAlpha(0) end
    end
end

function Group:Release(region)
    local a = self.anims[region]
    if a then a.show:Stop(); a.hide:Stop() end
    region:SetAlpha(1)
end

local editModeHooked = false
local function HookEditMode()
    if editModeHooked then return end
    editModeHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        editMode = true
        for _, g in ipairs(groups) do g:SetVisible(true, false) end
    end, groups)
    EventRegistry:RegisterCallback("EditMode.Exit", function() editMode = false end, groups)
    editMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false
end

function Group:Start()
    HookEditMode()

    local sensor = CreateFrame("Frame", nil, UIParent)
    sensor:SetFrameStrata("HIGH")
    sensor:SetMouseMotionEnabled(true)
    sensor:SetMouseClickEnabled(false)
    sensor:SetScript("OnEnter", function() self:SetVisible(true, true) end)
    sensor:Hide()
    self.sensor = sensor

    local poller = CreateFrame("Frame")
    poller:SetScript("OnUpdate", function(f, dt)
        if not ns.safecall(self.Poll, self, dt) then f:Hide() end -- report once, don't repeat per frame
    end)
    poller:Hide()
    self.poller = poller

    if editMode then self:SetVisible(true, false) else self:SetVisible(false, false) end

    -- Blizzard (and other addons) finish setting up the UI after PLAYER_LOGIN:
    -- frames get shown/rebuilt on PLAYER_ENTERING_WORLD, sometimes a frame later.
    -- Re-apply the hidden state then, so nothing pops up until the first hover.
    ns:On("PLAYER_ENTERING_WORLD", function()
        RunNextFrame(function()
            self:Reapply()
            self:Refresh()
        end)
    end)
end
