-- Quest tracker: your tracked quests grouped by zone, in Blizzard's tracker
-- look, at the Objective Tracker's Edit Mode spot.
--   * zones: the one you're in first, then A-Z; finished quests last in each
--   * click a zone name to fold it (remembered; a folded zone shows its quest
--     count); a quest log button on the minimap (in its hover row next to the
--     calendar) hides / shows the tracker
--   * left-click a quest: Blizzard's own tracker click (opens the quest; the
--     untrack / chat link modifiers work as usual); right-click: a menu with
--     untrack, share, abandon and a Wowhead link
--   * usable quest items get a button left of the quest
--   * colour shows a quest's state: finished quests green, the focused quest
--     (right-click > Focus: the waypoint and map follow it) bright white-gold
--   * Spoken's Play button left of a voiced quest's title (when Spoken is on)
--   * timed quests get a "Time Remaining" line that counts down
--
-- How: Blizzard's ObjectiveTrackerFrame stays where Edit Mode puts it, faded
-- to alpha 0 (never hidden: it's managed by Edit Mode) and click-through
-- (mouse off on its named click sinks); this frame is anchored to it. While
-- Edit Mode is open Blizzard's tracker shows instead, so it can be moved and
-- sized there. Left-clicks reach Blizzard's own block through a secure
-- overlay button (out of combat), so no Blizzard map or quest code runs from
-- addon code. Item buttons are secure buttons placed by screen position (not
-- anchored to the tracker) and only moved out of combat.
-- Blizzard's other tracker sections (achievements, tracked recipes, ...) fade
-- out with it. When another addon hides Blizzard's tracker (Polestar's "Hide
-- the game's quest tracker", Questie's equivalent: both Hide that frame), this
-- one hides with it.
-- Cost: one redraw per frame at most, on quest log changes.
local _, ns = ...

local M = ns:NewModule("QuestTracker", {
    title = "Quest Tracker",
    group = "Interface",
    desc = "Tracked quests grouped by zone (current zone first, finished quests last), at the Objective Tracker's "
        .. "Edit Mode spot. Click a zone to fold it; the quest button on the minimap (while hovering it) hides or shows the tracker. Right-click a quest "
        .. "for untrack, share, abandon and a Wowhead link.",
    defaults = { collapsed = false, foldedZones = {} },
})

local ZONE_HEIGHT = 25    -- unless Blizzard's section header says otherwise
local ZONE_SPACING = 9    -- px between a zone header (its bar) and its first quest
local ZONE_BAR_PAD = 2    -- px of bar left of the zone name before its fade starts
local ZONE_BAR_FADE = 18  -- px over which the bar's left end fades out
local ZONE_BAR_SKIP = 24  -- px of the art's right end left out (it tapers off there, under Blizzard's button)
local ZONE_GAP = 14       -- px above every zone header but the first
local QUEST_GAP = 10      -- px between quests
local LINE_GAP = 2        -- px between a quest's lines
local DEFAULT_BUTTON_SIZE = 22
local BUTTON_GAP = 2     -- px between the calendar and the quest button (round minimap)
local BUTTON_INSET = 4   -- px from the button's edge to its quest glyph
local PLAY_SIZE = 14      -- Spoken's Play button
local PLAY_GAP = 4
local PLAY_BOX = "QuestLog-icon-ticksquare" -- the quest log's box, which Spoken's button matches
local TIMER_WARN = 60     -- seconds left from which a timer turns red
local ITEM_SIZE = 26
local ITEM_GAP = 6        -- px between an item button and its quest
local DEFAULT_MAX_HEIGHT = 600
local MIN_MAX_HEIGHT = 150

local WOWHEAD = "https://www.wowhead.com/forever/%squest=%d"
local WOWHEAD_LANG = {
    deDE = "de/", esES = "es/", esMX = "es/", frFR = "fr/", itIT = "it/", ptBR = "pt/", ruRU = "ru/",
    koKR = "ko/", zhCN = "cn/", zhTW = "cn/",
}

-- Blizzard tracker sections whose blocks a quest left-click can go to.
local QUEST_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
-- Sections whose click sinks are switched off while faded.
local MODULES = {
    "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "AchievementObjectiveTracker",
    "ProfessionsRecipeTracker", "BonusObjectiveTracker", "WorldQuestObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker", "AdventureObjectiveTracker", "InitiativeTasksObjectiveTracker",
}

-- Blizzard's tracker colours when the client has them.
local FALLBACK_COLORS = {
    Normal = { r = 0.8, g = 0.8, b = 0.8 }, NormalHighlight = { r = 1, g = 1, b = 1 },
    Header = { r = 0.75, g = 0.61, b = 0 }, HeaderHighlight = { r = 1, g = 0.82, b = 0 },
    Complete = { r = 0.6, g = 0.6, b = 0.6 }, CompleteHighlight = { r = 1, g = 1, b = 1 },
    Failed = { r = 0.75, g = 0.1, b = 0.1 }, FailedHighlight = { r = 1, g = 0.2, b = 0.2 },
}
-- Quest titles by state (hover: the Highlight one).
local TITLE_COLORS = {
    Finished = { r = 0.25, g = 0.9, b = 0.25 }, FinishedHighlight = { r = 0.55, g = 1, b = 0.55 },
    Focused = { r = 1, g = 0.95, b = 0.65 }, FocusedHighlight = { r = 1, g = 1, b = 1 },
}

