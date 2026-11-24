-- Frame fading: your player frame stays out of sight while it isn't needed.
--   * shown in combat, while you have a target, and while the mouse is over
--     the spot where it sits; faded out otherwise (and always shown in Edit
--     Mode)
--   * the Cooldown Manager follows the same rules when Edit Mode has it set
--     to show in combat only: out of combat it also shows while you have a
--     target or the mouse is over its spot
--   * the action bars fade to MOVING_ALPHA once you've been on the move for
--     MOVING_DELAY out of combat (travelling: you're looking at the world),
--     counted from AFTER_COMBAT after a fight at the earliest; they come back
--     (slowly) STILL_DELAY after you stop, and at once when combat starts
--
-- How: the player frame is faded with SetAlpha (it stays clickable and in
-- place; Edit Mode keeps positioning it). The Cooldown Manager bars are
-- shown / hidden the way Blizzard's own "in combat" setting does it (their
-- Show / Hide; they aren't protected), re-applied after Blizzard's own
-- visibility update (a post-hook on UpdateShownState). Their spot is
-- remembered from when they last showed, for the mouse-over check.
-- The action bars: SetAlpha on Blizzard's bar frames (not protected for
-- alpha); moving is IsPlayerMoving (walking, running, riding).
-- Cost: a cursor and movement check 10 times a second.
local _, ns = ...

local M = ns:NewModule("FrameFade", {
    title = "Frame Fading",
    group = "Interface",
    desc = "Your player frame fades out of combat and comes back while you have a target or hover its spot. The "
        .. "Cooldown Manager, when Edit Mode shows it in combat only, also shows with a target or on hover. "
        .. "The action bars fade while you've been on the move for a few seconds out of combat.",
})

local FADE_TIME = 0.2   -- seconds for a full fade
local POLL = 0.1        -- seconds between cursor checks
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }
local MOVING_ALPHA = 0.2    -- action bars while travelling
local MOVING_DELAY = 6.0    -- seconds of moving before they fade
local AFTER_COMBAT = 10.0   -- seconds after a fight before moving counts
local STILL_DELAY = 3.0     -- seconds standing still before they come back
local MOVING_FADE_OUT = 1.0 -- seconds for the fade out
local MOVING_FADE_IN = 0.8  -- and back in (combat: at once)

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v) if type(v) == "number" and not Secret(v) then return v end end

local editing = false
local alpha, wantedAlpha = 1, 1
local barAlpha, wantedBarAlpha = 1, 1
local movingSince, stillSince, combatAt
local settingAlpha = false
local driver = CreateFrame("Frame")
local elapsedPoll = 0

---------------------------------------------------------------------------
-- Cursor over a spot
---------------------------------------------------------------------------
local function CursorIn(rect)
    if not rect then return false end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    return x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4]
end

-- A frame's rectangle in UIParent coordinates, or nil.
local function RectOf(frame)
    local l, b, w, h = frame:GetRect()
    l, b, w, h = Plain(l), Plain(b), Plain(w), Plain(h)
    if not (l and b and w and h) then return nil end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return { l * s, b * s, (l + w) * s, (b + h) * s }
end

local function InCombat()
    return UnitAffectingCombat("player") or InCombatLockdown()
end

---------------------------------------------------------------------------
-- Player frame
---------------------------------------------------------------------------
local function SetFrameAlpha(value)
    alpha = value
    settingAlpha = true
    PlayerFrame:SetAlpha(value)
    settingAlpha = false
end

local function PlayerWanted()
    return editing or InCombat() or UnitExists("target") or CursorIn(RectOf(PlayerFrame))
end

---------------------------------------------------------------------------
-- Cooldown Manager (only bars set to "in combat" in Edit Mode)
---------------------------------------------------------------------------
local viewerRects = {}   -- [viewer] = rect from when it last showed
local shownByUs = {}     -- [viewer] = true while we show it out of combat

