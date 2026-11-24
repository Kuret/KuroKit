-- Raid frames: Blizzard's raid-style party and raid frames (compact unit
-- frames) in the same rounded bronze plate as the unit frame skin: a dark
-- outline, a bronze line lighter at the top, and a dark rim around the health
-- and power cells, with stepped (pixel) corners. Class colours come from the
-- game setting the Unit Frames module turns on.
--
-- How: the bars are inset inside the frame so the plate shows around them
-- (Blizzard insets them 1 px; we use PLATE_RING), Blizzard's dark background
-- follows the health cell. The plate is plain textures on the frame's
-- BACKGROUND layer, anchored to the frame and the bars by both corners, so it
-- follows every size Edit Mode gives the frames. Re-applied after each of
-- Blizzard's layout passes (DefaultCompactUnitFrameSetup / ApplyConfig /
-- UpdateAll), only on frames named Compact* (raid / party, not nameplates),
-- and not on the small pet / target frames.
-- The bars get the nameplates' fill; the role icon and name sit top left and
-- the health text small at the bottom right, outlined.
-- Blizzard's aggro border (a ring stretched over the frame) is replaced by
-- the plate's own edge in the aggro colour.
-- Cost: a few SetPoint calls per frame when Blizzard lays it out.
local _, ns = ...

local M = ns:NewModule("RaidFrames", {
    title = "Raid Frames",
    group = "Interface",
    desc = "Raid-style party and raid frames in the same rounded bronze plate as the unit frames.",
})

local PLATE_RING = 3       -- px from the frame edge to the bars: outline, bronze, rim
local PLATE_RADIUS = 3
local DIVIDER = 3          -- px between health and power: rim, bronze, rim
local POWER_HEIGHT = 6     -- px
local BAR_FILL_ATLAS = "UI-HUD-CoolDownManager-Bar" -- the nameplates' / unit frames' fill
local BAR_TEXTURE = "Interface/Buttons/WHITE8X8"    -- replaced by the fill atlas
local STATUS_TEXT_SIZE = 10
local FILL_DIM = 0.7       -- health colours at this brightness: white text reads on every class
local TEXT_INSET = 3
local skins = setmetatable({}, { __mode = "k" })

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function Skin(frame)
    local s = skins[frame]
    if s then return s end
    s = {
        outline = ns.RoundShape(frame, -8, ns.PLATE_OUTLINE, PLATE_RADIUS),
        bronze = ns.RoundShape(frame, -7, nil, PLATE_RADIUS - 1),
        -- Aggro: over the outline and the bronze line (a 2 px coloured edge),
        -- below the rims.
        aggro = ns.RoundShape(frame, -6, { 1, 1, 1, 1 }, PLATE_RADIUS),
        healthRim = ns.RoundShape(frame, -5, ns.PLATE_RIM, 1),
        powerRim = ns.RoundShape(frame, -5, ns.PLATE_RIM, 1),
    }
    ns.ShadeShape(s.bronze, ns.PLATE_BRONZE_TOP, ns.PLATE_BRONZE_BOTTOM)
    -- The nameplates' bar fill (Blizzard colours it: class / power colours).
    for _, bar in ipairs({ frame.healthBar, frame.powerBar }) do
        if bar then
            bar:SetStatusBarTexture(BAR_TEXTURE)
            bar:GetStatusBarTexture():SetAtlas(BAR_FILL_ATLAS)
        end
    end
    -- Health colours dimmed (after every colour Blizzard sets), so white
    -- text reads on light class colours (priests).
    local health = frame.healthBar
    local dimming = false
    local function Dim(bar, r, g, b)
        if dimming or type(r) ~= "number" or Secret(r) or Secret(g) or Secret(b) then return end
        dimming = true
        bar:SetStatusBarColor(r * FILL_DIM, g * FILL_DIM, b * FILL_DIM)
        dimming = false
    end
    hooksecurefunc(health, "SetStatusBarColor", Dim)
    Dim(health, health:GetStatusBarColor())
    -- Crisp text: a thin outline and a small soft shadow.
    for _, fs in ipairs({ frame.name, frame.statusText }) do
        local file, size = fs:GetFont()
        if file then fs:SetFont(file, size, "OUTLINE") end
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.6)
    end
    -- Blizzard's aggro border is a ring stretched over the whole frame: out
    -- of sight, its shown state and colour mirrored on our edge. The values
    -- may be secret: alpha through SetAlphaFromBoolean, colour passed on.
    local highlight = frame.aggroHighlight
    for _, tex in ipairs(s.aggro) do tex:SetAlpha(0) end
    if highlight then
        local function Shown(shown)
            for _, tex in ipairs(s.aggro) do
                if not pcall(tex.SetAlphaFromBoolean, tex, shown, 1, 0) and not (issecretvalue and issecretvalue(shown)) then
                    tex:SetAlpha(shown and 1 or 0)
                end
            end
        end
        hooksecurefunc(highlight, "SetShown", function(_, shown) Shown(shown) end)
        hooksecurefunc(highlight, "Show", function() Shown(true) end)
        hooksecurefunc(highlight, "Hide", function() Shown(false) end)
        hooksecurefunc(highlight, "SetVertexColor", function(_, r, g, b)
            for _, tex in ipairs(s.aggro) do pcall(tex.SetVertexColor, tex, r, g, b) end
        end)
        local ok, shown = pcall(highlight.IsShown, highlight)
        if ok then Shown(shown) end
        local okColor, r, g, b = pcall(highlight.GetVertexColor, highlight)
        if okColor then for _, tex in ipairs(s.aggro) do pcall(tex.SetVertexColor, tex, r, g, b) end end
        ns.Conceal(highlight)
    end
    skins[frame] = s
    return s
