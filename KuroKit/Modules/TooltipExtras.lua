-- TooltipExtras: extra information and colours on the default tooltip.
--
-- Everything is added through TooltipDataProcessor post-calls: Blizzard runs
-- addon post-calls through a secure attribute delegate, isolated from its own
-- tooltip code, and before the tooltip's Show(), so added lines are sized in.
-- Additions go *inside* the tooltip (lines, inline icons), so the tooltip's own
-- size -- and with it the cursor anchor (Tooltip module) -- always accounts for them.
--
-- Safety on the 12.x client:
--  * Auras (buffs, mount) are read only while the game allows it: not in combat,
--    C_Secrets.ShouldAurasBeSecret() false, and a protected probe call succeeds;
--    every read is pcall'd and secret values are skipped. Otherwise those lines
--    are simply left out.
--  * Other values that can be secret (unit tokens, names, line text) are checked
--    with issecretvalue before use.
--  * Spec needs talent data of other players: one inspect at a time, throttled,
--    out of combat, in inspect range, never while the inspect window is open,
--    cached per player for a few minutes. Your own talents need no inspect.
local _, ns = ...

local M = ns:NewModule("TooltipExtras", {
    title = "Tooltip Extras",
    group = "Interface",
    desc = "Extra information and colours on tooltips: class, faction, level and guild colours, item quality border, target, guild rank, spec and role, mount, buffs and stack size.",
})

-- The per-extra checkboxes are gone (all always on). Drop their stored values.
function M:OnLoad()
    for _, key in ipairs({ "className", "classBorder", "qualityBorder", "target", "levelColor", "factionColors",
        "guildColor", "guildRank", "spec", "mount", "buffs", "maxStack" }) do
        self.db[key] = nil
    end
end

local INSPECT_CONFIG_ID = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1
local INSPECT_THROTTLE = 1.5   -- seconds between our inspect requests
local CACHE_SECONDS = 300      -- how long a player's spec stays cached

local QUESTIE_WAIT = 60 -- seconds to wait for Questie's start before adding the last lines anyway

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v)
    if v == nil or Secret(v) then return nil end
    return v
end

local function ClassColor(unit)
    local _, classFile = UnitClass(unit)
    classFile = Plain(classFile)
    return classFile and C_ClassColor.GetClassColor(classFile)
end

local function LeftLine(tooltip, i)
    return _G[tooltip:GetName() .. "TextLeft" .. i]
end

---------------------------------------------------------------------------
-- Borders: coloured per tooltip, back to the default whenever cleared/hidden.
---------------------------------------------------------------------------
local defaultBorder = {} -- [tooltip] = { r, g, b, a }
local tinted = {}        -- [tooltip] = true while we coloured it

local function TintBorder(tooltip, r, g, b)
    if not tooltip.NineSlice then return end
    tooltip.NineSlice:SetBorderColor(r, g, b, 1)
    tinted[tooltip] = true
end

local function ResetBorder(tooltip)
    if not tinted[tooltip] then return end
    tinted[tooltip] = nil
    local c = defaultBorder[tooltip]
    if c then tooltip.NineSlice:SetBorderColor(c[1], c[2], c[3], c[4]) end
end

local function WatchBorder(tooltip)
    if not (tooltip and tooltip.NineSlice) or defaultBorder[tooltip] then return end
    defaultBorder[tooltip] = { tooltip.NineSlice:GetBorderColor() }
    tooltip:HookScript("OnTooltipCleared", ResetBorder)
    tooltip:HookScript("OnHide", ResetBorder)
end

---------------------------------------------------------------------------
-- Spec and role (Forever: one talent tree, the three classic trees side by
-- side; a node's posX tells which tree it belongs to).
---------------------------------------------------------------------------
local TREE_NAMES = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral", "Restoration" },
}
-- Role per main tree; classes not listed are always DPS. Feral counts as DPS
-- unless the group-finder role says tank.
local TREE_ROLES = {
    WARRIOR = { "DAMAGER", "DAMAGER", "TANK" },
    PALADIN = { "HEALER", "TANK", "DAMAGER" },
    PRIEST = { "HEALER", "HEALER", "DAMAGER" },
    SHAMAN = { "DAMAGER", "DAMAGER", "HEALER" },
    DRUID = { "DAMAGER", "DAMAGER", "HEALER" },
}
local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

local treeOfNode = {} -- [nodeID] = 1..3 (layout never changes)

local function TreeForX(x)
    if type(x) ~= "number" or Secret(x) then return nil end
    if x < 4000 then return 1 elseif x < 8000 then return 2 end
    return 3
end

