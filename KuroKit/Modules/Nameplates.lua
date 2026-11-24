-- Nameplates: tweaks to Blizzard's default nameplates.
--   friendly players   name only, class colour (Blizzard's own names-only mode)
--                      + guild line under the name; includes the other faction
--                      when not flagged for PvP (attackable ones stay enemies)
--   friendly NPCs      name only (bar and the rest faded out) in NPC colours
--                      + <title> line under the name (e.g. <Innkeeper>)
--   player pets        name only, in a light player-controlled blue
--   size               Blizzard's Medium x PLATE_SCALE, the same at every
--                      distance; targeted plates don't grow (set once)
--   enemies            cast bars with spell name, icon and target, highlighted
--                      when they target you or the cast is important; health
--                      as number and percentage; all of your own debuffs
--   your target        a bobbing arrow above its name
--   threat             enemy plates get the target's selection border in
--                      threat colours while they're on you (red), or you're
--                      about to pull them (yellow / orange); your target
--                      keeps Blizzard's own
--   quest mobs         progress of the quest objective (8/10, or 45%) in a
--                      box left of the health bar, like the level box; item
--                      drops via Polestar's quest data; a class-coloured dot
--                      under it per group member who still needs the mob,
--                      and their count once yours is done
--
-- How (from studying Smart Friendly Nameplates, BetterBlizzPlates and
-- EllesmereUI on this client):
--  * Friendly players use Blizzard's native mode (CVars); Forever has no such
--    mode for NPCs or pets, so their plates get the bar etc. faded with
--    SetAlpha on just those parts (never Hide, never Blizzard's own layout
--    functions, never fields written on Blizzard frames); the alpha is put back
--    when the pooled frame is released or reused for another unit.
--  * One post-hook on CompactUnitFrame_UpdateName (runs after Blizzard sets the
--    name and its colour) re-checks the plate, colours the name and keeps the
--    title line; it leaves non-nameplate frames (raid frames) at once.
--  * Values that can be secret are checked with issecretvalue or only passed to
--    SetFormattedText; the NPC title comes from the unit tooltip, cached per
--    NPC id, skipped when secret.
--  * In dungeons / raids the game locks friendly nameplates against addons, so
--    friendly NPC and pet plates are switched off there (players keep the
--    native mode). Nameplate settings can't change in combat: queued.
-- Cost: per plate update a few unit queries; tooltip read once per NPC id.
-- Quest progress: the unit tooltip's quest lines (and Polestar's index), read
-- when a plate appears and twice after a burst of quest log changes.
local _, ns = ...

local M = ns:NewModule("Nameplates", {
    title = "Nameplates",
    group = "Interface",
    desc = "Friendly players, NPCs and pets show only their name (class colour, NPC colours, pet blue) with the guild or "
        .. "NPC title under it. Enemy cast bars show the spell, icon and target, health shows as percentage (left) and value (right), "
        .. "all your own debuffs show on enemies, and quest mobs show your objective progress next to the health bar.",
})

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v)
    if v == nil or Secret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Game settings
---------------------------------------------------------------------------
local ALWAYS = {
    nameplateShowFriendlyPlayers = "1",
    nameplateShowOnlyNameForFriendlyPlayerUnits = "1",
    nameplateUseClassColorForFriendlyPlayerUnitNames = "1",
    nameplateShowAllPersonalAuras = "1",
}

local PLATE_SCALE = 1.10 -- on top of Medium (1.0); tuned in game

local function SetCVarIf(cvar, value)
    local current = GetCVar(cvar)
    if current ~= nil and current ~= value then SetCVar(cvar, value) end
end

local function SetBit(cvar, index, on)
    if not index or GetCVar(cvar) == nil then return end
    if C_CVar.GetCVarBitfield(cvar, index) ~= on then pcall(C_CVar.SetCVarBitfield, cvar, index, on) end
end