local tracker, questButton, itemLayer, overlay, linkBox
local fonts = {}
local zoneArt             -- Blizzard's section header bar, read once (see ReadZoneArt)
local zoneRows, blocks, itemButtons = {}, {}, {}
local shownZones, shownBlocks = 0, 0
local pending, editing, itemsQueued = false, false, false
local HiddenByAddon
local timerTicker
local spoken           -- { ui = Spoken's quest overlay, api = Spoken } once checked; false: not available
local voiced = {}      -- [questID] = whether Spoken offers Play for it
local hookedModules = {}

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function PlainNumber(v) if type(v) == "number" and not Secret(v) then return v end end
local function PlainString(v) if type(v) == "string" and not Secret(v) and v ~= "" then return v end end

local function Color(key)
    local c = TITLE_COLORS[key] or (OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR[key]) or FALLBACK_COLORS[key]
    return c.r, c.g, c.b
end

local function Text(globalName, fallback)
    return PlainString(_G[globalName]) or fallback
end

local function FontObject(...)
    for i = 1, select("#", ...) do
        local font = _G[select(i, ...)]
        if font then return font end
    end
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
-- The quest log: zone (its header), log index, title and "on this map" per quest.
local function ReadLog()
    local log = {}
    local zone
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                zone = PlainString(info.title)
            elseif info.questID then
                log[info.questID] = { zone = zone, logIndex = i, title = PlainString(info.title), onMap = info.isOnMap }
            end
        end
    end
    return log
end

-- Forever's own title prefix (quest level and the like), as its quest log shows it.
local function TitlePrefix(id)
    local overrides = QuestUtilsOverrides
    if not (overrides and overrides.GetQuestTitlePrefix) then return "" end
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    local ok, prefix = pcall(overrides.GetQuestTitlePrefix, { questID = id, difficultyLevel = level })
    return ok and PlainString(prefix) or ""
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, sec = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, sec) end
    return ("%d:%02d"):format(m, sec)
end

-- A timer line's text and colour for the time left.
local function PaintTimerLine(line)
    local left = line.timerEnd - GetTime()
    line.text = ("- %s %s"):format(Text("TIME_REMAINING", "Time Remaining:"), Clock(left))
    line.kind = left <= TIMER_WARN and "Failed" or "Normal"
end

-- Seconds left per timed quest, as end times.
local function QuestTimers()
    local ends = {}
    local timers = C_QuestLog.GetQuestTimers and C_QuestLog.GetQuestTimers()
    if type(timers) == "table" then
        local now = GetTime()
        for _, t in ipairs(timers) do
            local id, left = t.questID, PlainNumber(t.questTimer)
            if id and left then ends[id] = now + left end
        end
    end
    return ends
end

