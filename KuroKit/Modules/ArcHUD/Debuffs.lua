-- Arc HUD part: debuffs.
--   your target's   Blizzard's target frame debuffs (yours and the mob's
--                   own, the game's filter) in a column just outside the
--                   target arc, from below its level badge (as the Essential
--                   cooldowns on your side), slightly larger, the mob's buffs
--                   left out, while the arc shows, fading with it; back on
--                   the target frame as Blizzard has them when the frame is
--                   (pop out, Edit Mode)
--   on you          a new debuff on you pops its icon in big to the right of
--                   your character with a red glow, then fades (away from
--                   the cooldown pulses above you and the shield arc on the
--                   left); your own lockouts (Weakened Soul, Forbearance)
--                   don't count, but no other debuff is ever skipped for
--                   one (see Flush)
-- How: the target frame's aura icons are locked against addons on this
-- client (forbidden objects), their container isn't: it moves as a whole
-- with its own layout, which takes settings (the container's public
-- setters): a vertical flow makes it a column. Blizzard re-anchors it on
-- every aura change (TargetFrame:AnchorAuraContainer) and re-configures it
-- on target changes (ConfigureAuraContainer): post-hooks record Blizzard's
-- anchor and settings (to put them back) and re-apply ours. (Aura data
-- itself can't be read in combat, not even passed on: the HUD can't draw
-- its own icons.)
-- Your debuffs: Blizzard's DebuffFrame (top right) fills its buttons in
-- aura order, the newest last; when more buttons show than before (a
-- post-hook on its UpdateAuraButtons), the last one's icon pulses. Its
-- texture may be secret in combat: only handed to SetTexture.
-- Cost: a few alpha checks per frame; the rest per aura change.
local _, ns = ...
local A = ns.ArcHUD
local T, sides, Secret, Editing = A.T, A.sides, A.Secret, A.Editing

local COLUMN_X = 3              -- the debuff column's left edge, right of the target arc's frame
local COLUMN_START = -0.33      -- its top: this share of the arc's half angle (negative: above the middle)
local COLUMN_H = 118            -- its height (UI units): then a second column
local SMALL_SIZE, LARGE_SIZE = 20, 24 -- icon sizes (others' / yours; Blizzard's 17 / 21)
local ALERT_X, ALERT_Y = 92, 10 -- the debuff alert, from the HUD's centre (your character)
local ALERT_SIZE, ALERT_HOLD = 40, 0.9
local ALERT_COLOR = { 1, 0.18, 0.12 }
local SETTLE = 2                -- seconds after a loading screen without alerts (all debuffs re-listed)
local FLUSH_DELAY = 0.3         -- seconds a new debuff waits for its alert (see Flush)

---------------------------------------------------------------------------
-- Your target's auras beside its arc
---------------------------------------------------------------------------
local container        -- Blizzard's target aura container
local blizzPoint       -- its anchor as Blizzard last set it { point, relativeTo, relativePoint, x, y }
local blizzLayout      -- its layout settings as Blizzard last set them (see LAYOUT)
local onArc = false
local shownAlpha

-- The container's layout settings ours change: { getter, setter, ours }.
-- On the arc: a column (vertical flow), as tall as the rail, larger icons,
-- debuffs only (the mob's buffs: max 0).
local LAYOUT = {
    { "GetFlowLayoutAxis", "SetFlowLayoutAxis", AnchorUtil and AnchorUtil.FlowLayoutAxis and AnchorUtil.FlowLayoutAxis.Vertical },
    { "GetFlowLayoutMaximumLineSize", "SetFlowLayoutMaximumLineSize", COLUMN_H },
    { "GetConstrainedFlowLayoutLineSize", "SetConstrainedFlowLayoutLineSize", COLUMN_H },
    { "GetNumConstrainedFlowLayoutLines", "SetNumConstrainedFlowLayoutLines", 0 },
    { "GetMaxBuffs", "SetMaxBuffs", 0 },
    { "GetSmallAuraSize", "SetSmallAuraSize", SMALL_SIZE },
    { "GetLargeAuraSize", "SetLargeAuraSize", LARGE_SIZE },
}

local function ReadLayout()
    local values = {}
    for i, entry in ipairs(LAYOUT) do values[i] = container[entry[1]](container) end
    return values
end

-- `values` nil: ours.
local function ApplyLayout(values)
    for i, entry in ipairs(LAYOUT) do
        local value
        if values then value = values[i] else value = entry[3] end
        if value ~= nil and container[entry[1]](container) ~= value then container[entry[2]](container, value) end
    end
end

-- The column's top left: just outside the arc's outer edge, from the rail's
-- start (below the level badge), as the Essential cooldowns on your side.
local function PlaceOnArc()
    local angle = A.ARC_HALF * COLUMN_START
    local y = (A.ARC_CY + A.ARC_R * math.sin(angle)) * A.SCALE
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", sides.target.frame, "TOPRIGHT", COLUMN_X, -y)
    ApplyLayout(nil)
end

local function PutBack()
    if blizzPoint then
        container:ClearAllPoints()
        container:SetPoint(blizzPoint[1], blizzPoint[2], blizzPoint[3], blizzPoint[4], blizzPoint[5])
    end
    if blizzLayout then ApplyLayout(blizzLayout) end
end

-- After Blizzard anchored it: remember that, keep ours.
local function OnBlizzardAnchor()
    local point, relativeTo, relativePoint, x, y = container:GetPoint(1)
    if point and not onArc then blizzPoint = { point, relativeTo, relativePoint, x, y } end
    if onArc then PlaceOnArc() end
end

-- After Blizzard configured it (its target or that one's target changed):
-- the values it set are its own now; ours again on the arc.
local function OnBlizzardConfigure()
    local values = ReadLayout()
    if not onArc or not blizzLayout then
        blizzLayout = values
    else
        for i, entry in ipairs(LAYOUT) do
            if values[i] ~= entry[3] then blizzLayout[i] = values[i] end
        end
    end
    if onArc then ApplyLayout(nil) end
end

local function UpdateTargetAuras()
    local s = sides.target
    local want = s.alpha > 0 and not Editing()
    if want ~= onArc then
        if want then
            blizzLayout = ReadLayout()
            local point, relativeTo, relativePoint, x, y = container:GetPoint(1)
            if point then blizzPoint = { point, relativeTo, relativePoint, x, y } end
            onArc = true
            PlaceOnArc()
        else
            onArc = false
            PutBack()
        end
        shownAlpha = nil
    end
    local alpha = onArc and s.alpha or 1
    if alpha ~= shownAlpha then
        shownAlpha = alpha
        container:SetAlpha(alpha)
    end
end

---------------------------------------------------------------------------
-- New debuffs on you
---------------------------------------------------------------------------
local alert = A.NewIconPulse(ALERT_X, ALERT_Y, ALERT_SIZE, ALERT_COLOR, ALERT_HOLD)
local lastCount
local quietUntil = 0
local pending = 0          -- new debuffs waiting for their alert
local flushQueued = false
local usedLockout          -- the lockout start (your clock) a skipped debuff was put down to
local newest = {}          -- (reused) the newest shown buttons

-- Blizzard's shown debuff buttons, in order: how many (the list in `newest`).
local function ShownDebuffs()
    wipe(newest)
    for _, button in ipairs(DebuffFrame.auraFrames or {}) do
        if not button.isAuraAnchor and button.hasValidInfo and button:IsShown() then
            newest[#newest + 1] = button
        end
    end
    return #newest
end

local function IconOf(button)
    if not button.Icon then return nil end
    local ok, texture = pcall(button.Icon.GetTexture, button.Icon)
    if ok then return texture end
end

-- The new debuffs (the last `pending` buttons): each pulses, except your own
-- lockout. Readable icons: compared with the lockout's. Secret ones (in
-- combat): the one new debuff landing with a lockout your clock just
-- started is put down to it; with more new ones than that, all of them
-- pulse (one is the lockout, which can't be told: never miss a real one).
local function Flush()
    flushQueued = false
    local count = ShownDebuffs()
    local n = math.min(pending, count)
    pending = 0
    if n <= 0 then return end
    local candidates, secret = 0, 0
    for i = count - n + 1, count do
        local texture = IconOf(newest[i])
        if texture ~= nil and not A.IsLockoutIcon(texture) then
            candidates = candidates + 1
            if Secret(texture) then secret = secret + 1 end
        end
    end
    local started = A.LockoutStartedAt and A.LockoutStartedAt()
    local skipOne = secret == 1 and candidates == 1 and started and started ~= usedLockout
        and GetTime() - started < T.LOCKOUT_GRACE
    if skipOne then
        usedLockout = started
        return
    end
    for i = count - n + 1, count do
        local texture = IconOf(newest[i])
        if texture ~= nil and not A.IsLockoutIcon(texture) then alert.Queue(texture) end
    end
end

local function OnDebuffs()
    if Editing() or GetTime() < quietUntil then
        lastCount, pending = nil, 0 -- (example icons, re-listing: a fresh start)
        return
    end
    local count = ShownDebuffs()
    if lastCount and count > lastCount then
        pending = pending + count - lastCount
        -- (a moment for your clock to start a lockout landing with it)
        if not flushQueued then
            flushQueued = true
            C_Timer.After(FLUSH_DELAY, function() ns.safecall(Flush) end)
        end
    end
    lastCount = count
end

A.AddPart({
    Build = function()
        container = TargetFrame and TargetFrame.GetAuraContainer and TargetFrame:GetAuraContainer()
        if container and not pcall(function() blizzLayout = ReadLayout() OnBlizzardAnchor() end) then
            container = nil -- (locked after all: left alone)
        end
    end,
    Update = function()
        if container then UpdateTargetAuras() end
    end,
    Enable = function()
        if container and TargetFrame.AnchorAuraContainer then
            hooksecurefunc(TargetFrame, "AnchorAuraContainer", function() ns.safecall(OnBlizzardAnchor) end)
        end
        if container and TargetFrame.ConfigureAuraContainer then
            hooksecurefunc(TargetFrame, "ConfigureAuraContainer", function() ns.safecall(OnBlizzardConfigure) end)
        end
        if DebuffFrame and DebuffFrame.UpdateAuraButtons then
            hooksecurefunc(DebuffFrame, "UpdateAuraButtons", function() ns.safecall(OnDebuffs) end)
            quietUntil = GetTime() + SETTLE
            ns:On("PLAYER_ENTERING_WORLD", function() quietUntil = GetTime() + SETTLE end)
        end
    end,
})