local function InCombatOnly(viewer)
    local setting = Enum.CooldownViewerVisibleSetting
    return setting and viewer.visibleSetting == setting.InCombat
end

local function ViewerEnabled()
    local on = C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled")
    return on ~= false
end

local function UpdateViewer(viewer)
    if editing or not InCombatOnly(viewer) then
        shownByUs[viewer] = nil
        return
    end
    -- Its spot (a hidden frame may not report one: the last known spot stays).
    viewerRects[viewer] = RectOf(viewer) or viewerRects[viewer]
    if InCombat() then
        shownByUs[viewer] = nil -- Blizzard shows it now
        return
    end
    local wanted = ViewerEnabled() and (UnitExists("target") or CursorIn(viewerRects[viewer]))
    if wanted and not viewer:IsShown() then
        shownByUs[viewer] = true
        viewer:Show()
    elseif not wanted and shownByUs[viewer] then
        shownByUs[viewer] = nil
        viewer:Hide()
    end
end

local function UpdateViewers()
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer then UpdateViewer(viewer) end
    end
end

---------------------------------------------------------------------------
-- Action bars while turning the camera
---------------------------------------------------------------------------
local function SetBarsAlpha(value)
    barAlpha = value
    for _, name in ipairs(BARS) do
        local bar = _G[name]
        if bar then bar:SetAlpha(value) end
    end
end

local function BarsWanted()
    local now = GetTime()
    if editing or InCombat() then
        movingSince, stillSince = nil, nil
        if InCombat() then
            combatAt = now
            if barAlpha ~= 1 then SetBarsAlpha(1) end -- at once
        end
        return 1
    end
    if IsPlayerMoving() then
        movingSince, stillSince = movingSince or now, nil
    else
        stillSince = stillSince or now
        if now - stillSince >= STILL_DELAY then movingSince = nil end
    end
    if not movingSince then return 1 end
    local from = math.max(movingSince, combatAt and combatAt + AFTER_COMBAT or 0)
    return now - from >= MOVING_DELAY and MOVING_ALPHA or 1
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
local function Update()
    wantedAlpha = PlayerWanted() and 1 or 0
    wantedBarAlpha = BarsWanted()
    UpdateViewers()
end

local function Step(current, wanted, elapsed, fadeOutTime, fadeInTime)
    local step = elapsed / ((wanted < current and fadeOutTime) or fadeInTime or FADE_TIME)
    return wanted > current and math.min(wanted, current + step) or math.max(wanted, current - step)
end

driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedPoll = elapsedPoll + elapsed
    if elapsedPoll >= POLL then
        elapsedPoll = 0
        Update()
    end
    if alpha ~= wantedAlpha then SetFrameAlpha(Step(alpha, wantedAlpha, elapsed)) end
    if barAlpha ~= wantedBarAlpha then SetBarsAlpha(Step(barAlpha, wantedBarAlpha, elapsed, MOVING_FADE_OUT, MOVING_FADE_IN)) end
end)

function M:OnEnable()
    if not PlayerFrame then return end
    -- Blizzard (vehicles, Edit Mode) sets the frame's alpha back: ours stands.
    hooksecurefunc(PlayerFrame, "SetAlpha", function(self, value)
        if not settingAlpha and not editing and value ~= alpha then
            settingAlpha = true
            self:SetAlpha(alpha)
            settingAlpha = false
        end
    end)
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer and type(viewer.UpdateShownState) == "function" then
            hooksecurefunc(viewer, "UpdateShownState", function(self) ns.safecall(UpdateViewer, self) end)
        end
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function()
            editing = true
            wipe(shownByUs)
            wantedAlpha = 1
            SetFrameAlpha(1)
        end)
        EditModeManagerFrame:HookScript("OnHide", function()
            editing = false
            Update()
        end)
    end
    -- Instant changes for target and combat (the poll covers hovering).
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        ns:On(event, Update)
    end
    wantedAlpha = PlayerWanted() and 1 or 0
    SetFrameAlpha(wantedAlpha)
end