local function QuestLines(q)
    local id, lines = q.id, {}
    if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then
        lines[1] = { text = "- " .. Text("FAILED", "Failed"), kind = "Failed" }
        return lines
    end
    if q.timerEnd then
        local timer = { timerEnd = q.timerEnd }
        PaintTimerLine(timer)
        lines[1] = timer
    end
    if q.complete then
        local text = GetQuestLogCompletionText and PlainString(GetQuestLogCompletionText(q.logIndex))
        lines[#lines + 1] = { text = "- " .. (text or Text("QUEST_WATCH_QUEST_READY", "Ready for turn-in")), kind = "Normal" }
        return lines
    end
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        local text = PlainString(objective.text)
        if text then
            if objective.type == "progressbar" and GetQuestProgressBarPercent then
                local percent = PlainNumber(GetQuestProgressBarPercent(id))
                if percent then text = ("%s (%d%%)"):format(text, percent) end
            end
            lines[#lines + 1] = { text = "- " .. text, kind = objective.finished and "Complete" or "Normal" }
        end
    end
    return lines
end

local function QuestItem(logIndex, complete)
    if not GetQuestLogSpecialItemInfo then return nil end
    local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
    link = PlainString(link)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if not itemID or (complete and not showWhenComplete) then return nil end
    return { id = itemID, texture = texture, charges = PlainNumber(charges) or 0 }
end

local function IsCurrentZone(name, quests)
    if name == GetRealZoneText() or name == GetZoneText() then return true end
    if IsInInstance() then return name == GetInstanceInfo() end
    for _, q in ipairs(quests) do
        if q.onMap then return true end
    end
    return false
end

local function SortZones(a, b)
    if a.current ~= b.current then return a.current end
    return a.name < b.name
end

local function SortQuests(a, b)
    if a.complete ~= b.complete then return b.complete end
    return a.order < b.order
end

-- Tracked quests as zone groups, in display order.
local function Collect()
    local log = ReadLog()
    local timers = QuestTimers()
    local byZone, groups = {}, {}
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        local entry = id and log[id]
        if entry then
            local complete = C_QuestLog.IsComplete(id) and true or false
            local q = {
                id = id, order = i, logIndex = entry.logIndex, onMap = entry.onMap, complete = complete,
                timerEnd = timers[id],
                title = TitlePrefix(id) .. (entry.title or C_QuestLog.GetTitleForQuestID(id) or ""),
                item = QuestItem(entry.logIndex, complete),
            }
            q.lines = QuestLines(q)
            local zone = entry.zone or Text("OTHER", "Other")
            local group = byZone[zone]
            if not group then
                group = { name = zone, quests = {} }
                byZone[zone] = group
                groups[#groups + 1] = group
            end
            group.quests[#group.quests + 1] = q
        end
    end
    for _, group in ipairs(groups) do
        group.current = IsCurrentZone(group.name, group.quests)
        table.sort(group.quests, SortQuests)
    end
    table.sort(groups, SortZones)
    return groups
end

---------------------------------------------------------------------------
-- Wowhead link box
---------------------------------------------------------------------------
local function ShowLink(id)
    if not linkBox then
        local box = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")
        ButtonFrameTemplate_HidePortrait(box)
        box:SetSize(420, 90)
        box:SetPoint("CENTER", 0, 160)
        box:SetFrameStrata("DIALOG")
        box:SetToplevel(true)
        box:EnableMouse(true)
        if box.SetTitle then box:SetTitle("Wowhead (Ctrl+C to copy, Esc to close)") end
        if box.Inset then
            box.Inset:ClearAllPoints()
            box.Inset:SetPoint("TOPLEFT", 8, -28)
            box.Inset:SetPoint("BOTTOMRIGHT", -6, 8)
        end
        local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
        edit:SetPoint("LEFT", box.Inset or box, "LEFT", 14, 0)
        edit:SetPoint("RIGHT", box.Inset or box, "RIGHT", -10, 0)
        edit:SetHeight(20)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() box:Hide() end)
        edit:SetScript("OnEnterPressed", function() box:Hide() end)
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(box.url)
                self:HighlightText()
            end
        end)
        box.edit = edit
        linkBox = box
    end
    linkBox.url = WOWHEAD:format(WOWHEAD_LANG[GetLocale()] or "", id)
    linkBox.edit:SetText(linkBox.url)
    linkBox:Show()
    linkBox.edit:SetFocus()
    linkBox.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Quest menu (right-click)
---------------------------------------------------------------------------
local function Abandon(id)
    C_QuestLog.SetSelectedQuest(id)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
end

-- The focused (super-tracked) quest: the waypoint and the map follow it.
local function FocusedQuest()
    return C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
end

local function OpenMenu(block)
    local q = block.quest
    if not (q and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local id = q.id
    MenuUtil.CreateContextMenu(block, function(_, root)
        root:CreateTitle(q.title)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            local focused = FocusedQuest() == id
            root:CreateButton(focused and Text("STOP_SUPER_TRACK_QUEST", "Stop Focusing") or Text("SUPER_TRACK_QUEST", "Focus"),
                function() C_SuperTrack.SetSuperTrackedQuestID(focused and 0 or id) end)
        end
        local untrack = root:CreateButton(Text("OBJECTIVES_STOP_TRACKING", "Untrack Quest"), function()
            if not InCombatLockdown() then C_QuestLog.RemoveQuestWatch(id) end
        end)
        untrack:SetEnabled(not InCombatLockdown())
        local share = root:CreateButton(Text("SHARE_QUEST", "Share Quest"), function()
            QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(id))
        end)
        share:SetEnabled(IsInGroup() and C_QuestLog.IsPushableQuest(id) and not InCombatLockdown())
        local abandon = root:CreateButton(Text("ABANDON_QUEST", "Abandon Quest"))
        local confirm = PlainString(ABANDON_QUEST_CONFIRM)
        confirm = confirm and confirm:find("%%s") and confirm:format(q.title) or ('Abandon "%s"?'):format(q.title)
        abandon:CreateButton(confirm, function() Abandon(id) end)
        root:CreateButton("Wowhead link", function() ShowLink(id) end)
    end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Paint(block, hot)
    local suffix = hot and "Highlight" or ""
    local q = block.quest
    local state = (FocusedQuest() == q.id and "Focused") or (q.complete and "Finished") or "Header"
    block.title:SetTextColor(Color(state .. suffix))
    for n, line in ipairs(block.quest.lines) do
        block.lines[n]:SetTextColor(Color(line.kind .. suffix))
    end
end

local function ShowTooltip(block)
    if not (IsInGroup() and GameTooltip.SetQuestPartyProgress) then return end
    GameTooltip:SetOwner(block, "ANCHOR_LEFT")
    local ok = pcall(GameTooltip.SetQuestPartyProgress, GameTooltip, block.quest.id)
    if ok and GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

-- Spoken's Play button (the quest's accept line), made and bound by Spoken's
-- own functions; any failure turns it off for the session.
local function SpokenChanged()
    wipe(voiced)
    M:Refresh()
end

local function SetupSpoken()
    spoken = false
    local env, api = _G.VoiceOver, _G.Spoken
    local ui = type(env) == "table" and rawget(env, "QuestOverlayUI")
    if type(ui) ~= "table" or type(api) ~= "table" then return end
    for _, name in ipairs({ "ShowsTrackerButton", "BindPlayButton", "SetPlayButtonState", "FollowQueue" }) do
        if type(ui[name]) ~= "function" then return end
    end
    if type(api.DressBoxButton) ~= "function" or type(api.RegisterCallback) ~= "function" then return end
    spoken = { ui = ui, api = api }
    api:RegisterCallback("VOICE_PACKS_LOADED", SpokenChanged)
    api:RegisterCallback("PART_SWITCHED", function(part)
        if part == "quests" then SpokenChanged() end
    end)
    if type(ui.UpdateTrackerButtons) == "function" then hooksecurefunc(ui, "UpdateTrackerButtons", SpokenChanged) end
end

local function DressPlay(block, q)
    local voice = voiced[q.id]
    if voice == nil then
        voice = spoken.ui:ShowsTrackerButton(q.id) and true or false
        voiced[q.id] = voice
    end
    if not voice then
        if block.play then block.play:Hide() end
        return false
    end
    local button = block.play
    if not button then
        button = CreateFrame("Button", nil, block)
        button:SetSize(PLAY_SIZE, PLAY_SIZE)
        button:SetHitRectInsets(1, 1, 1, 1)
        spoken.api:DressBoxButton(button)
        button:SetBox(PLAY_BOX, PLAY_SIZE, PLAY_SIZE)
        button.setPlayState = spoken.ui.FollowQueue -- its glyph follows Spoken's queue (play, stop, replay)
        local back = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        back:SetPoint("TOPLEFT", 1, -1)
        back:SetPoint("BOTTOMRIGHT", -1, 1)
        back:SetColorTexture(0, 0, 0, 0.6)
        block.play = button
    end
    if button.questID ~= q.id then -- bound again only for another quest: binding sets new scripts
        button.soundData = nil
        spoken.ui:BindPlayButton(button, q.id, C_QuestLog.GetTitleForQuestID(q.id) or "", "KuroKit's quest tracker")
        spoken.ui:SetPlayButtonState(button)
    end
    button:Show()
    return true
end

-- Whether the block shows a Play button.
local function UpdatePlay(block, q)
    if not spoken then return false end
    local ok, shown = pcall(DressPlay, block, q)
    if ok then return shown end
    spoken = false
    for _, b in ipairs(blocks) do
        if b.play then b.play:Hide() end
    end
    return false
end

local function BlockLeave(block)
    if overlay and overlay:IsShown() and overlay.block == block and overlay:IsMouseOver() then return end
    if block.quest then Paint(block, false) end
    if GameTooltip:GetOwner() == block then GameTooltip:Hide() end
end

local function HideOverlay()
    if overlay and not InCombatLockdown() then
        overlay:Hide()
        overlay.block = nil
    end
end

-- The header button of Blizzard's (faded) block for the quest, if it has one.
local function BlizzardHeader(id)
    for _, name in ipairs(QUEST_MODULES) do
        local module = _G[name]
        local block = module and module.GetExistingBlock and module:GetExistingBlock(id)
        if block and block.HeaderButton then return block.HeaderButton end
    end
end

local function Overlay()
    if overlay then return overlay end
    overlay = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetAttribute("*type1", "click") -- any modifier: Blizzard's header decides
    overlay:SetScript("PostClick", function(self, button)
        if button == "RightButton" and self.block then OpenMenu(self.block) end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.block and self.block.quest then
            Paint(self.block, true)
            ShowTooltip(self.block)
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        local block = self.block
        HideOverlay()
        if block then BlockLeave(block) end
    end)
    return overlay
end

-- Puts the secure overlay over a quest, so a left-click reaches Blizzard's block.
-- Over the quest's text only: the quest icon and Play buttons stay clickable.
local function ShowOverlay(block)
    if InCombatLockdown() then return end
    local target = BlizzardHeader(block.quest.id)
    if not target then return end
    local right, top = block:GetRight(), block:GetTop()
    if not (right and top) then return end
    local o = Overlay()
    local scale = block:GetEffectiveScale() / o:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * scale, top * scale)
    o:SetSize(block.textWidth * scale, block:GetHeight() * scale)
    o:SetAttribute("*clickbutton1", target)
    o.block = block
    o:Show()
end

local function BlockOnEnter(block)
    if not block.quest then return end
    Paint(block, true)
    ShowTooltip(block)
    ShowOverlay(block)
end

-- Clicks the overlay didn't take (no Blizzard block for the quest, or combat).
local function BlockOnClick(block, button)
    local q = block.quest
    if not q then return end
    if button == "RightButton" then
        OpenMenu(block)
    elseif IsModifiedClick("CHATLINK") and ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
        ChatFrameUtil.TryInsertQuestLinkForQuestID(q.id)
    end
end

local function Block(i)
    local block = blocks[i]
    if block then return block end
    block = CreateFrame("Button", nil, tracker)
    block:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    block.title = block:CreateFontString(nil, "ARTWORK")
    block.title:SetFontObject(fonts.line)
    block.title:SetPoint("TOPRIGHT")
    block.title:SetJustifyH("RIGHT")
    block.title:SetWordWrap(true)
    block.lines = {}
    block:SetScript("OnEnter", BlockOnEnter)
    block:SetScript("OnLeave", BlockLeave)
    block:SetScript("OnClick", BlockOnClick)
    blocks[i] = block
    return block
end

local function Line(block, n)
    local line = block.lines[n]
    if line then return line end
    line = block:CreateFontString(nil, "ARTWORK")
    line:SetFontObject(fonts.line)
    line:SetJustifyH("RIGHT")
    line:SetWordWrap(true)
    block.lines[n] = line
    return line
end

-- Fills a quest block; returns its height. Text is right-aligned to the
-- screen edge; block.textWidth is the widest line, block.decoWidth how far
-- the title and its Play button reach from the block's right edge (the item
-- button goes left of that).
local function FillBlock(block, q, width)
    local textMax = width
    block.quest = q
    block:SetWidth(width)
    block.title:SetWidth(textMax)
    block.title:SetText(q.title)
    local titleWidth = math.min(block.title:GetStringWidth(), textMax)
    local widest = titleWidth
    local height = block.title:GetStringHeight()
    for n, data in ipairs(q.lines) do
        local line = Line(block, n)
        line:ClearAllPoints()
        line:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -(height + LINE_GAP))
        line:SetWidth(textMax)
        line:SetText(data.text)
        line:Show()
        widest = math.max(widest, math.min(line:GetStringWidth(), textMax))
        height = height + LINE_GAP + line:GetStringHeight()
    end
    for n = #q.lines + 1, #block.lines do block.lines[n]:Hide() end
    block:SetHeight(height)
    block.textWidth = widest
    -- The Play button, centred on the title's first line.
    local _, fontSize = block.title:GetFont()
    fontSize = fontSize or 12
    block.decoWidth = titleWidth
    if UpdatePlay(block, q) then
        block.play:ClearAllPoints()
        block.play:SetPoint("TOPRIGHT", block, "TOPRIGHT", -(block.decoWidth + PLAY_GAP), (PLAY_SIZE - fontSize) / 2)
        block.decoWidth = block.decoWidth + PLAY_GAP + PLAY_SIZE
    end
    -- Only the text and its buttons take the mouse: empty space left of a
    -- short quest lets clicks through to the world.
    block:SetHitRectInsets(math.max(0, width - widest), 0, 0, 0)
    Paint(block, false)
    return height
