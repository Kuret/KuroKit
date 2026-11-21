-- Settings page: Settings > AddOns > KuroKit. One canvas page with tabs across
-- the top (one per group); each tab lists its modules as sections: title,
-- description and the module's options, with an on/off checkbox in front of the title. Built from Blizzard's
-- own templates (settings tabs/checkboxes, menu dropdowns, stepper sliders) so it
-- looks native. The page is built the first time it's opened, so it costs
-- nothing at login; values refresh every time it's shown.
--
-- A module declares (see Core.lua NewModule):
--   group = "Interface"          -- tab; default "General"
--   alwaysOn = true              -- no on/off checkbox (pure settings module)
--   options = {
--     { type = "header",   name = "Sub-section" },
--     { type = "checkbox", key = "repair", name = "Auto repair", tooltip = "...", reload = true },
--     { type = "slider",   key = "size", name = "Size", min = 1, max = 10, step = 1, format = fn(value) -> text },
--     { type = "dropdown", key = "mode", name = "Mode", values = { { value, "Label", "tooltip" }, ... } },
--     { type = "button",   name = "Row label", text = "Button text", onClick = fn },
--   }
-- Instead of `key` (a value in M.db), a row can pass get = fn(), set = fn(value),
-- default = v to control something stored elsewhere (a CVar, for example).
-- `reload = true`: changing it shows the "reload needed" bar.
-- After a change, M:OnOptionChanged(key, value) runs if the module is enabled.
--
-- Dependent options: prefer one dropdown for "on, and if so how" choices.
local ADDON, ns = ...

local GROUPS = { "General", "Interface", "Chat & Map", "Gameplay", "Developer" }

local HEADER_H = 64        -- title + tabs + divider
local FOOTER_H = 36        -- reload bar
local PAD = 20             -- left padding of rows
local SECTION_GAP = 20

local panel, category
local refreshers = {}      -- functions that reload widget values from their getters
local loginState = {}      -- module enabled state when the UI loaded
local reloadReasons = {}   -- [id] = true while a change needs /reload
local reloadBar

---------------------------------------------------------------------------
-- Reload bar
---------------------------------------------------------------------------
local function UpdateReloadBar()
    if not reloadBar then return end
    reloadBar:SetShown(next(reloadReasons) ~= nil)
end

local function SetNeedsReload(id, needed)
    reloadReasons[id] = needed or nil
    UpdateReloadBar()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Same tooltip as Blizzard's own settings rows.
local function ShowRowTooltip(owner, title, text)
    if not text or text == "" then return end
    SettingsTooltip:SetOwner(owner, "ANCHOR_RIGHT", -10, 0)
    Settings.InitTooltip(title, text)
    SettingsTooltip:Show()
end

local function HideRowTooltip()
    SettingsTooltip:Hide()
end

-- A row: label on the left, control from the middle; hovering shows the tooltip.
local function NewRow(parent, y, width, height, label, tooltip)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(width, height)
    row:EnableMouse(true)
    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetPoint("LEFT", PAD + 16, 0)
    row.Label:SetPoint("RIGHT", row, "CENTER", -90, 0)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetWordWrap(false)
    row.Label:SetText(label or "")
    row:SetScript("OnEnter", function(self) ShowRowTooltip(self, label, tooltip) end)
    row:SetScript("OnLeave", HideRowTooltip)
    row.controlX = width / 2 - 80
    return row
end

local function HookTooltip(control, row, label, tooltip)
    control:HookScript("OnEnter", function() ShowRowTooltip(row, label, tooltip) end)
    control:HookScript("OnLeave", HideRowTooltip)
end

local function Accessors(m, row)
    if row.get then return row.get, row.set end
    return function() return m.db[row.key] end, function(value) m.db[row.key] = value end
end

local function AfterChange(m, row, value, id)
    if row.reload then
        SetNeedsReload(id, value ~= row._loginValue)
    end
    if m.OnOptionChanged and m.enabled then
        ns.safecall(m.OnOptionChanged, m, row.key or row.name, value)
    end
end