-- Points spent per tree for a talent config, or nil if unreadable.
local function TreePoints(configID)
    if not (configID and C_Traits and C_Traits.GetConfigInfo) then return nil end
    local ok, config = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or type(config) ~= "table" or not config.treeIDs then return nil end
    local points, any = { 0, 0, 0 }, false
    for _, treeID in ipairs(config.treeIDs) do
        local okN, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if okN and nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local okI, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if okI and type(node) == "table" and node.ID and node.ID ~= 0 then
                    any = true
                    local tree = treeOfNode[nodeID]
                    if not tree then
                        tree = TreeForX(node.posX)
                        treeOfNode[nodeID] = tree
                    end
                    local spent = Plain(node.ranksPurchased) or 0
                    if tree and type(spent) == "number" then points[tree] = points[tree] + spent end
                end
            end
        end
    end
    return any and points or nil
end

-- { text = "Shadow (5/0/46)", tree = 3 } or nil
local function SpecFromPoints(classFile, points)
    local names = classFile and TREE_NAMES[classFile]
    if not (names and points) then return nil end
    local best = 1
    for i = 2, 3 do
        if points[i] > points[best] then best = i end
    end
    if points[best] == 0 then return nil end
    return { text = ("%s (%d/%d/%d)"):format(names[best], points[1], points[2], points[3]), tree = best }
end

local function RoleFor(unit, classFile, spec)
    local assigned = Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit))
    if assigned and ROLE_TEXT[assigned] then return assigned end
    local roles = classFile and TREE_ROLES[classFile]
    if roles and spec then return roles[spec.tree] end
    if classFile and TREE_NAMES[classFile] and not TREE_ROLES[classFile] then return "DAMAGER" end
    return nil
end

local specCache = {}     -- [guid] = { spec = {...} or false, time = t }
local pendingGUID, lastRequest = nil, 0

local function CachedSpec(guid)
    local entry = specCache[guid]
    if entry and GetTime() - entry.time < CACHE_SECONDS then return entry end
end

local INSPECT_TIMEOUT = 5      -- a request that never answered stops blocking after this

local function RequestInspect(unit, guid)
    if pendingGUID and GetTime() - lastRequest > INSPECT_TIMEOUT then pendingGUID = nil end
    if pendingGUID or InCombatLockdown() then return end
    if GetTime() - lastRequest < INSPECT_THROTTLE then return end
    if InspectFrame and InspectFrame:IsShown() then return end -- the user is inspecting someone
    local okC, can = pcall(CanInspect, unit)
    local okR, inRange = pcall(CheckInteractDistance, unit, 1)
    if not (okC and can and okR and inRange) then return end
    pendingGUID, lastRequest = guid, GetTime()
    NotifyInspect(unit)
end

local function OnInspectReady(_, guid)
    if guid ~= pendingGUID then return end
    pendingGUID = nil
    local unit = "mouseover"
    local classFile
    if Plain(UnitGUID(unit)) == guid then
        classFile = Plain(select(2, UnitClass(unit)))
    else
        classFile = Plain(select(2, GetPlayerInfoByGUID(guid)))
    end
    specCache[guid] = { spec = SpecFromPoints(classFile, TreePoints(INSPECT_CONFIG_ID)) or false, time = GetTime() }
    if not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
    -- Still showing that player? Rebuild the tooltip so the spec line appears.
    for _, tooltip in ipairs({ GameTooltip, ns.targetTooltip }) do
        if tooltip:IsShown() then
            local _, ttUnit = tooltip:GetUnit()
            if ttUnit and not Secret(ttUnit) and Plain(UnitGUID(ttUnit)) == guid then tooltip:RefreshData() end
        end
    end
end