end

-- Counts the timer lines down, once a second while any is shown.
local function TickTimers()
    local any = false
    for i = 1, shownBlocks do
        local block = blocks[i]
        local q = block.quest
        if q and q.timerEnd then
            any = true
            local data = q.lines[1]
            PaintTimerLine(data)
            block.lines[1]:SetText(data.text)
            block.lines[1]:SetTextColor(Color(data.kind))
            if data.timerEnd <= GetTime() then M:Refresh() end
        end
    end
    if not any and timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

local function UpdateTimerTicker()
    for i = 1, shownBlocks do
        local q = blocks[i].quest
        if q and q.timerEnd then
            if not timerTicker then timerTicker = C_Timer.NewTicker(1, TickTimers) end
            return
        end
    end
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

local function ZoneOnClick(row)
    local folded = M.db.foldedZones
    folded[row.zone] = not folded[row.zone] or nil
    M:Refresh()
end

-- Zone headers look like Blizzard's tracker section headers (Forever's art):
-- its header font and bar, read from its faded quest section header. The bar
-- isn't stretched: only its right part shows, at Blizzard's own scale, as wide
-- as the zone name, and its left end fades out (a second piece of the same
-- art with an alpha gradient) where Blizzard's has its curl.
local function ZoneFont()
    local header = QuestObjectiveTracker and QuestObjectiveTracker.Header
    local text = header and header.Text
    return text and text.GetFontObject and text:GetFontObject() or fonts.header
