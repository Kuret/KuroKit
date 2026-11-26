-- Arc HUD part: your cast arc below your character and your target's cast
-- bar beside its arc.
--   your cast      fills left to right (channels drain), the spell icon by
--                  its left tip, the spell name under it, the time left by
--                  its right tip, and a red latency zone at its end (at its
--                  start for channels) to time the next cast. It sits on
--                  Blizzard's player cast bar (faded out, but Edit Mode
--                  still moves it: it shows there, with the cast arc, while
--                  Edit Mode is open).
--   target's cast  the HUD's own bar beside the target arc (its own fill,
--                  icon, spell name, time left, a lock for casts you can't
--                  interrupt); Blizzard's steps back with its frame.
-- Interrupted / failed casts show in red with the reason; your target's
-- interrupted casts also burst a ring round its portrait (Trims.lua).
-- Channels with ticks (Penance, Mind Flay, Arcane Missiles, the Warlock's
-- drains...) show a mark across the arc between ticks: CHANNEL_TICKS, each
-- spell's tick interval (by name: every rank), the marks spread over the
-- channel's length (so 3, 4 or 5 Arcane Missiles by rank).
-- How: the arc runs off the cast's duration object (SetTimerDuration).
local _, ns = ...
local A = ns.ArcHUD
local MEDIA, SCALE, SIDE_H = A.MEDIA, A.SCALE, A.SIDE_H
local BACK_ALPHA, FILL_ALPHA, NAME_FONT_SIZE, TEXT_GAP = A.BACK_ALPHA, A.FILL_ALPHA, A.NAME_FONT_SIZE, A.TEXT_GAP
local sides, Secret, NewBar, NewText, PortraitPoint = A.sides, A.Secret, A.NewBar, A.NewText, A.PortraitPoint
local Fade = A.Fade

