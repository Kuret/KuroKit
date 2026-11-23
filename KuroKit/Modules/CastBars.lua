-- Cast bars: Blizzard's player, target and focus cast bars with the flight
-- timer's look, without making them feel non-native.
--   * a soft drop shadow (the cast bar's own shadow art)
--   * no text box under the bar: the spell name sits by the bar's left end
--     in gold and the time left by its right end in white, both outlined;
--     above the player's bar (as on the flight timer), below the target's
--     and focus' (above them is their frame and auras)
--   * player: a red zone at the end of a cast as wide as your latency, to
--     time the next cast (the spell queue); at the start for channels
--   * target and focus bars slightly larger; the player's size stays Edit
--     Mode's (Cast Bar > Bar Size)
--
-- How: textures and text are added to Blizzard's bars (nothing of theirs is
-- replaced); a HookScript'ed OnUpdate writes the time left, from the game's
-- cast duration objects (which also work when the time is secret).
-- Cost: one short text update per bar 20 times a second, only while it casts.
local _, ns = ...

local M = ns:NewModule("CastBars", {
    title = "Cast Bars",
    group = "Interface",
    desc = "Blizzard's cast bars in the flight timer's look: soft drop shadow, the spell name in gold and the time left "
        .. "by the bar's ends, outlined; target and focus bars slightly larger, and a latency zone at the end of your "
        .. "own casts. Your cast bar's size: Edit Mode.",
})

local TIMER_INTERVAL = 0.05   -- seconds between time-left updates
local TARGET_SCALE = 1.15     -- target and focus cast bars
local LABEL_GAP = 6           -- px between the bar and its name / time (as on the flight timer)
local TIME_ROOM = 44          -- px of the bar's width kept free of the name for the time
local SHADOW_ATLAS = "castbar_shadow_embedded"
local LATENCY_COLOR = { 1, 0.15, 0.1, 0.55 }