end

local function ReadZoneArt()
    zoneArt = { height = ZONE_HEIGHT, below = 0 }
    local header = QuestObjectiveTracker and QuestObjectiveTracker.Header
    if not header then return end
    local height = PlainNumber(header:GetHeight())
    if height and height > 0 then zoneArt.height = height end
    local bg = header.Background
    local atlas = bg and bg.GetAtlas and PlainString(bg:GetAtlas())
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    local drawnWidth, drawnHeight = bg and PlainNumber(bg:GetWidth()), bg and PlainNumber(bg:GetHeight())
    if not (info and info.file and drawnWidth and drawnHeight and drawnWidth > 0 and drawnHeight > 0) then return end
    zoneArt.file = info.file
    zoneArt.left, zoneArt.right = info.leftTexCoord, info.rightTexCoord
    zoneArt.top, zoneArt.bottom = info.topTexCoord, info.bottomTexCoord
    zoneArt.uPerPixel = (info.rightTexCoord - info.leftTexCoord) / drawnWidth
    zoneArt.barHeight = drawnHeight
    -- Its height against the header: centre offset, and how far it hangs below.
    zoneArt.offset = 0
    local _, barY = bg:GetCenter()
    local _, headerY = header:GetCenter()
    if PlainNumber(barY) and PlainNumber(headerY) then zoneArt.offset = barY - headerY end
    zoneArt.below = math.max(0, (drawnHeight / 2 - zoneArt.offset) - zoneArt.height / 2)
end

-- The bar piece `width` px wide whose right end is `fromRight` px from the
-- art's right end.
local function BarPiece(texture, fromRight, width)
    local a = zoneArt
    local right = math.max(a.left, a.right - fromRight * a.uPerPixel)
    local left = math.max(a.left, right - width * a.uPerPixel)
    texture:SetTexCoord(left, right, a.top, a.bottom)
    texture:SetWidth(math.max(1, width))
end

local function ZoneRow(i)
    local row = zoneRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, tracker)
    row:SetHeight(zoneArt.height)
    if zoneArt.file then
        row.bar = row:CreateTexture(nil, "BACKGROUND")
        row.bar:SetTexture(zoneArt.file)
        row.bar:SetHeight(zoneArt.barHeight)
        row.bar:SetPoint("RIGHT", row, "RIGHT", 0, zoneArt.offset) -- moved to the screen edge when drawn
        row.fade = row:CreateTexture(nil, "BACKGROUND")
        row.fade:SetTexture(zoneArt.file)
        row.fade:SetHeight(zoneArt.barHeight)
        row.fade:SetPoint("RIGHT", row.bar, "LEFT")
        if CreateColor then
            pcall(row.fade.SetGradient, row.fade, "HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
        end
    end
    row.text = row:CreateFontString(nil, "ARTWORK")
    row.text:SetFontObject(fonts.zone)
    row.text:SetPoint("RIGHT")
    row.text:SetPoint("LEFT")
    row.text:SetJustifyH("RIGHT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", ZoneOnClick)
    -- Hover: the name lights up (no fold button: a folded zone shows its quest count).
    row:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function(self) self.text:SetTextColor(self.text:GetFontObject():GetTextColor()) end)
    zoneRows[i] = row
    return row