local CAST_W, CAST_H = 512 * SCALE, 128 * SCALE
-- The cast fill's columns (texture px; tools/make_arcs.py: the same numbers):
-- the bars sit over just these, so the fill shows from the cast's start.
local CAST_FILL_LEFT = math.floor(256 - 600 * math.sin(math.rad(17)))
local CAST_FILL_RIGHT = math.ceil(256 + 600 * math.sin(math.rad(17)))
-- The target cast bar beside the right arc (heights from the target's
-- portrait centre, x from the arc's outermost point).
local TCAST_W, TCAST_H, TCAST_ICON = 170, 12, 20
local TCAST_Y = -88                      -- the cast bar, below the portrait's centre
local TCAST_X = 34                       -- its icon, right of the arc's outermost point (clear of the debuff column)
local INTERRUPT_HOLD = 0.8               -- seconds an interrupted / failed cast stays up
local INTERRUPT_GRACE = 0.3              -- a cast stopped this close to its end finished (not interrupted)
local INTERRUPT_COLOR = { 0.9, 0.1, 0.05 }
local TCAST_INTERRUPTED = "ui-castingbar-interrupted"
local TCAST_FILL = "ui-castingbar-filling-standard"
local TCAST_CHANNEL_FILL = "ui-castingbar-filling-channel"
local TCAST_BACK = "ui-castingbar-background"
local TCAST_LOCK = "ui-castingbar-shield"
local CAST_Y = 0             -- the cast arc's centre, from the player cast bar's (Edit Mode)
local CAST_TIP_X, CAST_TIP_Y = 0.86, -0.55 -- the time left: by the arc's right tip (share of its frame)
local CAST_ICON_X = 0.14     -- the spell icon: by the arc's left tip
local CAST_ICON_SIZE = 24
local TIMER_INTERVAL = 0.05  -- seconds between time-left updates
local LATENCY_COLOR = { 1, 0.15, 0.1, 0.6 }
local CAST_COLOR = { 1, 0.7, 0 }
-- Channel ticks: rank 1's spell ID -> seconds between ticks; the ticks split
-- the channel into round(length / interval) equal parts, a mark between
-- each. (Penance: a bolt at the cast and every second after, 2 s: 2 parts.)
local CHANNEL_TICKS = {
    [15407] = 1,    -- Mind Flay
    [402174] = 1,   -- Penance (WoW Forever's)
    [5143] = 1,     -- Arcane Missiles
    [10] = 1,       -- Blizzard
    [689] = 1,      -- Drain Life
    [5138] = 1,     -- Drain Mana
    [1120] = 3,     -- Drain Soul
    [755] = 1,      -- Health Funnel
    [1949] = 1,     -- Hellfire
    [5740] = 2,     -- Rain of Fire
    [740] = 2,      -- Tranquility
    [16914] = 1,    -- Hurricane
    [1510] = 1,     -- Volley
}
local TICK_RADIUS = 590              -- texture px: the cast ring's middle (tools/make_arcs.py CAST)
local TICK_CX, TICK_CY = 256, -484   -- its circle's centre (CAST_CX, CAST_CY)
local TICK_W, TICK_H = 2, 14         -- a mark (UI units), across the ring
local TICK_COLOR = { 1, 1, 1, 0.75 }
local CHANNEL_COLOR = { 0.3, 0.8, 0.3 }

local cast              -- { frame, bar, latency, name, timer, alpha, wanted, channel }

local function BuildCast()
    local frame = CreateFrame("Frame", nil, A.hud)
    frame:SetSize(CAST_W, CAST_H)
    if PlayerCastingBarFrame then
        frame:SetPoint("CENTER", PlayerCastingBarFrame, "CENTER", 0, CAST_Y)
    else
        frame:SetPoint("TOP", A.hud, "CENTER", 0, -128)
    end
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetAlpha(BACK_ALPHA)
    back:SetTexture(MEDIA .. "ArcCastBack")
    cast = { frame = frame, alpha = 0, wanted = 0 }
    local cols = CreateFrame("Frame", nil, frame)
    cols:SetPoint("TOPLEFT", frame, "TOPLEFT", CAST_FILL_LEFT * SCALE, 0)
    cols:SetSize((CAST_FILL_RIGHT - CAST_FILL_LEFT) * SCALE, CAST_H)
    cast.bar = NewBar(cols, MEDIA .. "ArcCastFill", "HORIZONTAL")
    local flashFrame = CreateFrame("Frame", nil, frame)
    flashFrame:SetAllPoints()
    flashFrame:SetFrameLevel(cast.bar:GetFrameLevel() + 2)
    cast.flash = flashFrame:CreateTexture(nil, "ARTWORK")
    cast.flash:SetAllPoints()
    cast.flash:SetTexture(MEDIA .. "ArcCast")
    cast.flash:SetVertexColor(INTERRUPT_COLOR[1], INTERRUPT_COLOR[2], INTERRUPT_COLOR[3])
    cast.flash:Hide()
    cast.bar:SetAlpha(FILL_ALPHA)
    -- Latency: a slice of the same arc at the cast's end (its start for
    -- channels), translucent red. Its own texture, cropped by hand: a
    -- StatusBar's reverse fill keeps the texture's left end (the arc's left
    -- tip, sloping the wrong way, drawn at the right).
    local latencyLayer = CreateFrame("Frame", nil, cols)
    latencyLayer:SetAllPoints()
    latencyLayer:SetFrameLevel(cast.bar:GetFrameLevel() + 1)
    cast.latency = latencyLayer:CreateTexture(nil, "ARTWORK")
    cast.latency:SetTexture(MEDIA .. "ArcCastFill")
    cast.latency:SetVertexColor(LATENCY_COLOR[1], LATENCY_COLOR[2], LATENCY_COLOR[3], LATENCY_COLOR[4])
    cast.latency:Hide()
    local texts = CreateFrame("Frame", nil, frame)
    texts:SetAllPoints()
    texts:SetFrameLevel(latencyLayer:GetFrameLevel() + 1)
    cast.tickLayer, cast.ticks = texts, {}
    cast.name = NewText(texts, NAME_FONT_SIZE)
    cast.name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    cast.name:SetPoint("TOP", frame, "BOTTOM", 0, -TEXT_GAP)
    -- The spell icon by the left tip, in the action bar's icon look.
    local icon = texts:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CAST_ICON_SIZE, CAST_ICON_SIZE)
    icon:SetPoint("RIGHT", frame, "TOPLEFT", CAST_W * CAST_ICON_X, CAST_H * CAST_TIP_Y)
    local mask = texts:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetPoint("CENTER", icon, "CENTER")
    mask:SetSize(CAST_ICON_SIZE * 1.5, CAST_ICON_SIZE * 1.5) -- as on Blizzard's small action buttons
    icon:AddMaskTexture(mask)
    local iconFrame = texts:CreateTexture(nil, "OVERLAY")
    iconFrame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    iconFrame:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", CAST_ICON_SIZE / 45, 0)
    cast.icon = icon
    cast.timer = NewText(texts, NAME_FONT_SIZE)
    cast.timer:SetTextColor(1, 1, 1)
    cast.timer:SetPoint("LEFT", frame, "TOPLEFT", CAST_W * CAST_TIP_X, CAST_H * CAST_TIP_Y)
    frame:SetAlpha(0)