local function AddCheckbox(parent, y, width, label, tooltip, get, set)
    local row = NewRow(parent, y, width, 30, label, tooltip)
    local box = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
    box:SetPoint("LEFT", row, "LEFT", row.controlX, 0)
    box:SetChecked(get() and true or false)
    box:SetScript("OnClick", function(self)
        local on = self:GetChecked()
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.safecall(set, on)
    end)
    if tooltip then -- the template shows SettingsTooltip on hover itself
        box:SetTooltipFunc(function() Settings.InitTooltip(label, tooltip) end)
    end
    refreshers[#refreshers + 1] = function() box:SetChecked(get() and true or false) end
    return 30
end

local function AddDropdown(parent, y, width, label, tooltip, values, get, set)
    local row = NewRow(parent, y, width, 32, label, tooltip)
    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", row, "LEFT", row.controlX, 0)
    dropdown:SetWidth(220)
    dropdown:SetupMenu(function(_, root)
        for _, v in ipairs(values) do
            local value, text, tip = v[1], v[2], v[3]
            local radio = root:CreateRadio(text,
                function() return get() == value end,
                function() ns.safecall(set, value) end)
            if tip and radio.SetTooltip then
                radio:SetTooltip(function(tt)
                    GameTooltip_SetTitle(tt, text)
                    GameTooltip_AddNormalLine(tt, tip, true)
                end)
            end
        end
    end)
    HookTooltip(dropdown, row, label, tooltip)
    refreshers[#refreshers + 1] = function() dropdown:GenerateMenu() end
    return 32
end

local function AddSlider(parent, y, width, label, tooltip, row_, get, set)
    local row = NewRow(parent, y, width, 34, label, tooltip)
    local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "LEFT", row.controlX, 0)
    slider:SetWidth(220)
    local min, max, step = row_.min, row_.max, row_.step or 1
    local format = row_.format or function(v) return tostring(v) end
    local function Snap(v) return min + math.floor((v - min) / step + 0.5) * step end
    slider:Init(get() or min, min, max, math.max(1, math.floor((max - min) / step + 0.5)),
        { [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return format(Snap(v)) end })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
        v = Snap(v)
        if v ~= get() then ns.safecall(set, v) end
    end, slider)
    HookTooltip(slider.Slider, row, label, tooltip)
    refreshers[#refreshers + 1] = function() slider:SetValue(get() or min) end
    return 34
end

local function AddButton(parent, y, width, label, tooltip, text, onClick)
    local row = NewRow(parent, y, width, 30, label, tooltip)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetPoint("LEFT", row, "LEFT", row.controlX, 0)
    button:SetText(text)
    button:SetWidth(math.max(120, button:GetFontString():GetStringWidth() + 40))
    button:SetScript("OnClick", function() ns.safecall(onClick) end)
    HookTooltip(button, row, label, tooltip)
    return 30
end

local function AddSubHeader(parent, y, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", PAD + 16, y - 8)
    fs:SetText(text)
    return 28
end

local function AddOptionRow(m, parent, y, width, row)
    if row.type == "header" then return AddSubHeader(parent, y, row.name) end
    if row.type == "button" then
        return AddButton(parent, y, width, row.name, row.tooltip, row.text, row.onClick)
    end

    local get, rawSet = Accessors(m, row)
    local id = m.name .. "." .. (row.key or row.name)
    row._loginValue = get()
    local function set(value)
        rawSet(value)
        AfterChange(m, row, value, id)
    end
    local tooltip = row.tooltip
    if row.reload then
        tooltip = (tooltip and tooltip .. "\n\n" or "") .. "Takes effect after reloading the UI."
    end

    if row.type == "checkbox" then
        return AddCheckbox(parent, y, width, row.name, tooltip, get, set)
    elseif row.type == "dropdown" then
        return AddDropdown(parent, y, width, row.name, tooltip, row.values, get, set)
    elseif row.type == "slider" then
        return AddSlider(parent, y, width, row.name, tooltip, row, get, set)
    end
    error("unknown option type " .. tostring(row.type) .. " in " .. m.name)
end

-- One module: title, description, Enabled checkbox, options.
local function AddSection(m, parent, y, width)
    local start = y
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetText(m.title)

    -- Frame spanning the whole section (height set at the end). The title
    -- checkbox's hover highlight covers its parent, so this makes it light up
    -- just this section. It ignores the mouse, so the controls inside still work.
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", 0, y + 4)
    section:SetWidth(width)
    section:EnableMouse(false)

    if m.alwaysOn then
        title:SetPoint("TOPLEFT", PAD, y)
    else
        -- On/off checkbox in front of the title.
        local name = m.name
        local box = CreateFrame("CheckButton", nil, section, "SettingsCheckboxTemplate")
        box:SetPoint("LEFT", parent, "TOPLEFT", PAD - 6, y - title:GetStringHeight() / 2)
        title:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box:SetChecked(ns:IsModuleEnabled(name))
        box:SetScript("OnClick", function(self)
            local on = self:GetChecked()
            PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            ns:SetModuleEnabled(name, on)
            SetNeedsReload("enable." .. name, on ~= loginState[name])
        end)
        box:SetTooltipFunc(function()
            Settings.InitTooltip(m.title, "Turn this feature on or off.\n\nTakes effect after reloading the UI.")
        end)
        refreshers[#refreshers + 1] = function() box:SetChecked(ns:IsModuleEnabled(name)) end
    end
    y = y - math.max(title:GetStringHeight(), 22) - 4

    if m.desc ~= "" then
        local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", PAD, y)
        desc:SetWidth(width - PAD * 2)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.75, 0.75, 0.75)
        desc:SetText(m.desc)
        y = y - desc:GetStringHeight() - 6
    end

    for _, row in ipairs(m.options or {}) do
        y = y - AddOptionRow(m, parent, y, width, row)
    end
    section:SetHeight(start - y + 8)
    return start - y
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local tabContents = {} -- [index] = scroll frame (built on first view)

local function ModulesIn(group)
    local list = {}
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        if (m.group or "General") == group then list[#list + 1] = m end
    end
    return list
end

local function BuildTab(group)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -28, FOOTER_H)
    local width = panel:GetWidth() - 28
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(width)
    scroll:SetScrollChild(child)

    local y = -8
    for _, m in ipairs(ModulesIn(group)) do
        y = y - AddSection(m, child, y, width) - SECTION_GAP
    end
    child:SetHeight(-y)
    return scroll
end

local function Build()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText(ADDON)
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 2)
    version:SetText("v" .. ns.version)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)

    -- Tabs, right-aligned like Blizzard's own settings tabs; empty groups hidden.
    local groups, tabs = {}, {}
    for _, group in ipairs(GROUPS) do
        if #ModulesIn(group) > 0 then groups[#groups + 1] = group end
    end
    local previous
    for i = #groups, 1, -1 do
        local tab = CreateFrame("Button", nil, panel, "MinimalTabTemplate")
        tab.Text:SetText(groups[i])
        tab:SetWidth(tab.Text:GetStringWidth() + 40)
        if previous then
            tab:SetPoint("TOPRIGHT", previous, "TOPLEFT", 0, 0)
        else
            tab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -14)
        end
        previous = tab
        tabs[i] = tab
    end

    reloadBar = CreateFrame("Frame", nil, panel)
    reloadBar:SetPoint("BOTTOMLEFT", PAD, 4)
    reloadBar:SetPoint("BOTTOMRIGHT", -PAD, 4)
    reloadBar:SetHeight(28)
    local note = reloadBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    note:SetPoint("LEFT")
    note:SetText("Some changes take effect after reloading the UI.")
    local reload = CreateFrame("Button", nil, reloadBar, "UIPanelButtonTemplate")
    reload:SetPoint("RIGHT")
    reload:SetText(RELOADUI or "Reload UI")
    reload:SetWidth(reload:GetFontString():GetStringWidth() + 40)
    reload:SetScript("OnClick", ReloadUI)
    UpdateReloadBar()

    local tabGroup = CreateRadioButtonGroup()
    tabGroup:AddButtons(tabs)
    tabGroup:RegisterCallback(ButtonGroupBaseMixin.Event.Selected, function(_, _, index)
        for i, content in pairs(tabContents) do content:SetShown(i == index) end
        if not tabContents[index] then
            ns.safecall(function() tabContents[index] = BuildTab(groups[index]) end)
        end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end, panel)
    tabGroup:SelectAtIndex(1)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
function ns:BuildOptions()
    for _, name in ipairs(self.moduleOrder) do
        loginState[name] = self:IsModuleEnabled(name)
    end
    panel = CreateFrame("Frame")
    panel:Hide()
    panel:SetScript("OnShow", function()
        if not panel.built then
            panel.built = true
            ns.safecall(Build)
        end
        for i = 1, #refreshers do ns.safecall(refreshers[i]) end
    end)
    category = Settings.RegisterCanvasLayoutCategory(panel, ADDON)
    Settings.RegisterAddOnCategory(category)
end

function ns:OpenOptions()
    if category then Settings.OpenToCategory(category:GetID()) end
end

-- Addon compartment (the minimap's addon menu) entry; see the TOC.
function KuroKit_OnAddonCompartmentClick()
    ns:OpenOptions()
end