end

---------------------------------------------------------------------------
-- Quest item buttons (secure; placed by screen position, out of combat only)---------------------------------------------------------------------------
-- Quest item buttons (secure; placed by screen position, out of combat only)
---------------------------------------------------------------------------
local function UpdateCooldown(button)
    if not (button.logIndex and GetQuestLogSpecialItemCooldown and CooldownFrame_Set) then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(button.logIndex)
    if PlainNumber(start) and PlainNumber(duration) then CooldownFrame_Set(button.cooldown, start, duration, enable) end
end

local function ItemButton(i)
    local button = itemButtons[i]
    if button then return button end
    button = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    button:SetSize(ITEM_SIZE, ITEM_SIZE)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "item")
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    back:SetColorTexture(0, 0, 0, 0.8)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -1, 1)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", function(self)
        if not self.logIndex then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetQuestLogSpecialItem(self.logIndex)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemButtons[i] = button
    return button
end

local PlaceItems
local function QueueItems()
    if itemsQueued then return end
    itemsQueued = true
    ns:OutOfCombat(function()
        itemsQueued = false
        PlaceItems()
    end)
end

function PlaceItems()
    if InCombatLockdown() then QueueItems() return end
    local n = 0
    if tracker:IsShown() and not editing then
        for i = 1, shownBlocks do
            local block = blocks[i]
            local item = block.quest and block.quest.item
            local right, top = block:GetRight(), block:GetTop()
            if item and right and top then
                n = n + 1
                local button = ItemButton(n)
                local scale = block:GetEffectiveScale() / button:GetEffectiveScale()
                button:ClearAllPoints()
                button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (right - block.decoWidth - ITEM_GAP) * scale, top * scale)
                button:SetAttribute("item", "item:" .. item.id)
                button.icon:SetTexture(item.texture)
                button.count:SetText(item.charges > 1 and item.charges or "")
                button.logIndex = block.quest.logIndex
                button:Show()
                UpdateCooldown(button)
            end
        end
    end
    for i = n + 1, #itemButtons do
        itemButtons[i]:Hide()
        itemButtons[i].logIndex = nil
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- Blizzard's tracker hidden by another addon (we only ever fade it). Blizzard
-- hides it itself only when it has nothing to show, and then so do we.
function HiddenByAddon()
    return not editing and not ObjectiveTrackerFrame:IsShown()
end

local function MaxHeight()
    local height = PlainNumber(ObjectiveTrackerFrame:GetHeight())
    if not height or height < MIN_MAX_HEIGHT then return DEFAULT_MAX_HEIGHT end
    return height
end