end

-- Blizzard's player cast bar out of sight: alpha 0 (kept there, except in
-- Edit Mode, to move it), and its fade animations (interrupted / failed
-- casts) fade from 0 to 0, since an animation sets the alpha without
-- SetAlpha.
local editingCastBar = false
local function HideCastBar(bar)
    if not bar then return end
    bar:SetAlpha(0)
    hooksecurefunc(bar, "SetAlpha", function(self, alpha)
        if not editingCastBar and alpha ~= 0 then self:SetAlpha(0) end
    end)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function()
            editingCastBar = true
            bar:SetAlpha(1)
            -- (and the cast arc on it)
            cast.name:SetText(HUD_EDIT_MODE_CAST_BAR_LABEL or "Cast Bar")
            cast.wanted = 1
        end)
        EditModeManagerFrame:HookScript("OnHide", function()
            editingCastBar = false
            bar:SetAlpha(0)
            if not cast.casting and not cast.holdUntil then cast.wanted = 0 end
        end)
    end
    for _, group in ipairs({ bar:GetAnimationGroups() }) do
        for _, anim in ipairs({ group:GetAnimations() }) do
            if anim:GetObjectType() == "Alpha" then
                anim:SetFromAlpha(0)
                anim:SetToAlpha(0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Target cast bar (ours, on the arc; Blizzard's steps back with its frame)
---------------------------------------------------------------------------
local tcast  -- { bar, back, icon, name, timer, lock, casting, channel }

-- An interrupted / failed cast: the bar full in red with the reason for
-- INTERRUPT_HOLD, then the fade. Only for a cast that was showing.
-- Whether an interrupted / failed event (its cast GUID and spell) is about
-- the cast shown. Pressing another spell mid-cast or mid-channel reports
-- that attempt as failed (or interrupted) too: Blizzard's own cast bar
-- ignores those, and so does this. GUIDs first, then spell IDs (either may
-- be secret or empty: then the next); neither readable: only while it runs.
local function SameCast(item, guid, spellID)
    local function Usable(a, b) return a ~= nil and b ~= nil and a ~= "" and b ~= "" and not Secret(a) and not Secret(b) end
    if Usable(guid, item.guid) then return guid == item.guid end
    if Usable(spellID, item.spellID) then return spellID == item.spellID end
    return item.casting
end

-- The cast's end time (seconds; nil if unreadable), from its info's end in ms.
local function CastEnd(endMS)
    if type(endMS) ~= "number" or Secret(endMS) then return nil end
    return endMS / 1000
end

local function ShowInterrupted(item, reason, guid, spellID)
    if not (item.casting or item.alpha > 0) then return end
    if not SameCast(item, guid, spellID) then return end
    -- Stopped at (about) its own end: it finished, whatever comes after.
    if not item.casting and item.endsAt and item.stoppedAt and item.stoppedAt >= item.endsAt - INTERRUPT_GRACE then
        return
    end
    item.casting = false
    item.flash:Show()
    item.name:SetText(reason)
    item.timer:SetText("")
    if item.latency then item.latency:Hide() end
    item.wanted = 1
    item.holdUntil = GetTime() + INTERRUPT_HOLD
    if item == tcast and reason == (INTERRUPTED or "Interrupted") and A.KickBurst then A.KickBurst() end
end

local function ClearInterrupted(item)
    item.flash:Hide()
    item.holdUntil = nil
end


local function AtlasOr(texture, atlas)
    if C_Texture.GetAtlasInfo(atlas) then texture:SetAtlas(atlas) return true end
end

local function BuildTargetCast()
    local bar = CreateFrame("StatusBar", nil, sides.target.frame)
    bar:SetSize(TCAST_W, TCAST_H)
    local _, py = PortraitPoint(false)
    local portraitY = SIDE_H / 2 - py -- the portrait's centre, from the arc frame's middle
    bar:SetPoint("LEFT", sides.target.frame, "RIGHT", TCAST_X + TCAST_ICON + 4, portraitY + TCAST_Y)
    bar:SetMinMaxValues(0, 1)
    if C_Texture.GetAtlasInfo(TCAST_FILL) then
        bar:SetStatusBarTexture(TCAST_FILL)
    else
        bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
        bar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    end
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    if not AtlasOr(back, TCAST_BACK) then back:SetColorTexture(0, 0, 0, 0.7) end
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TCAST_ICON, TCAST_ICON)
    icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    local mask = bar:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetPoint("CENTER", icon, "CENTER")
    mask:SetSize(TCAST_ICON * 1.5, TCAST_ICON * 1.5)
    icon:AddMaskTexture(mask)
    local iconFrame = bar:CreateTexture(nil, "OVERLAY")
    iconFrame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    iconFrame:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", TCAST_ICON / 45, 0)
    local lock = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    lock:SetSize(TCAST_H + 8, TCAST_H + 8)
    lock:SetPoint("CENTER", bar, "LEFT", 0, 0)
    if not AtlasOr(lock, TCAST_LOCK) then lock:SetTexture(nil) end
    lock:SetAlpha(0)
    local name = NewText(bar, NAME_FONT_SIZE)
    name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    name:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -TEXT_GAP)
    local timer = NewText(bar, NAME_FONT_SIZE)
    timer:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -TEXT_GAP)
    local flash = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    flash:SetAllPoints(bar)
    if not AtlasOr(flash, TCAST_INTERRUPTED) then
        flash:SetColorTexture(INTERRUPT_COLOR[1], INTERRUPT_COLOR[2], INTERRUPT_COLOR[3], 1)
    end
    flash:Hide()
    bar:SetAlpha(0)
    tcast = { bar = bar, icon = icon, name = name, timer = timer, lock = lock, flash = flash, alpha = 0, wanted = 0,
        frame = bar }
