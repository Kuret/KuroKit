-- TargetTooltip: while you play with the controller, the tooltip of what you're
-- aiming at stays in the default tooltip spot (the hidden cursor never hovers
-- anything, so no tooltip would appear otherwise).
--
-- What it shows, first match wins:
--   your target (what your abilities hit) > the enemy you aim at (soft target)
--   > an NPC or object you can interact with > a friendly unit you aim at
--   > a dead enemy (to loot / skin).
-- Objects (herbs, ore, chests) aren't units: the game only gives their name, so
-- their tooltip is just the name. Soft targets need the game's soft targeting
-- (Options > Combat); with it off only your target shows.
--
-- Only while on the controller (Core/Input.lua): mouse/keyboard play keeps
-- normal hover tooltips. One tooltip at a time: it waits while the game's own
-- GameTooltip shows and takes over when that hides. When the game's tooltip
-- fades out on the same unit, ours takes over at once in the same spot.
-- Event-driven (target and soft-target events), no per-frame work.
local _, ns = ...

local M = ns:NewModule("TargetTooltip", {
    title = "Controller Target Tooltip",
    group = "Interface",
    desc = "While you use a controller, the tooltip of your target, or of what you aim at (soft targeting), "
        .. "stays in the default tooltip spot as long as you target or aim at it. Hidden again as soon as you use the mouse or keyboard.",
})

-- "duration" used to be an option; now always "as long as you target it".
function M:OnLoad()
    self.db.duration = nil
end

local tip
local shownKey           -- what's shown: unit token | kind | GUID (when not secret)
local aimChanged = false -- an event said the aim changed (needed when GUIDs are secret)

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v) if Secret(v) then return nil end return v end
local function Has(unit) return Plain(UnitExists(unit)) and true or false end
local function Dead(unit) return Plain(UnitIsDead(unit)) and true or false end

-- unit token, and true when it's an object rather than a unit
local function Pick()
    if Has("target") then return "target" end
    if Has("softenemy") and not Dead("softenemy") then return "softenemy" end
    if Has("softinteract") then return "softinteract" end
    if type(UnitGUID("softinteract")) ~= "nil" and type(UnitName("softinteract")) ~= "nil" then
        return "softinteract", true
    end
    if Has("softfriend") then return "softfriend" end
    if Has("softenemy") then return "softenemy" end -- dead
end

local function Show(unit, isObject)
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    if isObject then
        tip:SetText(UnitName(unit), 1, 1, 1) -- may be secret: the game accepts that here
        tip:Show()
    else
        tip:SetUnit(unit)
    end
end

local function Refresh()
    local unit, isObject
    if ns.PadActive() then unit, isObject = Pick() end
    if not unit then
        shownKey, aimChanged = nil, false
        tip:Hide()
        return
    end
    local key = unit .. (isObject and "|object" or "|unit")
    local guid = UnitGUID(unit)
    local known = type(guid) == "string" and not Secret(guid)
    if known then key = key .. "|" .. guid end
    if key ~= shownKey or (aimChanged and not known) then
        shownKey = key
        tip:Hide()
    end
    aimChanged = false
    if GameTooltip:IsShown() then
        tip:Hide()
        return
    end
    if not tip:IsShown() then Show(unit, isObject) end
end

local function AimChanged()
    aimChanged = true
    Refresh()
end

-- The game's tooltip is fading out on the unit we'd show: take over at once.
local function OnGameTooltipFade(self)
    if self ~= GameTooltip or not ns.PadActive() then return end
    local _, ttUnit = self:GetUnit()
    local unit, isObject = Pick()
    if ttUnit and not Secret(ttUnit) and unit and not isObject and Plain(UnitIsUnit(ttUnit, unit)) then
        self:Hide() -- OnHide shows ours in the same spot
    end
end

function M:OnSlash()
    local unit, isObject = Pick()
    ns:Print(("On controller: %s (%s); gamepad input enabled: %s; aiming at: %s; tooltip shown: %s"):format(
        ns.PadActive() and "yes" or "no", ns.InputModeReason(),
        GetCVar("GamePadEnable") == "1" and "yes" or "no",
        unit and (unit .. (isObject and " (object)" or "")) or "nothing",
        tip and tip:IsShown() and "yes" or "no"))
end

function M:OnEnable()
    tip = CreateFrame("GameTooltip", "KuroKitTargetTooltip", UIParent, "GameTooltipTemplate")
    ns.targetTooltip = tip -- Tooltip Extras decorates it too
    -- The template's health bar colours itself by comparing health values, which
    -- are secret in combat and error in addon code. Keep its fill, one colour.
    local bar = tip.StatusBar
    if bar then
        bar:SetScript("OnValueChanged", nil)
        bar:SetStatusBarColor(0, 1, 0)
    end

    GameTooltip:HookScript("OnShow", Refresh)
    GameTooltip:HookScript("OnHide", Refresh)
    if GameTooltip.FadeOut then hooksecurefunc(GameTooltip, "FadeOut", OnGameTooltipFade) end
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED",
        "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
        ns:On(event, AimChanged)
    end
    ns.OnInputMode(Refresh)
end
