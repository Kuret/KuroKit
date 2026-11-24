-- Auras: your buffs and debuffs (top right; Blizzard's BuffFrame and
-- DebuffFrame, laid out by Edit Mode as usual) in a tidier look:
--   * icons in Forever's action button look: the action bar's rounded icon
--     mask (1.5 x the icon, as on Blizzard's small action buttons: the
--     mask art's opaque part is that much smaller than the art) and icon
--     frame (UI-HUD-ActionBar-IconFrame); for
--     debuffs the frame is tinted in the debuff type's colour (magic blue,
--     curse purple, ...), for weapon enchants purple; Blizzard's borders hidden
--   * a larger, outlined timer under the icon (38m, 2h, 45), gold, white
--     under 90 seconds and red under 10
--
-- How: each aura button is styled once (they're created up front). The timer
-- is the game's own duration text binding (C_DurationUtil): the client
-- counts the aura's duration object (C_UnitAuras.GetAuraDuration) down into
-- our font string and colours it from a colour curve, which keeps working in
-- combat, where aura times are secret to addons. Weapon enchants have no
-- aura: their timer is written from Blizzard's UpdateDuration (plain times).
-- Post-hooks on the button's Update (aura, tint) and UpdateDuration; Blizzard's
-- text and borders faded out with alpha (never hidden). The target / focus
-- frame auras are locked against addons on this client and stay Blizzard's.
-- Cost: the client updates the timer text; nothing per frame in Lua.
local _, ns = ...

local M = ns:NewModule("Auras", {
    title = "Buffs & Debuffs",
    group = "Interface",
    desc = "Your buffs and debuffs in the action bar's icon frame (debuffs tinted in their type's colour) with a larger timer.",
})

local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local ICON_FRAME = "UI-HUD-ActionBar-IconFrame"
local FRAME_EXTRA = 1 / 45   -- the frame art is 46 x 45 for a 45 icon: 1 px shadow on the right
local MASK_SCALE = 1.5       -- mask size / icon size (SmallActionButtonMixin: 45 for 30)
local TINT_LIFT = 0.35       -- debuff tints mixed with white, so the frame's shading stays visible
local ENCHANT = { 0.6, 0.25, 0.9 }
local TIMER_SIZE = 12
local WARN_TIME = 90         -- white under this (Blizzard's warning time)
local URGENT_TIME = 10       -- red under this
local GOLD = CreateColor(1, 0.82, 0)
local WHITE = CreateColor(1, 1, 1)
local RED = CreateColor(1, 0.25, 0.2)

local styled = setmetatable({}, { __mode = "k" })
local timerFont, formatter, colorCurve

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function TimerFont()
    if timerFont then return timerFont end
    timerFont = CreateFont("KuroKitAuraTimerFont")
    timerFont:CopyFontObject(GameFontHighlight)
    local file = timerFont:GetFont()
    timerFont:SetFont(file, TIMER_SIZE, "OUTLINE")
    timerFont:SetShadowOffset(1, -1)
    timerFont:SetShadowColor(0, 0, 0, 1)
    return timerFont
end

-- The game's seconds formatter, set up as Blizzard's aura buttons use it,
-- without spaces ("38m"); the colour curve over the time left.
local function Formatter()
    if formatter ~= nil then return formatter end
    formatter = false
    if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter and C_DurationUtil and C_CurveUtil) then return false end
    local ok = pcall(function()
        local f = C_StringUtil.CreateSecondsFormatter()
        local E = Enum
        f:SetDefaultAbbreviation(E.SecondsFormatterAbbreviation.OneLetter)
        f:SetRounding(E.SecondsFormatterRounding.Truncate)
        f:SetCanRoundUpLastUnit(true)
        f:SetMinInterval(E.SecondsFormatterInterval.Seconds)
        f:SetDesiredUnitCount(1)
        if f.SetStripIntervalWhitespace and E.SecondsFormatterIntervalWhitespace then
            f:SetStripIntervalWhitespace(E.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
        end
        -- Up to 90 s in seconds, up to 90 min in minutes, then hours.
        local intervals = C_CurveUtil.CreateCurve()
        if intervals.SetType and E.LuaCurveType then intervals:SetType(E.LuaCurveType.Step) end
        intervals:AddPoint(0, E.SecondsFormatterInterval.Seconds)
        intervals:AddPoint(91, E.SecondsFormatterInterval.Minutes)
        intervals:AddPoint(1 + 1.5 * 3600, E.SecondsFormatterInterval.Hours)
        f:SetMaxIntervalCurve(intervals)
        local colors = C_CurveUtil.CreateColorCurve()
        if colors.SetType and E.LuaCurveType then colors:SetType(E.LuaCurveType.Step) end
        colors:AddPoint(0, RED)
        colors:AddPoint(URGENT_TIME, WHITE)
        colors:AddPoint(WARN_TIME, GOLD)
        formatter, colorCurve = f, colors
    end)
    if not ok then formatter = false end
    return formatter
end

local function Binding(s)
    if s.binding ~= nil then return s.binding end
    s.binding = false
    if not Formatter() then return false end
    local ok, binding = pcall(function()
        local b = C_DurationUtil.CreateDurationTextBinding()
        b:SetToDefaults()
        b:SetFormatter(formatter)
        b:SetFontString(s.timer)
        if b.SetZeroDurationText then b:SetZeroDurationText("") end
        if b.SetExpiredText then b:SetExpiredText("") end
        b:SetTextColorCurve(colorCurve, Enum.DurationTextBindingProperty.RemainingDuration)
        b:SetEnabled(false)
        return b
    end)
    if ok then s.binding = binding end
    return s.binding
end

-- `color` nil: the frame's own colours.
local function SetTint(button, color)
    local s = styled[button]
    if s.tint == (color or false) then return end
    s.tint = color or false
    if color then
        local l = TINT_LIFT
        s.frame:SetVertexColor(color[1] + (1 - color[1]) * l, color[2] + (1 - color[2]) * l, color[3] + (1 - color[3]) * l)
    else
        s.frame:SetVertexColor(1, 1, 1)
    end
end

local debuffColors = {}
local function DebuffColor(debuffType)
    local key = (not Secret(debuffType) and debuffType) or "None"
    if debuffColors[key] then return debuffColors[key] end
    local info = AuraUtil.GetDebuffDisplayInfoTable and AuraUtil.GetDebuffDisplayInfoTable()
    local entry = info and (info[key] or info.None)
    local c = entry and entry.color
    debuffColors[key] = c and { c.r, c.g, c.b } or { 0.8, 0, 0 }
    return debuffColors[key]
end

-- The timer: bound to the aura's duration object, or (weapon enchants, or no
-- binding on this client) written by OnDuration.
local function BindTimer(button, info)
    local s = styled[button]
    local binding = Binding(s)
    local id = info.auraInstanceID
    local duration
    if binding and id ~= nil and not Secret(id) then
        local ok, d = pcall(C_UnitAuras.GetAuraDuration, PlayerFrame and PlayerFrame.unit or "player", id)
        if ok then duration = d end
    end
    if duration then
        binding:SetDuration(duration)
        binding:SetEnabled(true)
        s.bound = true
    else
        if binding then binding:SetEnabled(false) end
        s.bound = false
    end
    s.timer:SetShown(GetCVarBool("buffDurations"))
end

local function OnUpdate(button, info)
    if button.isExample or not info then return end
    local kind = button.auraType
    if kind == "Debuff" or kind == "DeadlyDebuff" then
        SetTint(button, DebuffColor(info.debuffType))
    elseif kind == "TempEnchant" then
        SetTint(button, ENCHANT)
    else
        SetTint(button, nil)
    end
    BindTimer(button, info)
end

local function OnDuration(button, timeLeft)
    local s = styled[button]
    if button.isExample or s.bound or type(timeLeft) == "nil" then return end
    local timer = s.timer
    if Secret(timeLeft) then
        -- No binding: Blizzard's own text.
        timer:SetText(button.Duration:GetText())
        timer:SetTextColor(GOLD:GetRGB())
        return
    end
    if timeLeft >= 3600 then
        timer:SetFormattedText("%dh", math.ceil(timeLeft / 3600))
    elseif timeLeft > WARN_TIME then
        timer:SetFormattedText("%dm", math.ceil(timeLeft / 60))
    else
        timer:SetFormattedText("%d", math.ceil(timeLeft))
    end
    local color = timeLeft < URGENT_TIME and RED or timeLeft < WARN_TIME and WHITE or GOLD
    timer:SetTextColor(color:GetRGB())
end

local function Style(button)
    if styled[button] or button.isAuraAnchor or not (button.Icon and button.Duration) then return end
    local s = {}
    styled[button] = s
    local icon = button.Icon
    local size = icon:GetWidth()
    s.mask = button:CreateMaskTexture()
    s.mask:SetAtlas(ICON_MASK)
    s.mask:SetPoint("CENTER", icon, "CENTER")
    s.mask:SetSize(size * MASK_SCALE, size * MASK_SCALE)
    icon:AddMaskTexture(s.mask)
    s.frame = button:CreateTexture(nil, "ARTWORK", nil, 1)
    s.frame:SetAtlas(ICON_FRAME)
    s.frame:SetPoint("TOPLEFT", icon, "TOPLEFT")
    s.frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", size * FRAME_EXTRA, 0)
    SetTint(button, nil)
    -- Our timer where Blizzard's sits (its anchor follows the Edit Mode
    -- layout: below, above or beside the icon).
    s.timer = button:CreateFontString(nil, "OVERLAY")
    s.timer:SetFontObject(TimerFont())
    s.timer:SetTextColor(GOLD:GetRGB())
    s.timer:SetPoint("CENTER", button.Duration, "CENTER")
    -- Edit Mode's example auras write Blizzard's text directly: copy it.
    hooksecurefunc(button.Duration, "SetFormattedText", function(self)
        if button.isExample then
            if s.binding then s.binding:SetEnabled(false) end
            s.bound = false
            s.timer:SetText(self:GetText())
            s.timer:Show()
        end
    end)
    ns.Conceal(button.Duration)
    ns.Conceal(button.DebuffBorder)
    ns.Conceal(button.TempEnchantBorder)
    if button.Update then hooksecurefunc(button, "Update", function(...) ns.safecall(OnUpdate, ...) end) end
    if button.UpdateDuration then
        hooksecurefunc(button, "UpdateDuration", function(...) ns.safecall(OnDuration, ...) end)
    end
end

local function StyleAll(frame)
    if not (frame and frame.auraFrames) then return end
    for _, button in ipairs(frame.auraFrames) do ns.safecall(Style, button) end
end

function M:OnEnable()
    StyleAll(BuffFrame)
    StyleAll(DebuffFrame)
end