end

local function TargetCastDuration()
    return (tcast.channel and UnitChannelDuration or UnitCastingDuration)("target")
end

local function StartTargetCast(channel, guid, spellID)
    if not UnitExists("target") then tcast.wanted = 0 return end
    local info = { (channel and UnitChannelInfo or UnitCastingInfo)("target") }
    if type(info[1]) == "nil" then tcast.wanted = 0 tcast.casting = false return end
    ClearInterrupted(tcast)
    tcast.channel = channel
    tcast.guid, tcast.spellID, tcast.endsAt, tcast.stoppedAt = guid, spellID, CastEnd(info[5]), nil
    local duration = TargetCastDuration()
    if not duration then tcast.wanted = 0 return end
    local direction = Enum.StatusBarTimerDirection
    tcast.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
        direction and (channel and direction.RemainingTime or direction.ElapsedTime))
    local fill = channel and TCAST_CHANNEL_FILL or TCAST_FILL
    if C_Texture.GetAtlasInfo(fill) then tcast.bar:GetStatusBarTexture():SetAtlas(fill) end
    tcast.name:SetText(info[1])
    pcall(tcast.icon.SetTexture, tcast.icon, info[3])
    -- Not interruptible (may be secret): the lock through SetAlphaFromBoolean.
    local locked = info[channel and 7 or 8]
    if type(locked) == "nil" then
        tcast.lock:SetAlpha(0)
    elseif not pcall(tcast.lock.SetAlphaFromBoolean, tcast.lock, locked, 1, 0) then
        tcast.lock:SetAlpha(0)
    end
    tcast.casting = true
    tcast.wanted = 1
end

local function StopTargetCast()
    tcast.casting = false
    tcast.stoppedAt = GetTime()
    if not tcast.holdUntil then tcast.wanted = 0 end
end

-- A cast already running when you pick the target.
local function CheckTargetCast()
    -- (These return nothing at all without a cast: into a local first.)
    local casting = UnitCastingInfo("target")
    local channeling = UnitChannelInfo("target")
    if type(casting) ~= "nil" then
        StartTargetCast(false)
    elseif type(channeling) ~= "nil" then
        StartTargetCast(true)
    else
        StopTargetCast()
    end
end