local function ApplyCVars()
    ns:OutOfCombat(function()
        for cvar, value in pairs(ALWAYS) do SetCVarIf(cvar, value) end
        -- Friendly NPC / pet plates only where we can make them names-only.
        local inInstance, kind = IsInInstance()
        local friendly = (inInstance and kind ~= "none") and "0" or "1"
        SetCVarIf("nameplateShowFriendlyNpcs", friendly)
        SetCVarIf("nameplateShowFriendlyPlayerMinions", friendly)
        -- Simplified plates hide the name: never for friendly units.
        local S = Enum.NamePlateSimplifiedType
        if S then
            SetBit("nameplateSimplifiedTypes", S.FriendlyPlayer, false)
            SetBit("nameplateSimplifiedTypes", S.FriendlyNpc, false)
            SetBit("nameplateSimplifiedTypes", S.Minion, false)
        end
        -- Enemy defaults, applied once; after that Blizzard's settings decide.
        if not M.db.enemySeeded then
            M.db.enemySeeded = true
            local C = Enum.NamePlateCastBarDisplay
            if C then
                for _, key in ipairs({ "SpellName", "SpellIcon", "SpellTarget", "HighlightImportantCasts", "HighlightWhenCastTarget" }) do
                    SetBit("nameplateCastBarDisplay", C[key], true)
                end
            end
            SetCVarIf("nameplateShowCastBars", "1")
            if Enum.NamePlateEnemyNpcAuraDisplay then
                SetBit("nameplateEnemyNpcAuraDisplay", Enum.NamePlateEnemyNpcAuraDisplay.Debuffs, true)
            end
            if Enum.NamePlateEnemyPlayerAuraDisplay then
                SetBit("nameplateEnemyPlayerAuraDisplay", Enum.NamePlateEnemyPlayerAuraDisplay.Debuffs, true)
            end
        end
        -- Added later, each applied once: health number + percentage, and
        -- Blizzard's nameplate size one step up (Extra Large).
        if not M.db.healthTextSeeded then
            M.db.healthTextSeeded = true
            local I = Enum.NamePlateInfoDisplay
            if I then
                SetBit("nameplateInfoDisplay", I.CurrentHealthPercent, true)
                SetBit("nameplateInfoDisplay", I.CurrentHealthValue, true)
            end
        end
        -- Size between Blizzard's steps: size Medium and every plate at PLATE_SCALE whatever its distance (normal
        -- and far-away scale equal). With distance scaling, plates beyond 10
        -- yards shrank to 80% while the target / soft target stayed full size,
        -- so looking at a unit made its plate grow. The target / soft-target
        -- scale is an absolute size too: the same value.
        if M.db.scaleVersion ~= 8 then
            M.db.scaleVersion = 8
            M.db.sizeSeeded, M.db.scaleSeeded = nil, nil
            if Enum.NamePlateSize then SetCVarIf("nameplateSize", tostring(Enum.NamePlateSize.Medium)) end
            local maxScale = tonumber(C_CVar.GetCVarDefault("nameplateMaxScale") or "") or 1
            local scale = ("%.3f"):format(maxScale * PLATE_SCALE)
            SetCVarIf("nameplateMaxScale", scale)
            SetCVarIf("nameplateMinScale", scale)
            SetCVarIf("nameplateSelectedScale", scale)
        end
    end)
end

---------------------------------------------------------------------------
-- Names-only for friendly NPCs and pets: fade everything but the name, the
-- raid icon, widgets and the soft-target icon.
---------------------------------------------------------------------------
local FADE_KEYS = {
    "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "ClassificationFrame", "LevelFrame",
    "PlayerLevelDiffFrame", "selectionHighlight", "aggroHighlight", "aggroHighlightBase",
    "aggroHighlightAdditive", "aggroFlash",
}
local faded = setmetatable({}, { __mode = "k" })   -- [unitFrame] = { [region] = alpha before }
local titles = setmetatable({}, { __mode = "k" })  -- [unitFrame] = title FontString
local frameOf = {}                                 -- [unit token] = unitFrame

local function Fade(frame)
    local saved = faded[frame]
    if saved then
        for region in pairs(saved) do region:SetAlpha(0) end -- keep them faded
        return
    end
    saved = {}
    for _, key in ipairs(FADE_KEYS) do
        local region = frame[key]
        if region and region.SetAlpha and not (region.IsForbidden and region:IsForbidden()) then
            saved[region] = Plain(region:GetAlpha()) or 1
            region:SetAlpha(0)
        end
    end
    faded[frame] = saved
end

local function Unfade(frame)
    local saved = faded[frame]
    if not saved then return end
    faded[frame] = nil
    for region, alpha in pairs(saved) do region:SetAlpha(alpha) end
end