local function AddSpecLine(tooltip, unit)
    local _, classFile = UnitClass(unit)
    classFile = Plain(classFile)
    local spec
    if UnitIsUnit(unit, "player") then
        local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
        spec = SpecFromPoints(classFile, TreePoints(ok and configID or nil))
    else
        local guid = Plain(UnitGUID(unit))
        if not guid then return end
        local entry = CachedSpec(guid)
        if entry then
            spec = entry.spec or nil
        else
            RequestInspect(unit, guid)
        end
    end
    local role = RoleFor(unit, classFile, spec)
    if not (spec or role) then return end
    local right = ""
    if role then
        local atlas = ROLE_ATLAS[role]
        local icon = atlas and C_Texture.GetAtlasInfo(atlas) and ("|A:" .. atlas .. ":14:14|a ") or ""
        right = icon .. ROLE_TEXT[role]
    end
    local color = ClassColor(unit)
    local r, g, b = 1, 1, 1
    if color then r, g, b = color:GetRGB() end
    tooltip:AddDoubleLine(spec and spec.text or " ", right, r, g, b, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Buffs and mount (one aura pass)
---------------------------------------------------------------------------
local MAX_BUFF_ICONS, ICONS_PER_ROW, ICON_SIZE = 16, 8, 16
local BUFF_GAP = 10 -- extra pixels between the text and the first row of buff icons
local icons = {} -- reused

-- Extra space under the tooltip's current last line. Inline images don't
-- stretch a line, but a texture added with AddTexture does: the line becomes as
-- tall as the texture plus its margins. An invisible 1px spacer at the line's
-- top-left with a bottom margin of (text height + gap) leaves the text where it
-- is and adds `gap` pixels below it (the -1 right margin cancels its width).
local function AddGapBelowLastLine(tooltip, gap)
    local line = LeftLine(tooltip, tooltip:NumLines())
    local textHeight = line and Plain(line:GetStringHeight()) or 12
    tooltip:AddTexture("Interface\\Common\\spacer", {
        width = 1, height = 1,
        anchor = Enum.TooltipTextureAnchor.LeftTop,
        margin = { left = 0, right = -1, top = 0, bottom = math.ceil(textHeight) + gap - 1 },
    })
end

local function AurasReadable()
    if InCombatLockdown() then return false end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
    return (pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL"))
end

local function AddAuraLines(tooltip, unit)
    local wantMount = C_MountJournal and C_MountJournal.GetMountFromSpell
    wipe(icons)
    local mountName
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not aura then break end
        local icon, spellID = Plain(aura.icon), Plain(aura.spellId)
        if wantMount and not mountName and spellID then
            local mountID = Plain(C_MountJournal.GetMountFromSpell(spellID))
            if mountID and mountID > 0 then
                mountName = Plain((C_MountJournal.GetMountInfoByID(mountID))) or Plain(aura.name)
            end
        end
        if icon and #icons < MAX_BUFF_ICONS then
            icons[#icons + 1] = ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(icon, ICON_SIZE, ICON_SIZE)
        end
    end
    if mountName then
        tooltip:AddLine(("|cffffd100Mount:|r %s"):format(mountName), 1, 1, 1)
    end
    if #icons > 0 then AddGapBelowLastLine(tooltip, BUFF_GAP) end
    for first = 1, #icons, ICONS_PER_ROW do
        tooltip:AddLine(table.concat(icons, " ", first, math.min(first + ICONS_PER_ROW - 1, #icons)))
    end
end

---------------------------------------------------------------------------
-- Target and guild rank
---------------------------------------------------------------------------
local function AddTargetLine(tooltip, unit)
    local target = unit .. "target"
    if not UnitExists(target) then return end
    local text
    if UnitIsUnit(target, "player") then
        text = "|cffff4040You|r"
    else
        local name = ns.UnitFullName(target)
        if not name then return end
        local color = UnitIsPlayer(target) and ClassColor(target)
        text = color and color:WrapTextInColorCode(name) or name
    end
    tooltip:AddLine("|cffffd100Target:|r " .. text, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Colours on the default lines: class line, level number, race, faction.
-- Lines are recognised by their text (localised names from the unit API);
-- only parts of a line get a colour code, the rest keeps Blizzard's colour.
---------------------------------------------------------------------------
local function Hex(r, g, b)
    return ("ff%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

local FACTION_COLOR = {} -- [englishFaction] = { r, g, b, hex }
do
    local colors = PLAYER_FACTION_COLORS
    local function Set(key, color, r, g, b)
        if type(color) == "table" and color.GetRGB then r, g, b = color:GetRGB() end
        FACTION_COLOR[key] = { r, g, b, Hex(r, g, b) }
    end
    Set("Horde", colors and colors[0], 0.90, 0.05, 0.07)
    Set("Alliance", colors and colors[1], 0.29, 0.33, 0.91)
end

-- Colour the first plain occurrence of word (from init on).
local function Splice(text, word, hex, init)
    local s, e = text:find(word, init or 1, true)
    if not s then return text end
    return text:sub(1, s - 1) .. "|c" .. hex .. word .. "|r" .. text:sub(e + 1)
end

local function LevelHex(level)
    if level <= 0 then -- "??": far above you
        local c = QuestDifficultyColors and QuestDifficultyColors.impossible
        return c and Hex(c.r, c.g, c.b) or "ffff1919"
    end
    if not GetCreatureDifficultyColor then return nil end
    local ok, c = pcall(GetCreatureDifficultyColor, level)
    return ok and type(c) == "table" and c.r and Hex(c.r, c.g, c.b) or nil
end

local function ColorLines(tooltip, unit, isPlayer)
    local className = isPlayer and Plain((UnitClass(unit)))
    local classColor = className and ClassColor(unit)
    local race = isPlayer and Plain((UnitRace(unit)))
    local group, factionName = UnitFactionGroup(unit)
    local faction = FACTION_COLOR[Plain(group) or ""]
    factionName = Plain(factionName)
    local level = Plain(UnitLevel(unit))
    local levelHex = type(level) == "number" and LevelHex(level)
    local levelText = levelHex and (level > 0 and tostring(level) or "??")
    local levelLabel = LEVEL
    local levelDone = not levelLabel

    for i = 2, tooltip:NumLines() do
        local line = LeftLine(tooltip, i)
        local text = line and line:GetText()
        if text and not Secret(text) then
            if classColor and text == className then
                line:SetTextColor(classColor:GetRGB())
            elseif faction and factionName and text == factionName then
                line:SetTextColor(faction[1], faction[2], faction[3])
            elseif not levelDone then
                local at = text:find(levelLabel, 1, true)
                if at then
                    levelDone = true
                    local new = text
                    if levelText then new = Splice(new, levelText, levelHex, at) end
                    if race and faction then new = Splice(new, race, faction[4]) end
                    if classColor then new = Splice(new, className, classColor:GenerateHexColor()) end
                    if new ~= text then line:SetText(new) end
                end
            end
        end
    end
end

-- Guild line: guild name in green (brighter for your own guild), rank in grey.
local GUILD_HEX, MY_GUILD_HEX = "ff8fd18f", "ff40ff40"

local function GuildLine(tooltip, unit)
    local guild, rank = GetGuildInfo(unit)
    guild, rank = Plain(guild), Plain(rank)
    if not guild or guild == "" then return end
    for i = 2, tooltip:NumLines() do
        local line = LeftLine(tooltip, i)
        local text = line and line:GetText()
        if text and not Secret(text) and text:find(guild, 1, true) then
            local new = text
            local mine = UnitIsInMyGuild and Plain(UnitIsInMyGuild(unit))
            new = Splice(new, guild, mine and MY_GUILD_HEX or GUILD_HEX)
            if rank and rank ~= "" then
                new = ("%s |cffb0b0b0(%s)|r"):format(new, rank)
            end
            if new ~= text then line:SetText(new) end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Post-calls
---------------------------------------------------------------------------
local function OnUnitTooltip(tooltip)
    if (tooltip ~= GameTooltip and tooltip ~= ns.targetTooltip) or tooltip:IsForbidden() then return end
    WatchBorder(tooltip) -- the controller target tooltip is created later
    local _, unit = tooltip:GetUnit()
    if not unit or Secret(unit) then return end

    if UnitIsPlayer(unit) then
        local color = ClassColor(unit)
        if color then
            local line = LeftLine(tooltip, 1)
            if line then line:SetTextColor(color:GetRGB()) end
            TintBorder(tooltip, color:GetRGB())
        end
        ColorLines(tooltip, unit, true)
        GuildLine(tooltip, unit)
        AddSpecLine(tooltip, unit)
    else
        ColorLines(tooltip, unit, false)
    end
end

-- The target line and buff icons go last: after other addons' unit lines too
-- (Questie's quest objectives), see M:OnEnable.
local function OnUnitTooltipEnd(tooltip)
    if (tooltip ~= GameTooltip and tooltip ~= ns.targetTooltip) or tooltip:IsForbidden() then return end
    local _, unit = tooltip:GetUnit()
    if not unit or Secret(unit) then return end
    AddTargetLine(tooltip, unit)
    if UnitIsPlayer(unit) and AurasReadable() then AddAuraLines(tooltip, unit) end
end

local function OnItemTooltip(tooltip, data)
    if tooltip:IsForbidden() or not defaultBorder[tooltip] then return end
    local _, link = tooltip:GetItem()
    local item = Plain(link) or (data and Plain(data.id))
    if not item then return end
    local _, _, quality, _, _, _, _, stackCount = C_Item.GetItemInfo(item)
    if quality and quality >= 2 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then TintBorder(tooltip, r, g, b) end
    end
    if stackCount and stackCount > 1 then
        tooltip:AddLine(("Stacks to %d"):format(stackCount), 0.6, 0.6, 0.6)
    end
end

function M:OnEnable()
    WatchBorder(GameTooltip)
    WatchBorder(ItemRefTooltip)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        ns.safecall(OnUnitTooltip, tooltip)
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        ns.safecall(OnItemTooltip, tooltip, data)
    end)
    ns:On("INSPECT_READY", OnInspectReady)

    -- Post-calls run in the order they were added. Questie adds its quest
    -- lines once it has started (after login), so with Questie the target
    -- line and buffs are added once Questie says it's ready, to come after
    -- its lines (or after QUESTIE_WAIT seconds, should it never get there).
    local added = false
    local function AddEnd()
        if added then return end
        added = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            ns.safecall(OnUnitTooltipEnd, tooltip)
        end)
    end
    local questie = Questie and Questie.API
    if questie and type(questie.RegisterOnReady) == "function" then
        questie.RegisterOnReady(AddEnd)
        C_Timer.After(QUESTIE_WAIT, AddEnd)
    else
        AddEnd()
    end
end