local sinceTargetTimer = 0
local function UpdateTargetCastTimer(elapsed)
    if not tcast.casting then return end
    sinceTargetTimer = sinceTargetTimer + elapsed
    if sinceTargetTimer < TIMER_INTERVAL then return end
    sinceTargetTimer = 0
    local duration = TargetCastDuration()
    if duration and duration.GetRemainingDuration then
        tcast.timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        tcast.timer:SetText("")
    end
end

---------------------------------------------------------------------------
-- Cast
---------------------------------------------------------------------------
local function CastDuration()
    return (cast.channel and UnitChannelDuration or UnitCastingDuration)("player")
end

-- The latency zone: latency / cast time of the arc, from the end the next
-- cast queues at (the end for casts, the start for channels).
local function PlaceLatency()
    local _, _, _, startMS, endMS = (cast.channel and UnitChannelInfo or UnitCastingInfo)("player")
    local _, _, _, latency = GetNetStats()
    if Secret(startMS) or Secret(endMS) or type(startMS) ~= "number" or type(endMS) ~= "number"
        or endMS <= startMS or not latency or latency <= 0 then
        cast.latency:Hide()
        return
    end
    -- That share of the fill's columns, from the right (or left) edge, the
    -- texture cropped to the same columns.
    local share = math.min(1, latency / (endMS - startMS))
    local t = cast.latency
    t:ClearAllPoints()
    if cast.channel then
        t:SetPoint("TOPLEFT")
        t:SetPoint("BOTTOMLEFT")
        t:SetTexCoord(0, share, 0, 1)
    else
        t:SetPoint("TOPRIGHT")
        t:SetPoint("BOTTOMRIGHT")
        t:SetTexCoord(1 - share, 1, 0, 1)
    end
    t:SetWidth((CAST_FILL_RIGHT - CAST_FILL_LEFT) * SCALE * share)
    t:Show()
end

-- Channel ticks: names -> interval (every rank), built when first needed.
local tickNames
local function TickInterval(spellID)
    if type(spellID) ~= "number" or Secret(spellID) then return nil end
    if not tickNames then
        tickNames = {}
        for id, interval in pairs(CHANNEL_TICKS) do
            local ok, name = pcall(C_Spell.GetSpellName, id)
            if ok and type(name) == "string" and not Secret(name) then tickNames[name] = interval end
        end
    end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and type(name) == "string" and not Secret(name) then return tickNames[name] end
end

-- A mark across the ring at `share` of the fill (left to right): the fill
-- runs over the cast columns linearly, so the mark sits at that column,
-- turned to the ring's radius there.
local function PlaceTick(mark, share)
    local x = CAST_FILL_LEFT + share * (CAST_FILL_RIGHT - CAST_FILL_LEFT)
    local angle = math.asin((x - TICK_CX) / TICK_RADIUS)
    local y = TICK_CY + TICK_RADIUS * math.cos(angle)
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", cast.frame, "TOPLEFT", x * SCALE, -y * SCALE)
    mark:SetRotation(angle)
    mark:Show()
end

local function UpdateTicks(channel, spellID)
    local marks = cast.ticks
    local count = 0
    local interval = channel and TickInterval(spellID)
    if interval then
        local _, _, _, startMS, endMS = UnitChannelInfo("player")
        if type(startMS) == "number" and type(endMS) == "number" and not Secret(startMS) and not Secret(endMS) then
            local parts = math.floor((endMS - startMS) / 1000 / interval + 0.5)
            for i = 1, parts - 1 do
                count = count + 1
                local mark = marks[count]
                if not mark then
                    mark = cast.tickLayer:CreateTexture(nil, "OVERLAY")
                    mark:SetColorTexture(TICK_COLOR[1], TICK_COLOR[2], TICK_COLOR[3], TICK_COLOR[4])
                    mark:SetSize(TICK_W, TICK_H)
                    marks[count] = mark
                end
                PlaceTick(mark, i / parts)
            end
        end
    end
    for i = count + 1, #marks do marks[i]:Hide() end
end