-- The game answers UnitIsPlayer / UnitPlayerControlled with a plain false
-- for some players (e.g. the other faction when not flagged for PvP), so the
-- unit's GUID type decides: "Player-", "Pet-", or a creature (a pet when
-- player-controlled: minions, totems). If the GUID itself is secret, the
-- tooltip decides: a pet has a UnitOwner line ("Name's Pet").
local function TooltipKind(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    if not lines then return nil end
    local ownerType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitOwner
    for _, line in ipairs(lines) do
        local lineType = line.type
        if ownerType and not Secret(lineType) and lineType == ownerType then return "pet" end
    end
    return "player"
end

-- "player" (friendly player), "npc" (friendly NPC), "pet" (friendly
-- player-controlled non-player), or nil (enemies, unknown). Players and their
-- pets that are neither friendly nor attackable (the other faction when not
-- flagged for PvP) count as friendly too; attackable ones stay enemies.
local function KindOf(unit)
    local friend = Plain(UnitIsFriend("player", unit))
    local canAttack = UnitCanAttack("player", unit)
    if not friend and (Secret(canAttack) or canAttack) then return nil end
    local kind
    local guid = UnitGUID(unit)
    if type(guid) == "string" and not Secret(guid) then
        local guidType = guid:match("^(%a+)%-")
        if guidType == "Player" then kind = "player"
        elseif guidType == "Pet" or Plain(UnitPlayerControlled(unit)) then kind = "pet"
        else kind = "npc" end
    else
        kind = TooltipKind(unit)
    end
    if not friend and kind == "npc" then return nil end -- neutral NPCs keep Blizzard's plate
    return kind
end

-- Class of a player plate: UnitClassBase, or (when the game hides it) the
-- class name line of the unit's tooltip, mapped back to the class token.
local classByName
local function TooltipClass(unit)
    if not classByName then
        classByName = {}
        for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for token, name in pairs(names) do classByName[name] = token end
        end
    end
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(unit)
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if text and not Secret(text) and classByName[text] then return classByName[text] end
    end
end

local function PlayerClass(unit)
    local token = UnitClassBase(unit)
    if type(token) ~= "nil" then return token end -- may be secret: only passed on
    return TooltipClass(unit)
end

---------------------------------------------------------------------------
-- Title line (guild / NPC title)
---------------------------------------------------------------------------
local titleCache = {} -- [npc id] = title text, or false for none

local function NpcTitle(unit)
    local guid = Plain(UnitGUID(unit))
    local npcID = guid and select(6, strsplit("-", guid))
    if npcID and titleCache[npcID] ~= nil then return titleCache[npcID] or nil end
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    if not (lines and lines[1]) then return nil end -- not ready yet: try again next update
    local line = lines[GetCVarBool("colorblindMode") and 3 or 2]
    local text = line and line.leftText
    local title = false
    if text and not Secret(text) and type(text) == "string" and text ~= ""
        and not (LEVEL and text:find(LEVEL, 1, true)) then
        title = text
    end
    if npcID then titleCache[npcID] = title end
    return title or nil
end

local function TitleString(frame)
    local fs = titles[frame]
    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlate")
        fs:SetPoint("TOP", frame.name, "BOTTOM", 0, -1)
        fs:SetTextColor(1, 1, 1)
        titles[frame] = fs
    end
    return fs
end

local function HideTitle(frame)
    local fs = titles[frame]
    if fs then fs:SetText(""); fs:Hide() end
end

-- Same font as the name, a bit smaller (Blizzard sizes the name per plate size).
local TITLE_SIZE = 0.85

local function MatchNameFont(fs, name)
    local file, height, flags = name:GetFont()
    if not (Plain(file) and Plain(height)) then return end
    local wanted = height * TITLE_SIZE
    local _, current = fs:GetFont()
    if current ~= wanted then fs:SetFont(file, wanted, Plain(flags) or "") end
end

local function UpdateTitle(frame, unit, kind)
    local text
    if kind == "player" then
        text = GetGuildInfo(unit) -- may be secret: only truth-tested and formatted
    elseif kind == "npc" then
        text = NpcTitle(unit)
    end
    local nameShown = frame.name and Plain(frame.name:IsShown())
    if text and nameShown then
        local fs = TitleString(frame)
        MatchNameFont(fs, frame.name)
        fs:SetFormattedText("<%s>", text)
        fs:Show()
    else
        HideTitle(frame)
    end
end

---------------------------------------------------------------------------
-- Per plate
---------------------------------------------------------------------------
local PET_BLUE = { 0.45, 0.65, 1.0 } -- the selection colour's blue is too dark to read
local FRIENDLY_NAME_SCALE = 0.99     -- friendly names relative to enemy ones (tuned in game)

-- Scale of a plate's name (and title): friendly plates a bit smaller, back to
-- 1 when the pooled frame shows an enemy. Region scale, not text scale:
-- Blizzard re-sets the name's text height on every layout, which would undo a
-- text scale.
local function SetNameScale(frame, scale)
    local name = frame.name
    if name and name.SetScale then pcall(name.SetScale, name, scale) end
    local fs = titles[frame]
    if fs and fs.SetScale then fs:SetScale(scale) end
end

-- Name colour via SetVertexColor, like Blizzard's own UpdateName: it re-sets
-- the vertex colour on every update, so nothing sticks to a pooled frame that
-- later shows another unit.
local function Tint(frame, r, g, b)
    if frame.name then frame.name:SetVertexColor(r, g, b) end
end

---------------------------------------------------------------------------
-- Quest progress box, left of the health bar (mirrors the level box)
---------------------------------------------------------------------------
local QUEST_PAD = 8          -- room around the text, both sides together
local QUEST_GAP = 5          -- health bar to box, as the level box
local QUEST_REFRESH = 0.1    -- quest log changes come in bursts
local QUEST_REFRESH_LATE = 0.5 -- after Polestar's quest index caught up
local QUEST_COLOR = { 1, 0.82, 0 }      -- your own quests
local MAX_DOTS = 5           -- group member dots under the box
local DOT_SIZE, DOT_RING, DOT_GAP = 4, 1, 2 -- dot, its dark outline, space between
local badges = setmetatable({}, { __mode = "k" }) -- [unitFrame] = box frame

-- One tooltip objective line as "8/10" or "45%" (area objectives keep their
-- percentage only in the text), and how much is left; nil when it has no count.
local function LineProgress(line)
    local text = Plain(line.leftText)
    text = type(text) == "string" and text or ""
    local percent = tonumber(text:match("(%d+)%s*%%"))
    if percent then return percent .. "%", 100 - percent end
    local have, need = Plain(line.numFulfilled), Plain(line.numRequired)
    if type(have) ~= "number" or type(need) ~= "number" then
        have, need = text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(have), tonumber(need)
    end
    if have and need then return have .. "/" .. need, need - have end
end

-- Polestar (kept as its own addon) knows which mobs drop quest items, which
-- the game's tooltip doesn't list. Its quest index covers your own log only.
local function PolestarProgress(unit)
    local db = Polestar and Polestar.QuestDB
    if not (db and db.IsRunning and db.IsRunning() and db.ObjectivesForNpc) then return nil end
    local guid = Plain(UnitGUID(unit))
    local guidType, npcID = guid and guid:match("^(%a+)%-"), nil
    if guidType == "Creature" or guidType == "Vehicle" then npcID = tonumber((select(6, strsplit("-", guid)))) end
    local list = npcID and db.ObjectivesForNpc(npcID)
    for _, o in ipairs(list or {}) do
        if not o.done and not (o.entry and o.entry.ready) and (o.max or 0) > 1 then
            return (o.cur or 0) .. "/" .. o.max
        end
    end
end

-- Group members' classes by full name (the tooltip's quest lines write names
-- in full): the colours, and the test that a name line is a group member.
local rosterClass, rosterDirty = {}, true
local function MemberClass(name)
    if rosterDirty then
        rosterDirty = false
        wipe(rosterClass)
        local prefix, count = "party", GetNumSubgroupMembers()
        if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
        for i = 1, count do
            local unit = prefix .. i
            local full = ns.UnitFullName(unit)
            local class = Plain(UnitClassBase(unit))
            if full and class then rosterClass[full] = class end
        end
    end
    return rosterClass[name]