end

local function IsRaidFrame(frame)
    if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then return false end
    if not (frame.healthBar and frame.background) then return false end
    -- Nameplates have a HealthBarsContainer; raid frames don't.
    if frame.HealthBarsContainer then return false end
    -- Named frames: only Compact* (pooled ones have no name).
    local name = frame:GetName()
    if type(name) == "string" and name:sub(1, 7) ~= "Compact" then return false end
    -- Not the small pet / target frames (no power bar, mini layout).
    local mini = DefaultCompactMiniFrameSetup
    return not (mini and frame.updateAllSetupFunc == mini)
end

local function Layout(frame)
    if not IsRaidFrame(frame) then return end
    local health, power = frame.healthBar, frame.powerBar
    if InCombatLockdown() and (health:IsProtected() or (power and power:IsProtected())) then
        ns:OutOfCombat(function() Layout(frame) end)
        return
    end
    local s = Skin(frame)
    local px = PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
    local R = PLATE_RING
    local hasPower = power and power:IsShown()
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", frame, "TOPLEFT", R * px, -R * px)
    health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -R * px, (hasPower and (R + POWER_HEIGHT + DIVIDER) or R) * px)
    if hasPower then
        power:ClearAllPoints()
        power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -DIVIDER * px)
        power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -R * px, R * px)
    end
    -- Blizzard's dark background: the health cell only (the power bar has
    -- its own).
    frame.background:ClearAllPoints()
    frame.background:SetAllPoints(health)
    -- Texts: role icon and name top left, the health text small at the bottom
    -- right (whatever name placement Edit Mode's aura organization picks).
    local role, name, status = frame.roleIcon, frame.name, frame.statusText
    if role then
        role:ClearAllPoints()
        role:SetPoint("TOPLEFT", health, "TOPLEFT", TEXT_INSET - 1, -(TEXT_INSET - 1))
    end
    if name then
        name:ClearAllPoints()
        if role then
            name:SetPoint("TOPLEFT", role, "TOPRIGHT", 1, -1)
        else
            name:SetPoint("TOPLEFT", health, "TOPLEFT", TEXT_INSET, -TEXT_INSET)
        end
        name:SetPoint("RIGHT", health, "RIGHT", -TEXT_INSET, 0)
        name:SetJustifyH("LEFT")
    end
    if status then
        status:ClearAllPoints()
        status:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -TEXT_INSET, TEXT_INSET)
        status:SetJustifyH("RIGHT")
        status:SetFontHeight(STATUS_TEXT_SIZE)
        status:SetHeight(STATUS_TEXT_SIZE)
    end
    ns.AnchorShape(s.outline, frame, 0, px)
    ns.AnchorShape(s.aggro, frame, 0, px)
    ns.AnchorShape(s.bronze, frame, 1, px)
    ns.AnchorShape(s.healthRim, health, -1, px)
    ns.ShowShape(s.powerRim, hasPower and true or false)
    if hasPower then ns.AnchorShape(s.powerRim, power, -1, px) end
