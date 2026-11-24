-- Action bars: a button's icon turns red while its spell is out of range of
-- your target (Blizzard only reddens the keybind). Out of mana (blue) and
-- unusable (grey) stay Blizzard's; range wins over both.
--
-- How: a post-hook on ActionButton_UpdateRangeIndicator, which Blizzard calls
-- with each range change (ACTION_RANGE_CHECK_UPDATE), and on each action
-- button's UpdateUsable (which recolours the icon) to put the red back. Coming
-- back into range recolours the icon as Blizzard does. Only the action bar
-- buttons (ActionBarButtonEventsFrame's list), not the pet bar.
-- Cost: nothing until a range change; then one colour per button.
local _, ns = ...

local M = ns:NewModule("ActionBars", {
    title = "Action Bars",
    group = "Interface",
    desc = "Action button icons turn red while the spell is out of range of your target.",
})

local OUT_OF_RANGE = { 0.85, 0.2, 0.2 }

local buttons = setmetatable({}, { __mode = "k" })     -- our hooked buttons
local outOfRange = setmetatable({}, { __mode = "k" })

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Blizzard's colours (ActionBarActionButtonMixin:UpdateUsable).
local function UsableColor(button)
    local icon = button.icon
    if not (icon and button.action) then return end
    local usable, noMana = C_ActionBar.IsUsableAction(button.action)
    if Secret(usable) or Secret(noMana) then return end
    if usable then
        icon:SetVertexColor(1, 1, 1)
    elseif noMana then
        icon:SetVertexColor(0.5, 0.5, 1)
    else
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

local function Paint(button)
    if outOfRange[button] and button.icon then
        button.icon:SetVertexColor(OUT_OF_RANGE[1], OUT_OF_RANGE[2], OUT_OF_RANGE[3])
    end
end

local function OnRange(button, checksRange, inRange)
    if not buttons[button] or Secret(checksRange) or Secret(inRange) then return end
    local out = (checksRange and not inRange) and true or nil
    if out == outOfRange[button] then return end
    outOfRange[button] = out
    if out then Paint(button) else UsableColor(button) end
end

local function Hook(button)
    if buttons[button] or type(button) ~= "table" or not button.UpdateUsable then return end
    buttons[button] = true
    hooksecurefunc(button, "UpdateUsable", Paint)
end

function M:OnEnable()
    local registry = ActionBarButtonEventsFrame
    if not registry then return end
    if registry.ForEachFrame then registry:ForEachFrame(Hook) end
    if registry.RegisterFrame then
        hooksecurefunc(registry, "RegisterFrame", function(_, button) Hook(button) end)
    end
    hooksecurefunc("ActionButton_UpdateRangeIndicator", OnRange)
end
