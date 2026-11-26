-- Arc HUD part: swing timers as thin arcs in the cast arc's style.
-- Blizzard's own swing timer bars (main hand, off hand, ranged: auto shot
-- and wands too) keep the time; each gets an arc on its spot (move the bars
-- in Edit Mode: the arcs follow, at the bars' Edit Mode scale), filling left
-- to right to the next swing. An arc shows only while its swing timer runs
-- (and in Edit Mode): a caster's main hand stays out of sight. Blizzard's
-- bars are faded out (Edit Mode shows them, to move them). The swing timer
-- is a game setting (Options, "Enable Swing Timer"), switched on once; Edit
-- Mode's "Visibility: Hidden" for a bar hides its arc too.
-- How: each bar keeps its swing's end and length in plain fields
-- (swingEndTime, swingDuration; Blizzard_SwingTimer), read per frame while
-- an arc shows.
-- Cost: per frame, a few field reads per bar; a SetValue while one runs.
local _, ns = ...
local A = ns.ArcHUD
local M = A.M
local MEDIA, SCALE, BACK_ALPHA, FILL_ALPHA = A.MEDIA, A.SCALE, A.BACK_ALPHA, A.FILL_ALPHA
local NewBar, Fade, Editing = A.NewBar, A.Fade, A.Editing

-- tools/make_arcs.py SWING_*: the same numbers (canvas, the ring's outer
-- radius, the cast arc's half angle); the fill's columns as for the cast arc.
local SWING_W, SWING_H = 512 * SCALE, 64 * SCALE
local SWING_FILL_LEFT = math.floor(256 - 600 * math.sin(math.rad(17)))
local SWING_FILL_RIGHT = math.ceil(256 + 600 * math.sin(math.rad(17)))
local LINGER = 0.4      -- seconds an arc stays after its timer stops (the next swing restarts it)
local EDIT_FILL = 0.6   -- the arcs' fill in Edit Mode (to see them)
local BARS = {
    { name = "SwingTimerMainHandFrame", color = { 1, 0.82, 0.45 } },
    { name = "SwingTimerOffHandFrame", color = { 0.95, 0.6, 0.3 } },
    { name = "SwingTimerRangedFrame", color = { 0.55, 0.85, 1 } },
}

local arcs = {}            -- { frame, bar, blizz, alpha, wanted, holdUntil, scale }
local settingAlpha = false

-- Blizzard's bar out of sight: alpha 0 except in Edit Mode, where it shows
-- at its own opacity (kept from its SetAlpha calls).
local function ApplyBlizzAlpha(arc)
    settingAlpha = true
    arc.blizz:SetAlpha(Editing() and arc.base or 0)
    settingAlpha = false
end

local function NewArc(spec, blizz)
    local frame = CreateFrame("Frame", nil, A.hud)
    frame:SetSize(SWING_W, SWING_H)
    frame:SetPoint("CENTER", blizz, "CENTER")
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetAlpha(BACK_ALPHA)
    back:SetTexture(MEDIA .. "ArcSwingBack")
    local cols = CreateFrame("Frame", nil, frame)
    cols:SetPoint("TOPLEFT", frame, "TOPLEFT", SWING_FILL_LEFT * SCALE, 0)
    cols:SetSize((SWING_FILL_RIGHT - SWING_FILL_LEFT) * SCALE, SWING_H)
    local bar = NewBar(cols, MEDIA .. "ArcSwingFill", "HORIZONTAL")
    bar:SetStatusBarColor(spec.color[1], spec.color[2], spec.color[3])
    bar:SetAlpha(FILL_ALPHA)
    frame:SetAlpha(0)
    local arc = { frame = frame, bar = bar, blizz = blizz, alpha = 0, wanted = 0, base = blizz:GetAlpha() }
    hooksecurefunc(blizz, "SetAlpha", function(_, alpha)
        if settingAlpha then return end
        arc.base = alpha
        ApplyBlizzAlpha(arc)
    end)
    ApplyBlizzAlpha(arc)
    return arc
end

local function UpdateArc(arc, elapsed)
    local blizz = arc.blizz
    local value
    if blizz.isInEditMode and blizz:IsShown() then
        value = EDIT_FILL
    elseif blizz:IsShown() and blizz.swingEndTime and blizz.swingDuration and blizz.swingDuration > 0 then
        value = 1 - (blizz.swingEndTime - GetTime()) / blizz.swingDuration
    end
    if value then
        arc.wanted = 1
        arc.holdUntil = GetTime() + LINGER
        arc.bar:SetValue(math.max(0, math.min(1, value)))
        local scale = blizz:GetScale()
        if scale ~= arc.scale then
            arc.scale = scale
            arc.frame:SetScale(scale)
        end
    elseif arc.alpha == 0 then
        return
    end
    Fade(arc, elapsed)
end

A.AddPart({
    Build = function()
        for _, spec in ipairs(BARS) do
            local blizz = _G[spec.name]
            if blizz then arcs[#arcs + 1] = NewArc(spec, blizz) end
        end
    end,
    Update = function(elapsed)
        for _, arc in ipairs(arcs) do UpdateArc(arc, elapsed) end
    end,
    Enable = function()
        if #arcs == 0 then return end
        if not M.db.swingTimerSeeded then
            M.db.swingTimerSeeded = true
            if GetCVar("showSwingTimer") ~= nil then SetCVar("showSwingTimer", "1") end
        end
        if EditModeManagerFrame then
            local function Again()
                for _, arc in ipairs(arcs) do ApplyBlizzAlpha(arc) end
            end
            EditModeManagerFrame:HookScript("OnShow", Again)
            EditModeManagerFrame:HookScript("OnHide", Again)
        end
    end,
})