end

local function SafeLayout(frame) ns.safecall(Layout, frame) end

local function ForEachNamed(fn)
    for i = 1, 5 do fn("CompactPartyFrameMember" .. i) end
    for i = 1, 40 do fn("CompactRaidFrame" .. i) end
    for group = 1, 8 do
        for member = 1, 5 do fn("CompactRaidGroup" .. group .. "Member" .. member) end
    end
end

local function LayoutAll()
    ForEachNamed(function(name) SafeLayout(_G[name]) end)
end

-- /kk raidframes test: in Edit Mode, its blue selection overlay over the
-- raid and party frames turns see-through, to see their look in the preview
-- (a preview frame of our own can't run Blizzard's frame code: its secret
-- health values only work in Blizzard's own execution). Again, or closing
-- Edit Mode, brings the overlay back.
local SEE_THROUGH = 0.1
local seeThrough = false

local function OverlayAlpha()
    for _, system in ipairs({ CompactRaidFrameContainer, CompactPartyFrame, PartyFrame }) do
        local selection = system and system.Selection
        if selection then selection:SetAlpha(seeThrough and SEE_THROUGH or 1) end
    end
end

local function TogglePreview()
    if not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        ns:Print("raid frame preview: open Edit Mode first (with the party or raid frames shown)")
        return
    end
    seeThrough = not seeThrough
    OverlayAlpha()
end

-- /kk raidframes: which raid / party frames exist and which got the plate.
function M:OnSlash(args)
    if args and args:lower():match("^%s*test") then TogglePreview() return end
    local count = 0
    for _ in pairs(skins) do count = count + 1 end
    ns:Print(("raid frames: %d skinned"):format(count))
    ForEachNamed(function(name)
        local frame = _G[name]
        if frame and frame:IsShown() then
            ns:Print(("  %s: %s, raid frame check %s"):format(name, skins[frame] and "skinned" or "not skinned",
                tostring(IsRaidFrame(frame))))
        end
    end)
end

function M:OnEnable()
    if DefaultCompactUnitFrameSetup then hooksecurefunc("DefaultCompactUnitFrameSetup", SafeLayout) end
    if CompactUnitFrame_UpdateAll then hooksecurefunc("CompactUnitFrame_UpdateAll", SafeLayout) end
    if CompactUnitFrameUtil and CompactUnitFrameUtil.ApplyConfig then
        hooksecurefunc(CompactUnitFrameUtil, "ApplyConfig", SafeLayout)
    end
    -- Frames already laid out before we loaded, and Edit Mode's previews.
    LayoutAll()
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function() C_Timer.After(0, LayoutAll) end)
        EditModeManagerFrame:HookScript("OnHide", function()
            if seeThrough then seeThrough = false; OverlayAlpha() end
        end)
    end
    ns:On("GROUP_ROSTER_UPDATE", function() C_Timer.After(0, LayoutAll) end)
    ns:On("UI_SCALE_CHANGED", function()
        for frame in pairs(skins) do SafeLayout(frame) end
    end)
end