local function StartCast(channel, guid, spellID)
    ClearInterrupted(cast)
    cast.channel = channel
    local _, _, _, _, endMS = (channel and UnitChannelInfo or UnitCastingInfo)("player")
    cast.guid, cast.spellID, cast.endsAt, cast.stoppedAt = guid, spellID, CastEnd(endMS), nil
    local duration = CastDuration()
    if not duration then return end
    local direction = Enum.StatusBarTimerDirection
    cast.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
        direction and (channel and direction.RemainingTime or direction.ElapsedTime))
    local color = channel and CHANNEL_COLOR or CAST_COLOR
    cast.bar:SetStatusBarColor(color[1], color[2], color[3])
    local name, _, texture = (channel and UnitChannelInfo or UnitCastingInfo)("player")
    if type(name) == "nil" then cast.name:SetText("") else cast.name:SetText(name) end
    if not pcall(cast.icon.SetTexture, cast.icon, texture) then cast.icon:SetTexture(nil) end
    PlaceLatency()
    UpdateTicks(channel, spellID)
    cast.casting = true
    cast.wanted = 1
end

local function StopCast()
    UpdateTicks(false)
    cast.casting = false
    cast.stoppedAt = GetTime()
    if not cast.holdUntil then cast.wanted = 0 end
end

-- Time left, while casting.
local sinceTimer = 0
local function UpdateCastTimer(elapsed)
    if not cast.casting then return end
    sinceTimer = sinceTimer + elapsed
    if sinceTimer < TIMER_INTERVAL then return end
    sinceTimer = 0
    local duration = CastDuration()
    if duration and duration.GetRemainingDuration then
        cast.timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        cast.timer:SetText("")
    end
end

A.AddPart({
    Build = function()
        BuildCast()
        BuildTargetCast()
        -- Blizzard's player cast bar out of sight (the cast arc replaces it).
        HideCastBar(PlayerCastingBarFrame)
    end,
    Update = function(elapsed)
        Fade(cast, elapsed)
        UpdateCastTimer(elapsed)
        Fade(tcast, elapsed)
        UpdateTargetCastTimer(elapsed)
    end,
    Enable = function()
        ns:On("PLAYER_TARGET_CHANGED", CheckTargetCast)
        -- (fn gets the event's cast GUID and spell ID)
        local function IfPlayer(fn) return function(_, unit, ...) if unit == "player" then fn(...) end end end
        ns:On("UNIT_SPELLCAST_START", IfPlayer(function(guid, id) StartCast(false, guid, id) end))
        ns:On("UNIT_SPELLCAST_DELAYED", IfPlayer(function(guid, id) StartCast(false, guid, id) end))
        ns:On("UNIT_SPELLCAST_CHANNEL_START", IfPlayer(function(guid, id) StartCast(true, guid, id) end))
        ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", IfPlayer(function(guid, id) StartCast(true, guid, id) end))
        for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
            ns:On(event, IfPlayer(StopCast))
        end
        ns:On("UNIT_SPELLCAST_INTERRUPTED", IfPlayer(function(guid, id)
            ShowInterrupted(cast, INTERRUPTED or "Interrupted", guid, id)
        end))
        ns:On("UNIT_SPELLCAST_FAILED", IfPlayer(function(guid, id) ShowInterrupted(cast, FAILED or "Failed", guid, id) end))
        -- Your target's casts.
        local function IfTarget(fn) return function(_, unit, ...) if unit == "target" then fn(...) end end end
        ns:On("UNIT_SPELLCAST_START", IfTarget(function(guid, id) StartTargetCast(false, guid, id) end))
        ns:On("UNIT_SPELLCAST_DELAYED", IfTarget(function(guid, id) StartTargetCast(false, guid, id) end))
        ns:On("UNIT_SPELLCAST_CHANNEL_START", IfTarget(function(guid, id) StartTargetCast(true, guid, id) end))
        ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", IfTarget(function(guid, id) StartTargetCast(true, guid, id) end))
        ns:On("UNIT_SPELLCAST_INTERRUPTIBLE", IfTarget(CheckTargetCast))
        ns:On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", IfTarget(CheckTargetCast))
        for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
            ns:On(event, IfTarget(StopTargetCast))
        end
        ns:On("UNIT_SPELLCAST_INTERRUPTED", IfTarget(function(guid, id)
            ShowInterrupted(tcast, INTERRUPTED or "Interrupted", guid, id)
        end))
        ns:On("UNIT_SPELLCAST_FAILED", IfTarget(function(guid, id) ShowInterrupted(tcast, FAILED or "Failed", guid, id) end))
    end,
})
