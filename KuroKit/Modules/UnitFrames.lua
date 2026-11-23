-- Unit frames: small tweaks to Blizzard's own player, target, focus,
-- target-of-target and party frames (all still positioned by Edit Mode).
--   * players' health bars in class colour (NPCs keep Blizzard's look);
--     raid-style party / raid frames get Blizzard's own class colour option
--   * health as value + percentage (Blizzard's status text, set once; your
--     Interface settings decide after that)
--   * cleaner frames: no portrait combat text (player, pet), no resting zzz
--     or resting glow (instead, the level number turns rested blue while you
--     rest), no leader / guide icons on the player, target and focus frames
--
-- How: the bars are desaturated and tinted after every Blizzard update that
-- colours them (hooksecurefunc post-hooks on UnitFrameHealthBar_Update, the
-- target / focus faction check and the party frames' online status). Hidden
-- parts are faded to alpha 0, never hidden or moved, and kept at 0 by a
-- post-hook on their SetAlpha.
-- Cost: a colour call per health bar update; nothing else runs.
local _, ns = ...

local M = ns:NewModule("UnitFrames", {
    title = "Unit Frames",
    group = "Interface",
    desc = "Blizzard's unit frames with players' health bars in class colour, health as value and percentage, and "
        .. "without portrait combat text, resting glow and leader icons (resting: your level number turns blue).",
})

local function Secret(v) return issecretvalue and issecretvalue(v) end

---------------------------------------------------------------------------
-- Class-coloured health bars
---------------------------------------------------------------------------
local bars = {}    -- [health bar] = unit token
local tinted = {}  -- [health bar] = true while we've tinted it

-- The class colour for a connected player, else nil (NPCs, pets, offline:
-- Blizzard's own colours). A secret class still gives a colour.
local function ClassColor(unit)
    if not UnitExists(unit) then return nil end
    local isPlayer = UnitIsPlayer(unit)
    if Secret(isPlayer) or not isPlayer then return nil end
    local connected = UnitIsConnected(unit)
    if not Secret(connected) and not connected then return nil end
    local _, class = UnitClass(unit)
    if not class then return nil end
    local color = C_ClassColor and C_ClassColor.GetClassColor(class)
    if not color and not Secret(class) then color = RAID_CLASS_COLORS[class] end
    return color
end

local function Tint(bar)
    local unit = bar and bars[bar]
    if not unit then return end
    local color = ClassColor(unit)
    if color then
        bar:SetStatusBarDesaturated(true)
        bar:SetStatusBarColor(color.r, color.g, color.b)
        tinted[bar] = true
    elseif tinted[bar] then
        tinted[bar] = nil
        bar:SetStatusBarDesaturated(false)
        bar:SetStatusBarColor(1, 1, 1)
    end
end

local function TintAll()
    for bar in pairs(bars) do Tint(bar) end
end

local function Track(bar, unit)
    if bar and bar.SetStatusBarDesaturated then bars[bar] = unit end
end

local function TrackBars()
    Track(PlayerFrame and PlayerFrame.healthbar, "player")
    Track(TargetFrame and TargetFrame.healthbar, "target")
    Track(FocusFrame and FocusFrame.healthbar, "focus")
    Track(TargetFrameToT and TargetFrameToT.HealthBar, "targettarget")
    Track(FocusFrameToT and FocusFrameToT.HealthBar, "focustarget")
    for i = 1, 4 do
        local member = PartyFrame and PartyFrame["MemberFrame" .. i]
        local container = member and member.HealthBarContainer
        Track(container and container.HealthBar, "party" .. i)
        if member and type(member.UpdateOnlineStatus) == "function" then
            hooksecurefunc(member, "UpdateOnlineStatus", function()
                Tint(container and container.HealthBar)
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Cleaner frames
---------------------------------------------------------------------------
local concealed = {}

-- Faded to alpha 0 and kept there.
local function Conceal(region)
    if not region or concealed[region] or not region.SetAlpha then return end
    concealed[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then self:SetAlpha(0) end
    end)
end

local function Path(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        if type(node) ~= "table" then return nil end
        node = node[select(i, ...)]
    end
    return node
end

-- The player frame's status glow is yellow while resting and red in combat:
-- only the resting glow goes.
local statusTexture
local function RestingOnly()
    return IsResting() and not UnitAffectingCombat("player")
end

local function UpdateStatusGlow()
    if not statusTexture then return end
    statusTexture:SetAlpha(RestingOnly() and 0 or 1)
end

-- Resting: the level number by the portrait in rested blue, instead of
-- Blizzard's glow and zzz. Kept after Blizzard recolours it.
local RESTED_COLOR = { 0.45, 0.72, 1 }
local levelText, levelColor
local recolouring = false

local function UpdateLevelColor()
    if not levelText then return end
    recolouring = true
    if IsResting() then
        levelText:SetTextColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3])
    elseif levelColor then
        levelText:SetTextColor(levelColor[1], levelColor[2], levelColor[3])
    end
    recolouring = false
end

local function SetupLevelColor()
    levelText = PlayerLevelText
        or Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "PlayerLevelText")
        or Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentContextual", "PlayerLevelText")
    if not (levelText and levelText.SetTextColor) then levelText = nil return end
    local r, g, b = levelText:GetTextColor()
    levelColor = { r, g, b }
    -- Blizzard's own colour changes (if any) become the colour to go back to.
    hooksecurefunc(levelText, "SetTextColor", function(_, nr, ng, nb)
        if recolouring then return end
        levelColor = { nr, ng, nb }
        if IsResting() then UpdateLevelColor() end
    end)
    UpdateLevelColor()
    ns:On("PLAYER_UPDATE_RESTING", UpdateLevelColor)
    -- After a reload inside an inn the game reports resting a little after
    -- login, without a PLAYER_UPDATE_RESTING: look again once the world is in.
    ns:On("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0, UpdateLevelColor)
        C_Timer.After(2, UpdateLevelColor)
    end)
    ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(0, UpdateLevelColor) end)