end


-- A tooltip name line as a plain name: colour codes and spaces removed.
local function CleanName(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(text)
end

local function ClassRGB(name)
    local class = MemberClass(name)
    local color = class and C_ClassColor.GetClassColor(class)
    if color then return color:GetRGB() end
    return 0.8, 0.8, 0.8
end

-- Read per plate; reused.
local memberLeft, memberText, needing = {}, {}, {}

-- What a quest mob's plate shows:
--  * the count: your own unfinished objective (the game's tooltip: kills and
--    areas; else Polestar: items the mob drops); once you're done (or don't
--    have the quest), the group member with the most left, in their class
--    colour;
--  * the group members (not you) who still need the mob, by name, sorted:
--    the dots. The game's tooltip lists their objectives under their name.
-- Lines other addons add to the tooltip don't count.
-- Returns text, member (nil: yours), list of member names.
local function QuestProgress(unit)
    wipe(memberLeft)
    wipe(memberText)
    wipe(needing)
    local mine
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    local types = Enum.TooltipDataLineType
    if lines and types then
        local me = ns.UnitFullName("player")
        local owner -- nil: you (objectives under a quest title until a member's name line)
        for _, line in ipairs(lines) do
            local lineType = Plain(line.type)
            if lineType == types.QuestTitle then
                owner = nil
            elseif lineType == types.QuestPlayer then
                -- Only a group member (not you) owns the lines below; any
                -- other name line (yours, or one that can't be matched)
                -- leaves them yours.
                local name = CleanName(Plain(line.leftText))
                owner = name and name ~= me and MemberClass(name) and name or nil
            elseif lineType == types.QuestObjective and Plain(line.completed) == false then
                local text, left = LineProgress(line)
                if text then
                    if not owner then
                        mine = mine or text
                    elseif not memberLeft[owner] or left > memberLeft[owner] then
                        memberLeft[owner], memberText[owner] = left, text
                    end
                end
            end
        end
    end
    mine = mine or PolestarProgress(unit)
    local behind
    for name, left in pairs(memberLeft) do
        needing[#needing + 1] = name
        if not behind or left > memberLeft[behind] then behind = name end
    end
    table.sort(needing)
    if mine then return mine, nil, needing end
    if behind then return memberText[behind], behind, needing end
    return nil, nil, needing
end

local function Badge(frame)
    local box = badges[frame]
    if box then return box end
    local bar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
    if not bar then return nil end
    box = CreateFrame("Frame", nil, frame)
    box:SetFrameLevel(bar:GetFrameLevel() + 5)
    box:SetPoint("TOPRIGHT", bar, "TOPLEFT", -QUEST_GAP, 3)
    box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -QUEST_GAP, -2)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("ui-hud-nameplates-levelindicator")
    bg:SetAllPoints()
    -- Wider than the level box: stretch the middle, keep the rounded ends.
    if bg.SetTextureSliceMargins then
        bg:SetTextureSliceMargins(6, 6, 6, 6)
        bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
    box.text = box:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateLevel")
    box.text:SetPoint("CENTER")
    -- Target / focus border, as on the level box.
    box.selected = box:CreateTexture(nil, "OVERLAY")
    box.selected:SetAtlas("ui-hud-nameplates-levelindicator-rectangle-selected")
    box.selected:SetPoint("TOPLEFT", -3, 3)
    box.selected:SetPoint("BOTTOMRIGHT", 3, -4)
    if box.selected.SetTextureSliceMargins then
        box.selected:SetTextureSliceMargins(8, 8, 8, 8)
        box.selected:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
    box.selected:Hide()
    box.dots = {}
    badges[frame] = box
    return box
end

-- A round dot with a dark outline, below the box.
local DOT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Circle(box, size, sublevel)
    local tex = box:CreateTexture(nil, "OVERLAY", nil, sublevel)
    tex:SetSize(size, size)
    local mask = box:CreateMaskTexture()
    mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end

local function Dot(box, i)
    local dot = box.dots[i]
    if dot then return dot end
    local ring = Circle(box, DOT_SIZE + 2 * DOT_RING, 1)
    ring:SetColorTexture(0, 0, 0, 0.9)
    local fill = Circle(box, DOT_SIZE, 2)
    fill:SetPoint("CENTER", ring)
    dot = { ring = ring, fill = fill }
    box.dots[i] = dot
    return dot
end

local function ShowDots(box, names)
    local n = math.min(#names, MAX_DOTS)
    local step = DOT_SIZE + 2 * DOT_RING + DOT_GAP
    local x0 = -(n - 1) * step / 2
    for i = 1, n do
        local dot = Dot(box, i)
        dot.ring:ClearAllPoints()
        dot.ring:SetPoint("TOP", box, "BOTTOM", x0 + (i - 1) * step, 0)
        dot.fill:SetColorTexture(ClassRGB(names[i]))
        dot.ring:Show()
        dot.fill:Show()
    end
    for i = n + 1, #box.dots do
        box.dots[i].ring:Hide()
        box.dots[i].fill:Hide()
    end
end

local function UpdateSelected(frame, unit)
    local box = badges[frame]
    if not (box and box:IsShown()) then return end
    local constants = NamePlateConstants
    local color
    if Plain(UnitIsUnit(unit, "target")) then
        color = constants and constants.TARGET_BORDER_COLOR
    elseif Plain(UnitIsUnit(unit, "focus")) then
        color = constants and constants.FOCUS_TARGET_BORDER_COLOR
    end
    if color then box.selected:SetVertexColor(color:GetRGB()) end
    box.selected:SetShown(color ~= nil)
end

local function HideQuest(frame)
    local box = badges[frame]
    if box then box:Hide() end
end

---------------------------------------------------------------------------
-- Health text: percentage at the bar's left end, value at its right (as on
-- the unit frames). Blizzard's own text (both right-aligned in one spot) is
-- faded out; ours follows Blizzard's nameplate setting for which of the two
-- show (Interface > Nameplates, the health percentage / value options).
-- Values that are secret go straight to the text calls that accept them.
---------------------------------------------------------------------------
local HEALTH_TEXT_INSET = 3 -- px from the bar's ends
local healthTexts = setmetatable({}, { __mode = "k" }) -- [health bar] = { left, right }
local hiddenText = setmetatable({}, { __mode = "k" })  -- [Blizzard's health text] = true

local function HideBlizzardText(region)
    if not region or hiddenText[region] then return end
    hiddenText[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then self:SetAlpha(0) end
    end)
end

local function HealthTexts(bar)
    local texts = healthTexts[bar]
    if texts then return texts end
    local model = bar.Text or bar.TextString
    texts = {}
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local fs = bar:CreateFontString(nil, "OVERLAY")
        local font = model and model:GetFontObject()
        if font then
            fs:SetFontObject(font)
        elseif model and model:GetFont() then
            fs:SetFont(model:GetFont())
        else
            fs:SetFontObject("SystemFont_NamePlate")
        end
        if model then
            fs:SetShadowOffset(model:GetShadowOffset())
            fs:SetShadowColor(model:GetShadowColor())
            fs:SetTextColor(model:GetTextColor())
        end
        fs:SetPoint(side, bar, side, side == "LEFT" and HEALTH_TEXT_INSET or -HEALTH_TEXT_INSET, 0)
        fs:SetJustifyH(side)
        texts[side] = fs
    end
    HideBlizzardText(bar.Text)
    HideBlizzardText(bar.TextString)
    HideBlizzardText(bar.LeftText)
    HideBlizzardText(bar.RightText)
    healthTexts[bar] = texts
    return texts
end

-- Which of the two Blizzard's nameplate setting shows.
local function HealthTextWanted()
    local I = Enum.NamePlateInfoDisplay
    if not (I and C_CVar.GetCVarBitfield) then return true, true end
    return C_CVar.GetCVarBitfield("nameplateInfoDisplay", I.CurrentHealthPercent),
        C_CVar.GetCVarBitfield("nameplateInfoDisplay", I.CurrentHealthValue)
end

local function HealthValueText(fs, health)
    if not Secret(health) then
        fs:SetText(AbbreviateNumbers and AbbreviateNumbers(health) or tostring(health))
    elseif not (AbbreviateNumbers and pcall(function() fs:SetText(AbbreviateNumbers(health)) end)) then
        fs:SetFormattedText("%d", health)
    end
end

local function UpdateHealthText(frame, unit)
    local bar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
    if not bar then return end
    local texts = HealthTexts(bar)
    local percentOn, valueOn = HealthTextWanted()
    if percentOn and UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        texts.LEFT:SetFormattedText("%.0f%%", UnitHealthPercent(unit, nil, CurveConstants.ScaleTo100))
        texts.LEFT:Show()
    else
        texts.LEFT:Hide()
    end
    if valueOn then
        HealthValueText(texts.RIGHT, UnitHealth(unit))
        texts.RIGHT:Show()
    else
        texts.RIGHT:Hide()
    end
end

local kindOf = setmetatable({}, { __mode = "k" })  -- [unitFrame] = kind for its current unit
local classOf = setmetatable({}, { __mode = "k" }) -- [unitFrame] = class token for a player plate

local function Refresh(frame, unit, recheck)
    local kind = kindOf[frame]
    if recheck or kind == nil then
        kind = KindOf(unit) or false
        kindOf[frame] = kind
        classOf[frame] = kind == "player" and PlayerClass(unit) or nil
    end
    kind = kind or nil
    if kind == "pet" then
        Fade(frame)
        Tint(frame, PET_BLUE[1], PET_BLUE[2], PET_BLUE[3])
    elseif kind == "npc" then
        Fade(frame)
        -- NPC reaction colours (green / yellow).
        local r, g, b = UnitSelectionColor(unit)
        if Plain(r) then Tint(frame, r, g, b) end
    else
        -- Friendly players use Blizzard's names-only mode; neutral ones (the
        -- other faction, not flagged) get an enemy-style plate: fade it here.
        if kind == "player" and not Plain(UnitIsFriend("player", unit)) then Fade(frame) else Unfade(frame) end
        if kind == "player" then
            -- Class colour. Blizzard's own class colour fails for players whose
            -- identity is kept secret from addons (e.g. the other faction when
            -- not flagged for PvP: friendly but shown in neutral yellow). The
            -- class token may be secret: only nil-checked by type and passed
            -- to GetClassColor / SetVertexColor, which accept secret values.
            local token = classOf[frame]
            local color = type(token) ~= "nil" and C_ClassColor.GetClassColor(token)
            if color then Tint(frame, color:GetRGB()) end
        end
    end
    UpdateTitle(frame, unit, kind)
    SetNameScale(frame, kind and FRIENDLY_NAME_SCALE or 1)
end

-- Only on plates that show their health bar (not the names-only ones).
local function UpdateQuest(frame, unit)
    local text, member, needing
    if not kindOf[frame] then text, member, needing = QuestProgress(unit) end
    if not text then HideQuest(frame) return end
    local box = Badge(frame)
    if not box then return end
    if member then
        box.text:SetTextColor(ClassRGB(member))
    else
        box.text:SetTextColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3])
    end
    box.text:SetText(text)
    ShowDots(box, needing)
    local level = frame.PlayerLevelDiffFrame
    local minWidth = level and Plain(level:GetWidth()) or 0
    box:SetWidth(math.max(minWidth, box.text:GetStringWidth() + QUEST_PAD))
    box:Show()
    UpdateSelected(frame, unit)