local extras = {}   -- [bar] = { timer, shadow, zone, elapsed, above, small } (ours; nothing written on Blizzard's bars)

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function PlainNumber(v) if type(v) == "number" and not Secret(v) then return v end end

---------------------------------------------------------------------------
-- Time left
---------------------------------------------------------------------------
local function Remaining(bar, unit)
    local channel = bar.channeling
    local durationOf = channel and UnitChannelDuration or UnitCastingDuration
    local duration = durationOf and durationOf(unit)
    if duration and duration.GetRemainingDuration then return duration:GetRemainingDuration() end
    -- Older API: end time, readable when it isn't secret.
    local _, _, _, _, endMS = (channel and UnitChannelInfo or UnitCastingInfo)(unit)
    endMS = PlainNumber(endMS)
    return endMS and math.max(0, endMS / 1000 - GetTime())
end

local function UpdateTimer(bar)
    local x = extras[bar]
    local unit = bar.unit
    if not (unit and (bar.casting or bar.channeling)) then
        x.timer:SetText("")
        if x.zone then x.zone:Hide() end
        return
    end
    local left = Remaining(bar, unit)
    if left ~= nil then x.timer:SetFormattedText("%.1f", left) else x.timer:SetText("") end
end

---------------------------------------------------------------------------
-- Latency zone (player)
---------------------------------------------------------------------------
local function PlaceLatency(channel)
    local bar = PlayerCastingBarFrame
    local zone = bar and extras[bar] and extras[bar].zone
    if not zone then return end
    local _, _, _, startMS, endMS = (channel and UnitChannelInfo or UnitCastingInfo)("player")
    startMS, endMS = PlainNumber(startMS), PlainNumber(endMS)
    local _, _, _, latency = GetNetStats()
    local width = PlainNumber(bar:GetWidth())
    if not (startMS and endMS and endMS > startMS and latency and latency > 0 and width and width > 0) then
        zone:Hide()
        return
    end
    local castSeconds = (endMS - startMS) / 1000
    zone:ClearAllPoints()
    local side = channel and "LEFT" or "RIGHT" -- a channel's bar empties towards the left
    zone:SetPoint("TOP" .. side)
    zone:SetPoint("BOTTOM" .. side)
    zone:SetWidth(math.max(1, math.min(width, width * (latency / 1000) / castSeconds)))
    zone:Show()
end

---------------------------------------------------------------------------
-- The look
---------------------------------------------------------------------------
-- Faded to alpha 0 and kept there (Blizzard's text box under the bar).
local concealed = {}
local function Conceal(region)
    if not region or concealed[region] then return end
    concealed[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then self:SetAlpha(0) end
    end)
end

-- Name and time by the bar's ends, above or below it. Re-applied whenever
-- Blizzard restyles the bar (SetLook) or Edit Mode resizes it.
local function Layout(bar)
    local x = extras[bar]
    local edge, barEdge, y = "BOTTOM", "TOP", LABEL_GAP
    if not x.above then edge, barEdge, y = "TOP", "BOTTOM", -LABEL_GAP end
    local width = PlainNumber(bar:GetWidth())
    local text = bar.Text
    if text then
        text:SetFontObject(x.small and GameFontNormalSmall or GameFontNormal) -- gold, as the flight timer's route
        text:ClearAllPoints()
        text:SetPoint(edge .. "LEFT", bar, barEdge .. "LEFT", 0, y)
        if width and width > TIME_ROOM then text:SetWidth(width - TIME_ROOM) end
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        ns.OutlineText(text)
    end
    x.timer:SetFontObject(x.small and GameFontHighlightSmall or GameFontHighlight)
    x.timer:ClearAllPoints()
    x.timer:SetPoint(edge .. "RIGHT", bar, barEdge .. "RIGHT", 0, y)
    ns.OutlineText(x.timer)
end

-- above: name and time above the bar (else below); small: the smaller fonts.
local function Polish(bar, withLatency, above, small)
    if not bar or extras[bar] then return end
    local x = { elapsed = 0, above = above, small = small }
    extras[bar] = x
    x.shadow = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    x.shadow:SetAtlas(SHADOW_ATLAS)
    x.shadow:SetPoint("TOPLEFT", -3, 3)
    x.shadow:SetPoint("BOTTOMRIGHT", 5, -5)
    x.timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x.timer:SetJustifyH("RIGHT")
    Conceal(bar.TextBorder)
    if withLatency then
        x.zone = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        x.zone:SetColorTexture(LATENCY_COLOR[1], LATENCY_COLOR[2], LATENCY_COLOR[3], LATENCY_COLOR[4])
        x.zone:Hide()
    end
    Layout(bar)
    -- Blizzard restyles the bar when it's attached to / detached from the
    -- player frame (Edit Mode), which resets the text's font and spot.
    if type(bar.SetLook) == "function" then
        hooksecurefunc(bar, "SetLook", function(self) Layout(self) end)
    end
    bar:HookScript("OnSizeChanged", function(self) Layout(self) end)
    bar:HookScript("OnUpdate", function(self, elapsed)
        x.elapsed = x.elapsed + elapsed
        if x.elapsed < TIMER_INTERVAL then return end
        x.elapsed = 0
        UpdateTimer(self)
    end)
end

local function Enlarge(bar)
    if not bar then return end
    ns:OutOfCombat(function()
        if math.abs(bar:GetScale() - TARGET_SCALE) > 0.001 then bar:SetScale(TARGET_SCALE) end
    end)
end

function M:OnEnable()
    Polish(PlayerCastingBarFrame, true, true, false)
    Polish(TargetFrameSpellBar, false, false, true)
    Polish(FocusFrameSpellBar, false, false, true)
    Enlarge(TargetFrameSpellBar)
    Enlarge(FocusFrameSpellBar)
    ns:On("UNIT_SPELLCAST_START", function(_, unit) if unit == "player" then PlaceLatency(false) end end)
    ns:On("UNIT_SPELLCAST_DELAYED", function(_, unit) if unit == "player" then PlaceLatency(false) end end)
    ns:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit) if unit == "player" then PlaceLatency(true) end end)
end