end

local function CleanFrames()
    local main = Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain")
    local contextual = Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentContextual")
    Conceal(main and main.HitIndicator)
    Conceal(PetHitIndicator)
    if contextual then
        Conceal(contextual.PlayerRestLoop)
        Conceal(contextual.PlayerRestIcon)
        Conceal(contextual.PlayerRestGlow)
        Conceal(contextual.LeaderIcon)
        Conceal(contextual.GuideIcon)
    end
    for _, frame in ipairs({ TargetFrame, FocusFrame }) do
        local targetContextual = Path(frame, "TargetFrameContent", "TargetFrameContentContextual")
        if targetContextual then
            Conceal(targetContextual.LeaderIcon)
            Conceal(targetContextual.GuideIcon)
        end
    end
    SetupLevelColor()
    statusTexture = main and main.StatusTexture
    if statusTexture then
        hooksecurefunc(statusTexture, "SetAlpha", function(self, alpha)
            if alpha ~= 0 and RestingOnly() then self:SetAlpha(0) end
        end)
        UpdateStatusGlow()
        ns:On("PLAYER_UPDATE_RESTING", UpdateStatusGlow)
        ns:On("PLAYER_REGEN_DISABLED", UpdateStatusGlow)
        ns:On("PLAYER_REGEN_ENABLED", UpdateStatusGlow)
        if PlayerFrame_UpdateStatus then hooksecurefunc("PlayerFrame_UpdateStatus", UpdateStatusGlow) end
    end
end

---------------------------------------------------------------------------
-- Settings set once (your Interface settings decide after that)
---------------------------------------------------------------------------
local function SetCVarIf(cvar, value)
    local current = C_CVar.GetCVar(cvar)
    if current ~= nil and current ~= value then C_CVar.SetCVar(cvar, value) end
end

local function SeedSettings()
    if M.db.seeded then return end
    ns:OutOfCombat(function()
        M.db.seeded = true
        SetCVarIf("statusText", "1")              -- health / power text always shown
        SetCVarIf("statusTextDisplay", "BOTH")    -- percentage left, value right
        SetCVarIf("raidFramesDisplayClassColor", "1") -- raid-style party / raid frames
    end)
end

function M:OnEnable()
    SeedSettings()
    TrackBars()
    CleanFrames()
    hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
        if bars[bar] then Tint(bar) end
    end)
    for _, frame in ipairs({ TargetFrame, FocusFrame }) do
        if frame and type(frame.CheckFaction) == "function" then
            hooksecurefunc(frame, "CheckFaction", function(self) Tint(self.healthbar) end)
        end
    end
    local function TintSoon() C_Timer.After(0, TintAll) end
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
        "UNIT_CONNECTION",
    }) do
        ns:On(event, TintSoon)
    end
    ns:On("UNIT_TARGET", function(_, unit)
        if unit == "target" or unit == "focus" then TintSoon() end
    end)
    TintAll()
end