end

local function RefreshQuests()
    for unit, frame in pairs(frameOf) do ns.safecall(UpdateQuest, frame, unit) end
end

-- Quest events come in bursts: one refresh shortly after, and one more once
-- Polestar has updated its own quest index (it waits a quarter second).
local refreshSoon, refreshLate = false, false
local function QueueQuestRefresh()
    if not refreshSoon then
        refreshSoon = true
        C_Timer.After(QUEST_REFRESH, function() refreshSoon = false; RefreshQuests() end)
    end
    if not refreshLate then
        refreshLate = true
        C_Timer.After(QUEST_REFRESH_LATE, function() refreshLate = false; RefreshQuests() end)
    end
end

---------------------------------------------------------------------------
-- Target marker: one arrow, moved to the target's plate (above its name).
---------------------------------------------------------------------------
local MARKER_ATLAS = "NPE_ArrowDown"
local MARKER_HEIGHT = 18
local MARKER_GAP = 2
local MARKER_BOB = 4      -- px up and down
local MARKER_BOB_TIME = 0.45
local marker

local function Marker()
    if marker then return marker end
    marker = CreateFrame("Frame", nil, UIParent)
    marker:Hide()
    local tex = marker:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    local info = C_Texture.GetAtlasInfo(MARKER_ATLAS)
    if info and info.height > 0 then
        tex:SetAtlas(MARKER_ATLAS)
        marker:SetSize(MARKER_HEIGHT * info.width / info.height, MARKER_HEIGHT)
    else
        tex:SetTexture("Interface/Minimap/MiniMap-QuestArrow")
        tex:SetRotation(math.pi)
        marker:SetSize(MARKER_HEIGHT, MARKER_HEIGHT)
    end
    marker.bob = marker:CreateAnimationGroup()
    marker.bob:SetLooping("BOUNCE")
    local move = marker.bob:CreateAnimation("Translation")
    move:SetOffset(0, MARKER_BOB)
    move:SetDuration(MARKER_BOB_TIME)
    move:SetSmoothing("IN_OUT")
    return marker