local function Render()
    pending = false
    if not tracker or editing then return end
    HideOverlay()
    for i = 1, shownZones do zoneRows[i]:Hide() end
    for i = 1, shownBlocks do
        blocks[i]:Hide()
        blocks[i].quest = nil
    end
    shownZones, shownBlocks = 0, 0

    if not zoneArt then ReadZoneArt() end
    local groups = Collect()
    if #groups == 0 or M.db.collapsed or HiddenByAddon() then
        tracker:Hide()
        UpdateTimerTicker()
        PlaceItems()
        return
    end
    tracker:Show()

    local width, maxHeight = tracker:GetWidth(), MaxHeight()
    local y = 0
    local full = false
    for gi, group in ipairs(groups) do
        local groupTop = y
        if gi > 1 then y = y + ZONE_GAP end
        if y + zoneArt.height > maxHeight then break end
        shownZones = shownZones + 1
        local row = ZoneRow(shownZones)
        local folded = M.db.foldedZones[group.name]
        row.zone = group.name
        row.text:SetText(folded and ("%s (%d)"):format(group.name, #group.quests) or group.name)
        local headerWidth = row.text:GetStringWidth()
        row:SetHitRectInsets(math.max(0, width - headerWidth), 0, 0, 0)
        if row.bar then
            -- From the screen edge (under the fold button too) to just left of the name.
            local edge = math.max(0, (UIParent:GetRight() or 0) - (tracker:GetRight() or 0))
            local solid = math.min(width, headerWidth + ZONE_BAR_PAD) + edge
            row.bar:ClearAllPoints()
            row.bar:SetPoint("RIGHT", row, "RIGHT", edge, zoneArt.offset)
            BarPiece(row.bar, ZONE_BAR_SKIP, solid)
            BarPiece(row.fade, ZONE_BAR_SKIP + solid, math.min(ZONE_BAR_FADE, math.max(0, width + edge - solid)))
            row.fade:SetShown(solid < width + edge)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + zoneArt.height + zoneArt.below + ZONE_SPACING
        if not folded then
            local placed = 0
            for _, q in ipairs(group.quests) do
                local block = Block(shownBlocks + 1)
                local height = FillBlock(block, q, width)
                if y + height > maxHeight then
                    block:Hide()
                    block.quest = nil
                    full = true
                    break
                end
                shownBlocks = shownBlocks + 1
                placed = placed + 1
                block:ClearAllPoints()
                block:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, -y)
                block:Show()
                y = y + height + QUEST_GAP
            end
            if placed == 0 then -- no room for its first quest: no header without quests
                row:Hide()
                shownZones = shownZones - 1
                y = groupTop
            end
        end
        if full then break end
    end
    tracker:SetHeight(y)
    UpdateTimerTicker()
    PlaceItems()
end

function M:Refresh()
    if pending then return end
    pending = true
    C_Timer.After(0, function() ns.safecall(Render) end)
end

---------------------------------------------------------------------------
-- Blizzard's tracker: faded and click-through (shown again in Edit Mode)
---------------------------------------------------------------------------
local function MouseOff(frame)
    if type(frame) ~= "table" or not frame.EnableMouse or frame:IsForbidden() then return end
    if InCombatLockdown() and frame:IsProtected() then return end
    if frame:IsMouseEnabled() then frame:EnableMouse(false) end
end

local function MuteBlock(block)
    MouseOff(block)
    MouseOff(block.HeaderButton)
    MouseOff(block.ItemButton)
    MouseOff(block.poiButton)
    if type(block.usedLines) == "table" then
        for _, line in pairs(block.usedLines) do MouseOff(line) end
    end
    if type(block.addedRegions) == "table" then
        for region in pairs(block.addedRegions) do
            if type(region) == "table" then
                MouseOff(region)
                MouseOff(region.Bar)
            end
        end
    end
end

-- The scenario and widget sections share Blizzard's tooltip widget pool and
-- are never touched.
local function MuteModule(module)
    if type(module) ~= "table" or hookedModules[module] then return end
    if module == _G.ScenarioObjectiveTracker or module == _G.UIWidgetObjectiveTracker then return end
    hookedModules[module] = true
    if module.Header then MouseOff(module.Header.MinimizeButton) end
    if module.AddBlock then
        hooksecurefunc(module, "AddBlock", function(_, block)
            if block then MuteBlock(block) end
        end)
    end
    if type(module.usedBlocks) == "table" then
        for _, byTemplate in pairs(module.usedBlocks) do
            if type(byTemplate) == "table" then
                for _, block in pairs(byTemplate) do
                    if type(block) == "table" then MuteBlock(block) end
                end
            end
        end
    end
end

local function MuteBlizzard()
    local otf = ObjectiveTrackerFrame
    otf:SetAlpha(0)
    -- Edit Mode and the managed frame container set it back.
    hooksecurefunc(otf, "SetAlpha", function(self, alpha)
        if not editing and alpha ~= 0 then self:SetAlpha(0) end
    end)
    local master = otf.HeaderMenu or otf.Header
    if master then
        MouseOff(master.MinimizeButton)
        MouseOff(master.FilterButton)
    end
    for _, name in ipairs(MODULES) do MuteModule(_G[name]) end
    if type(otf.modules) == "table" then
        for _, module in ipairs(otf.modules) do MuteModule(module) end
    end
    if otf.AddModule then
        hooksecurefunc(otf, "AddModule", function(_, module)
            C_Timer.After(0, function() MuteModule(module) end)
        end)
    end
end

local function SetEditing(on)
    editing = on
    ObjectiveTrackerFrame:SetAlpha(on and 1 or 0)
    if on then
        tracker:Hide()
        PlaceItems()
    else
        M:Refresh()
    end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- The quest button: hides / shows the tracker. In the square minimap's hover
-- row (after the calendar) when that module is on; otherwise under Blizzard's
-- calendar button, shown while the mouse is over the minimap.
local function UpdateQuestButton()
    questButton.icon:SetAtlas(M.db.collapsed and "questlog-tab-icon-quest-inactive" or "questlog-tab-icon-quest")
end

local function QuestButtonTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(Text("TRACKER_HEADER_QUESTS", "Quests"), 1, 1, 1)
    GameTooltip:AddLine(M.db.collapsed and "Click: show the quest tracker" or "Click: hide the quest tracker", 0.8, 0.8, 0.8)
    if HiddenByAddon() then
        GameTooltip:AddLine("Another addon hides the game's quest tracker (e.g. Polestar's \"Hide the game's quest tracker\"), "
            .. "so this one stays hidden too.", 1, 0.5, 0.25, true)
    end
    GameTooltip:Show()
end

local function BuildQuestButton()
    local width = GameTimeFrame and PlainNumber(GameTimeFrame:GetWidth())
    local height = GameTimeFrame and PlainNumber(GameTimeFrame:GetHeight())
    if not (width and height and width > 0 and height > 0) then width, height = DEFAULT_BUTTON_SIZE, DEFAULT_BUTTON_SIZE end
    local button = CreateFrame("Button", "KuroKitQuestButton", Minimap)
    button:SetSize(width, height)
    ns.AddButtonPlate(button) -- the calendar button's plate, so the two match
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", BUTTON_INSET, -BUTTON_INSET)
    button.icon:SetPoint("BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(button.icon)
    glow:SetAtlas("questlog-tab-icon-quest")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    button:SetScript("OnClick", function(self)
        M.db.collapsed = not M.db.collapsed
        UpdateQuestButton()
        QuestButtonTooltip(self)
        M:Refresh()
    end)
    button:SetScript("OnEnter", QuestButtonTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    questButton = button
    UpdateQuestButton()

    local minimap = ns:GetModule("Minimap")
    if ns:IsModuleEnabled("Minimap") and minimap and minimap.AddHoverIcon and minimap.AddHoverIcon(button) then return end

    -- Blizzard's round minimap: under the addon menu button (itself under the
    -- calendar), or under the calendar without one.
    local above = (AddonCompartmentFrame and AddonCompartmentFrame:IsShown() and AddonCompartmentFrame) or GameTimeFrame
    if above then
        button:SetPoint("TOP", above, "BOTTOM", 0, -BUTTON_GAP)
    else
        button:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT")
    end
    button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    button:SetAlpha(0)
    local function HideUnlessHovered()
        if not (Minimap:IsMouseOver() or button:IsMouseOver()) then button:SetAlpha(0) end
    end
    Minimap:HookScript("OnEnter", function() button:SetAlpha(1) end)
    Minimap:HookScript("OnLeave", HideUnlessHovered)
    button:HookScript("OnEnter", function() button:SetAlpha(1) end)
    button:HookScript("OnLeave", HideUnlessHovered)
end

local function Build()
    local otf = ObjectiveTrackerFrame
    fonts.line = FontObject("ObjectiveTrackerLineFont", "ObjectiveFont", "GameFontHighlightSmall")
    fonts.header = FontObject("ObjectiveTrackerHeaderFont", "GameFontNormalMed2", "GameFontNormal")
    fonts.zone = ZoneFont()

    tracker = CreateFrame("Frame", "KuroKitQuestTracker", UIParent)
    tracker:SetPoint("TOPLEFT", otf, "TOPLEFT")
    tracker:SetPoint("TOPRIGHT", otf, "TOPRIGHT")
    tracker:SetHeight(1)
    tracker:SetFrameStrata("LOW")

    itemLayer = CreateFrame("Frame", nil, UIParent)
    itemLayer:SetAllPoints()
    itemLayer:SetFrameStrata("MEDIUM")
end

local function Start()
    if tracker or not ObjectiveTrackerFrame then return end
    Build()
    ns.safecall(BuildQuestButton) -- a failing minimap button mustn't stop the tracker
    ns.safecall(SetupSpoken)
    MuteBlizzard()
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function() SetEditing(true) end)
        EditModeManagerFrame:HookScript("OnHide", function() SetEditing(false) end)
    end
    -- The managed container or Edit Mode moved Blizzard's tracker (and so this one).
    hooksecurefunc(ObjectiveTrackerFrame, "SetPoint", function() M:Refresh() end)
    -- Shown / hidden by another addon's setting (or by Blizzard when empty).
    ObjectiveTrackerFrame:HookScript("OnShow", function() M:Refresh() end)
    ObjectiveTrackerFrame:HookScript("OnHide", function() M:Refresh() end)
    local refresh = function() M:Refresh() end
    for _, event in ipairs({
        "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED",
        "DISPLAY_SIZE_CHANGED", "SUPER_TRACKING_CHANGED",
    }) do
        ns:On(event, refresh)
    end
    ns:On("BAG_UPDATE_COOLDOWN", function()
        for _, button in ipairs(itemButtons) do
            if button:IsShown() then UpdateCooldown(button) end
        end
    end)
    ns:On("PLAYER_REGEN_DISABLED", HideOverlay)
    M:Refresh()
end

-- /kk questtracker art: size and textures of the minimap hover row's buttons.
local function DumpArt()
    local cluster = MinimapCluster
    local frames = {
        { "addon menu", AddonCompartmentFrame }, { "tracking", cluster and cluster.Tracking },
        { "tracking button", cluster and cluster.Tracking and cluster.Tracking.Button }, { "calendar", GameTimeFrame },
        { "quest", questButton },
    }
    for _, entry in ipairs(frames) do
        local name, frame = entry[1], entry[2]
        if frame then
            local w, h = frame:GetSize()
            ns:Print(("%s: %.1fx%.1f scale %.2f"):format(name, PlainNumber(w) or -1, PlainNumber(h) or -1, frame:GetScale()))
            for _, region in ipairs({ frame:GetRegions() }) do
                if region:IsObjectType("Texture") and region:IsShown() then
                    local tw, th = region:GetSize()
                    ns:Print(("   %s %s %.1fx%.1f"):format(region:GetDrawLayer(), tostring(region:GetAtlas() or region:GetTexture()),
                        PlainNumber(tw) or -1, PlainNumber(th) or -1))
                end
            end
        end
    end
end

function M:OnSlash(args)
    if (args or ""):lower():match("^art") then DumpArt() return end
    local otf = ObjectiveTrackerFrame
    ns:Print(("started %s; Blizzard tracker %s (alpha %s, shown %s); ours shown %s"):format(
        tostring(tracker ~= nil), otf and "exists" or "MISSING", otf and tostring(otf:GetAlpha()) or "-",
        otf and tostring(otf:IsShown()) or "-", tracker and tostring(tracker:IsShown()) or "-"))
    if not tracker then return end
    ns:Print(("quest tracker: %d zone(s), %d quest(s) shown, %d item button(s)%s"):format(
        shownZones, shownBlocks, #itemButtons, M.db.collapsed and "; hidden (minimap quest button)" or ""))
    local linked = 0
    for i = 1, shownBlocks do
        if blocks[i].quest and BlizzardHeader(blocks[i].quest.id) then linked = linked + 1 end
    end
    ns:Print(("%d of %d shown quest(s) have a Blizzard block for left-clicks"):format(linked, shownBlocks))
end

function M:OnEnable()
    if ObjectiveTrackerFrame then
        Start()
    else
        ns:On("ADDON_LOADED", function(_, name)
            if name == "Blizzard_ObjectiveTracker" then Start() end
        end)
    end
end
