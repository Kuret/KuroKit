-- Low health warning: the screen edges glow red as your health drops,
-- building up from 50% to full strength at 20%, with a slow pulse, so it
-- catches the eye from the corner of the screen (movement reads better there
-- than colour). Drawn under the interface, over the world. Replaces
-- Blizzard's own low health flash (on / off at 35%), which is switched off
-- once (CVar doNotFlashLowHealthWarning; a game setting you can turn back on).
--
-- How: your health may be secret to addons in combat, so the addon never
-- reads it: UnitHealthPercent with a curve (health fraction -> glow strength)
-- is evaluated by the client and handed to SetAlpha, which accepts secret
-- values. The pulse is an animation on the texture inside that frame, so it
-- only shows as far as the frame does. Off while dead or a ghost.
-- Cost: one curve evaluation per health change.
local _, ns = ...

local M = ns:NewModule("LowHealth", {
    title = "Low Health Warning",
    group = "Interface",
    desc = "The screen edges glow red as your health drops, from 50% to full strength at 20%, with a slow pulse. "
        .. "Replaces Blizzard's low health flash.",
})

local TEXTURE = "Interface\\FullScreenTextures\\LowHealth" -- Blizzard's own red edge
local START = 0.5      -- health fraction where the glow begins
local FULL = 0.2       -- and where it is at full strength
local PULSE_LOW = 0.45 -- the pulse's dimmest point (share of the glow)
local PULSE_TIME = 0.6 -- seconds per half pulse

local frame, curve

local function Update()
    if UnitIsDeadOrGhost("player") then frame:Hide() return end
    frame:Show()
    frame:SetAlpha(UnitHealthPercent("player", true, curve))
end

function M:OnEnable()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then return end
    curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(0, 1)
    curve:AddPoint(FULL, 1)
    curve:AddPoint(START, 0)
    curve:AddPoint(1, 0)

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(0)
    frame:EnableMouse(false)
    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetTexture(TEXTURE)
    glow:SetBlendMode("ADD")
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(PULSE_LOW)
    fade:SetDuration(PULSE_TIME)
    fade:SetSmoothing("IN_OUT")
    pulse:Play()

    if not self.db.blizzardFlashSeeded then
        self.db.blizzardFlashSeeded = true
        if GetCVar("doNotFlashLowHealthWarning") ~= nil then SetCVar("doNotFlashLowHealthWarning", "1") end
    end

    ns:On("UNIT_HEALTH", function(_, unit) if unit == "player" then Update() end end)
    ns:On("UNIT_MAXHEALTH", function(_, unit) if unit == "player" then Update() end end)
    ns:On("PLAYER_DEAD", Update)
    ns:On("PLAYER_ALIVE", Update)
    ns:On("PLAYER_UNGHOST", Update)
    ns:On("PLAYER_ENTERING_WORLD", Update)
    Update()
end