end

local function UpdateMarker()
    local m = Marker()
    local frame
    for unit, f in pairs(frameOf) do
        if Plain(UnitIsUnit(unit, "target")) then frame = f break end
    end
    if not frame then
        m.bob:Stop()
        m:Hide()
        m:SetParent(UIParent)
        return
    end
    m:SetParent(frame)
    m:SetFrameLevel(frame:GetFrameLevel() + 10)
    m:ClearAllPoints()
    local name = frame.name
    m:SetPoint("BOTTOM", (name and name:IsShown()) and name or frame.HealthBarsContainer or frame, "TOP", 0, MARKER_GAP)
    m:Show()
    m.bob:Play()
end

-- Threat: our own copy of the selection border (Blizzard's atlas, laid over
-- Blizzard's selectedBorder, which keeps its anchors even while hidden), in
-- GetThreatStatusColor's colour at threat status 1+. Not on your target: it
-- shows Blizzard's. Blizzard re-runs its border update on every threat and
-- target change; our own threat events too.
local threatBorders = setmetatable({}, { __mode = "k" }) -- [health bar] = texture
local function ThreatBorder(bar)
    local border = threatBorders[bar]
    if border or not bar.selectedBorder then return border end
    border = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    local constants = NamePlateConstants
    local atlas = constants and constants.SELECTED_BORDER_ATLAS
    if atlas then
        border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    else
        border:SetTexture(bar.selectedBorder:GetTexture())
    end
    border:SetAllPoints(bar.selectedBorder)
    border:Hide()
    threatBorders[bar] = border
    return border
end

-- Threat values can be secret to addons (in combat, and solo Blizzard's own
-- threat display is off): with a plain status the colour follows it; with a
-- secret one the border is red and shown only while the enemy is on you
-- (isTanking, a secret boolean, through SetAlphaFromBoolean).
local THREAT_RED = { 1, 0.1, 0.1 }
local function OnHealthBorder(frame)
    if type(frame) ~= "table" or frame:IsForbidden() then return end
    local unit = frame.unit
    if type(unit) ~= "string" or Secret(unit) or unit:sub(1, 9) ~= "nameplate" then return end
    local bar = frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
    if not bar then return end
    local isTanking, status
    if Plain(UnitCanAttack("player", unit)) and not Plain(UnitIsUnit(unit, "target")) then
        isTanking, status = UnitDetailedThreatSituation("player", unit)
    end
    if type(isTanking) == "nil" then
        if threatBorders[bar] then threatBorders[bar]:Hide() end
        return
    end
    local border = ThreatBorder(bar)
    if not border then return end
    if not Secret(status) and not Secret(isTanking) then
        if not status or status < 1 then border:Hide() return end
        local r, g, b = GetThreatStatusColor(status)
        border:SetVertexColor(r, g, b)
        border:SetAlpha(1)
    else
        border:SetVertexColor(THREAT_RED[1], THREAT_RED[2], THREAT_RED[3])
        border:SetAlphaFromBoolean(isTanking, 1, 0)
    end
    border:Show()
end

-- After Blizzard set the name (and its colour): any nameplate update.
local function OnUpdateName(frame)
    local unit = frame and frame.unit
    if type(unit) ~= "string" or Secret(unit) or unit:sub(1, 9) ~= "nameplate" then return end
    if frame:IsForbidden() then return end
    ns.safecall(Refresh, frame, unit)
end

local function OnPlateAdded(_, unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit) -- no forbidden plates
    local frame = plate and plate.UnitFrame
    if not frame or frame:IsForbidden() then return end
    frameOf[unit] = frame
    Refresh(frame, unit, true)
    UpdateQuest(frame, unit)
    UpdateHealthText(frame, unit)
    if Plain(UnitIsUnit(unit, "target")) then UpdateMarker() end
end

local function OnPlateRemoved(_, unit)
    local frame = frameOf[unit]
    frameOf[unit] = nil
    if not frame then return end
    Unfade(frame) -- the pooled frame may be reused for an enemy
    kindOf[frame], classOf[frame] = nil, nil
    HideTitle(frame)
    HideQuest(frame)
    SetNameScale(frame, 1)
    if marker and marker:GetParent() == frame then UpdateMarker() end
end

-- /kk nameplates scale: every plate scale setting, to see what still grows.
local SCALE_CVARS = {
    "nameplateSize", "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale", "nameplateLargerScale",
    "nameplateGlobalScale", "nameplateSelfScale", "nameplateMinScaleDistance", "nameplateMaxScaleDistance",
    "nameplateSoftTargetScale", "SoftTargetNameplateSize", "SoftTargetNameplateEnemy", "SoftTargetNameplateFriend",
    "SoftTargetNameplateInteract",
}

-- /kk nameplates unit: what the game reports for your target (to see why a
-- plate is styled the way it is).
local function Describe(v)
    if Secret(v) then return "secret (" .. type(v) .. ")" end
    return tostring(v)
end

local function DebugUnit()
    local unit = UnitExists("target") and "target" or (UnitExists("mouseover") and "mouseover")
    if not unit then ns:Print("target a unit first") return end
    local plateUnit
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local u = plate.UnitFrame and plate.UnitFrame.unit
        if u and not Secret(u) and Plain(UnitIsUnit(u, unit)) then plateUnit = u end
    end
    local function Line(label, value) ns:Print(("%s: %s"):format(label, value)) end
    Line("unit", unit .. (plateUnit and (" = " .. plateUnit) or " (not in the plate list)"))
    local direct = C_NamePlate.GetNamePlateForUnit(unit)
    Line("nameplate", direct and "yes" or "none (or locked)")
    local u = plateUnit or unit
    Line("UnitIsFriend", Describe(UnitIsFriend("player", u)))
    Line("UnitCanAttack", Describe(UnitCanAttack("player", u)))
    Line("UnitIsPlayer", Describe(UnitIsPlayer(u)))
    Line("UnitPlayerControlled", Describe(UnitPlayerControlled(u)))
    local guid = UnitGUID(u)
    Line("UnitGUID type", Secret(guid) and "secret" or tostring(guid and guid:match("^(%a+)%-")))
    Line("UnitClassBase", Describe(UnitClassBase(u)))
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        Line("identity secret", Describe(C_Secrets.ShouldUnitIdentityBeSecret(u)))
    end
    Line("KuroKit kind", tostring(KindOf(u)))
    local text, member, needing = QuestProgress(u)
    Line("quest box", ("%s (%s), dots: %s"):format(tostring(text), member or "yours",
        #needing > 0 and table.concat(needing, ", ") or "none"))
    local roster = {}
    for name, class in pairs(rosterClass) do roster[#roster + 1] = name .. "=" .. class end
    Line("group", #roster > 0 and table.concat(roster, ", ") or "none")
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit(u)
    for i, line in ipairs(data and data.lines or {}) do
        Line(("tooltip %d"):format(i), ("type %s, %s"):format(Describe(line.type), Describe(line.leftText)))
    end
end

function M:OnSlash(args)
    if args and args:lower():match("^unit") then
        DebugUnit()
    elseif args and args:lower():match("^scale") then
        for _, cvar in ipairs(SCALE_CVARS) do
            local value = GetCVar(cvar)
            if value ~= nil then
                ns:Print(("%s = %s (default %s)"):format(cvar, value, tostring(C_CVar.GetCVarDefault(cvar))))
            end
        end
    else
        ns:Print("/kk nameplates scale: list the nameplate scale settings")
        ns:Print("/kk nameplates unit: what the game reports for your target")
    end
end

---------------------------------------------------------------------------
-- Questie: its nameplate quest icon sits where the quest box goes (the
-- plate's left edge) and draws over it. Once per Questie profile, KuroKit
-- turns Questie's nameplate icons off, the way Questie's own checkbox does
-- (Questie options > Nameplate), and says so in chat. Turning them back on
-- there is respected.
---------------------------------------------------------------------------
local function TakeOverQuestieNameplates()
    local db = Questie and Questie.db
    local profile = db and db.profile
    if not profile then return end
    local name = db.GetCurrentProfile and db:GetCurrentProfile() or "Default"
    M.db.questieNameplatesOff = M.db.questieNameplatesOff or {}
    if M.db.questieNameplatesOff[name] then return end
    M.db.questieNameplatesOff[name] = true
    if not profile.nameplateEnabled then return end
    profile.nameplateEnabled = false
    local nameplate = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("QuestieNameplate")
    if nameplate and nameplate.HideCurrentFrames then nameplate:HideCurrentFrames() end
    ns:Print("turned off Questie's nameplate quest icons: KuroKit's quest box shows your progress there. "
        .. "Questie options > Nameplate turns them back on.")
end

function M:OnEnable()
    ApplyCVars()
    local questie = Questie and Questie.API
    if questie and type(questie.RegisterOnReady) == "function" then
        questie.RegisterOnReady(function() ns.safecall(TakeOverQuestieNameplates) end)
    end
    hooksecurefunc("CompactUnitFrame_UpdateName", OnUpdateName)
    ns:On("NAME_PLATE_UNIT_ADDED", OnPlateAdded)
    ns:On("NAME_PLATE_UNIT_REMOVED", OnPlateRemoved)
    local function OnHealth(_, unit)
        local frame = frameOf[unit]
        if frame then ns.safecall(UpdateHealthText, frame, unit) end
    end
    ns:On("UNIT_HEALTH", OnHealth)
    ns:On("UNIT_MAXHEALTH", OnHealth)
    ns:On("CVAR_UPDATE", function(_, cvar)
        if type(cvar) == "string" and not Secret(cvar) and cvar == "nameplateInfoDisplay" then
            for unit, frame in pairs(frameOf) do ns.safecall(UpdateHealthText, frame, unit) end
        end
    end)
    ns:On("UNIT_FACTION", function(_, unit)
        local frame = frameOf[unit]
        if frame then
            Refresh(frame, unit, true)
            UpdateQuest(frame, unit)
        end
    end)
    -- Your quest log, and group members' (UNIT_QUEST_LOG_CHANGED for party units).
    ns:On("QUEST_LOG_UPDATE", QueueQuestRefresh)
    ns:On("UNIT_QUEST_LOG_CHANGED", QueueQuestRefresh)
    hooksecurefunc("CompactUnitFrame_UpdateHealthBorder", function(frame) ns.safecall(OnHealthBorder, frame) end)
    -- Our own threat events too (they may name "target" or the player rather
    -- than the plate): all plates, once per frame.
    local threatQueued = false
    local function OnThreat()
        if threatQueued then return end
        threatQueued = true
        C_Timer.After(0, function()
            threatQueued = false
            for _, frame in pairs(frameOf) do ns.safecall(OnHealthBorder, frame) end
        end)
    end
    ns:On("UNIT_THREAT_SITUATION_UPDATE", OnThreat)
    ns:On("UNIT_THREAT_LIST_UPDATE", OnThreat)
    ns:On("PLAYER_REGEN_DISABLED", OnThreat)
    ns:On("PLAYER_REGEN_ENABLED", function()
        for _, frame in pairs(frameOf) do ns.safecall(OnHealthBorder, frame) end
    end)
    local function OnSelectionChanged()
        for unit, frame in pairs(frameOf) do UpdateSelected(frame, unit) end
        UpdateMarker()
    end
    ns:On("PLAYER_TARGET_CHANGED", OnSelectionChanged)
    ns:On("PLAYER_FOCUS_CHANGED", OnSelectionChanged)
    ns:On("GROUP_ROSTER_UPDATE", function()
        rosterDirty = true
        QueueQuestRefresh()
    end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        wipe(titleCache)
        ApplyCVars()
    end)
end
