-- Chat: minimal chat. Unhovered, only the chat text shows: no background, and
-- tabs / buttons / scroll bar appear while the mouse is over the chat
-- (Core/HoverReveal.lua, fade mode). The input box is plain (no border art) and
-- Edit Mode can put the chat right at the screen edge. Settings: timestamps and
-- that's it; the rest is always on.
--
-- Chat is the most taint-sensitive part of the 12.x UI: a tainted chat code path
-- breaks secret chat messages and sending in instances. So this module:
--  * never hooks any FCF_* / chat function and never writes Blizzard's chat
--    globals (e.g. CHAT_FRAME_TAB_*_ALPHA): it only changes alpha / visibility;
--  * never touches the alpha of frames Blizzard fades itself (tabs, button
--    frames, scroll bars: FCF_FadeIn/OutChatFrame): it fades their *contents*
--    (regions and child frames) instead, so the result is ours x Blizzard's;
--  * hides the background textures (CHAT_FRAME_TEXTURES) outright: Blizzard's
--    fade skips hidden ones and nothing re-shows them. Out of combat only (chat
--    frames can be protected while a temporary whisper window exists);
--  * picks up new windows (whisper tabs etc.) from our own event dispatch, a
--    frame later, outside Blizzard's call chains.
-- Note: the new-message flash on other tabs runs its own animation and may still
-- blink while the rest is hidden.
--
-- Idle fade: the chat text fades to IDLE_ALPHA IDLE_TIME seconds after the
-- last new message, hover or typing, and comes back with the next one. The chat
-- frame's own alpha (Blizzard fades its background and tabs, never the frame
-- itself). New messages are noticed by reading the newest entry's time in the
-- frame's message buffer, read only: calling the frame's fade functions from
-- an addon would write its fields and taint it.
local _, ns = ...

-- Default: 24-hour clock, hours and minutes. The game's own default is none;
-- applied once (first time KuroKit runs), after that it's the user's choice.
local DEFAULT_TIMESTAMPS = TIMESTAMP_FORMAT_HHMM_24HR or "%H:%M "

-- Same timestamp formats as Blizzard's Social settings (TIMESTAMP_FORMAT_*).
local function TimestampValues()
    local example = time({ year = 2010, month = 12, day = 15, hour = 15, min = 27, sec = 32 })
    local values = { { "none", TIMESTAMP_FORMAT_NONE or "None" } }
    for _, fmt in ipairs({
        TIMESTAMP_FORMAT_HHMM, TIMESTAMP_FORMAT_HHMMSS, TIMESTAMP_FORMAT_HHMM_AMPM,
        TIMESTAMP_FORMAT_HHMMSS_AMPM, TIMESTAMP_FORMAT_HHMM_24HR, TIMESTAMP_FORMAT_HHMMSS_24HR,
    }) do
        if fmt then values[#values + 1] = { fmt, date(fmt, example) } end
    end
    return values
end

local M = ns:NewModule("Chat", {
    title = "Minimal Chat",
    group = "Chat & Map",
    desc = "Only the chat text shows: tabs, buttons and the scroll bar appear while you hover the chat, and the background is gone. "
        .. "The chat turns faint 30 seconds after the last message, hover or typing.",
    options = {
        { type = "dropdown", name = "Timestamps", default = DEFAULT_TIMESTAMPS,
          tooltip = "Time in front of each chat line (the game's own Chat Timestamps setting).",
          values = TimestampValues(),
          get = function() return GetCVar("showTimestamps") end,
          set = function(value) SetCVar("showTimestamps", value) end },
    },
})

-- These used to be options; now always on. Drop their stored values.
function M:OnLoad()
    self.db.hideBackground, self.db.plainInput, self.db.screenEdge, self.db.hideDelay = nil, nil, nil, nil
end

local reveal

local function ChatFrameNames()
    return CHAT_FRAMES or {}
end

---------------------------------------------------------------------------
-- Background
---------------------------------------------------------------------------
local function ApplyBackground()
    if not CHAT_FRAME_TEXTURES then return end
    ns:OutOfCombat(function()
        for _, name in ipairs(ChatFrameNames()) do
            for _, suffix in ipairs(CHAT_FRAME_TEXTURES) do
                local region = _G[name .. suffix]
                if region then region:Hide() end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Plain input box: the box art faded out (alpha only: Blizzard shows/hides the
-- focus art itself) and the box shifted left so "Say:" starts where the chat
-- text starts. Blizzard anchors the box 5 px left of the chat and puts the
-- header 15 px into it. Plain setters only, from our own dispatch.
---------------------------------------------------------------------------
local EDITBOX_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local EDITBOX_X = -15

local function ApplyEditBoxes()
    ns:OutOfCombat(function()
        for _, name in ipairs(ChatFrameNames()) do
            local frame, editBox = _G[name], _G[name .. "EditBox"]
            if frame and editBox and frame.ScrollBar then
                for _, suffix in ipairs(EDITBOX_ART) do
                    local art = _G[name .. "EditBox" .. suffix]
                    if art then art:SetAlpha(0) end
                end
                editBox:ClearAllPoints()
                editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", EDITBOX_X, -2)
                editBox:SetPoint("RIGHT", frame.ScrollBar, "RIGHT", 8, 0)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Screen edge. Edit Mode clamps the chat by its selection box, which reaches
-- 32 px past the chat's left side to cover the button column. Narrowing that
-- box to the chat itself lets the chat reach the edge; Edit Mode recomputes its
-- clamp from the box, so the change sticks. Blizzard's own rule already puts the
-- buttons on the right of a chat at the left edge, but only re-checks on a
-- reload or re-dock, so we place them right away (plain setters on the button
-- frame, never Blizzard's FCF_* functions or fields).
---------------------------------------------------------------------------
local movedButtons = {}
local ALERT_ABOVE_BUTTONS = 27                  -- Blizzard's toast spot above the buttons
local ALERT_ABOVE_CHAT = ALERT_ABOVE_BUTTONS - 3 -- the same height (the buttons start 3 below the chat's top)

local function AnchorButtons(frame, side)
    local buttons, bg = frame.buttonFrame, frame.Background
    buttons:ClearAllPoints()
    if side == "right" then
        buttons:SetPoint("TOPLEFT", bg, "TOPRIGHT", 3, -3)
        buttons:SetPoint("BOTTOMLEFT", bg, "BOTTOMRIGHT", 3, 6)
    else
        buttons:SetPoint("TOPRIGHT", bg, "TOPLEFT", -3, -3)
        buttons:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", -3, 6)
    end
end

local function ApplyScreenEdge()
    ns:OutOfCombat(function()
        local main = ChatFrame1
        if main and main.Selection then
            local selection = main.Selection
            selection:ClearAllPoints()
            selection:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 60)
            selection:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 25, -32)
            local left, right, top, bottom = main:GetClampRectInsets()
            if left ~= 0 then
                main:SetClampRectInsets(0, right, top, bottom)
                -- Edit Mode placed the chat under the old clamp: put it back at its saved spot.
                ns.ReapplyEditModeAnchor(main)
            end
        end
        -- Buttons: on the right while there's no room for them on the left.
        for _, name in ipairs(ChatFrameNames()) do
            local frame = _G[name]
            local buttons = frame and frame.buttonFrame
            local left = frame and frame:GetLeft()
            if buttons and frame.Background and left then
                local noRoom = left < buttons:GetWidth() + 6
                    and left < (GetScreenWidth() - (frame:GetRight() or 0))
                if noRoom then
                    AnchorButtons(frame, "right")
                    movedButtons[buttons] = true
                elseif movedButtons[buttons] then
                    AnchorButtons(frame, frame.buttonSide == "right" and "right" or "left")
                    movedButtons[buttons] = nil
                end
                -- Toasts (Battle.net, Quick Join) sit above the main chat's
                -- button column: with the buttons moved right, above the chat's
                -- own left edge instead (at the screen edge, as before).
                if frame == DEFAULT_CHAT_FRAME and ChatAlertFrame then
                    ChatAlertFrame:ClearAllPoints()
                    if movedButtons[buttons] then
                        ChatAlertFrame:SetPoint("BOTTOMLEFT", frame.Background, "TOPLEFT", 0, ALERT_ABOVE_CHAT)
                    else
                        ChatAlertFrame:SetPoint("BOTTOMLEFT", buttons, "TOPLEFT", 0, ALERT_ABOVE_BUTTONS)
                    end
                end
            end
        end
        if reveal then reveal:Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Copy chat: a button in the chat button column (above the chat menu bubble)
-- opens a window with the selected chat tab's text, selected, ready for
-- Ctrl+C. Colour codes, links and icons are stripped to plain text; lines the
-- game keeps secret from addons are left out. Our own frames only.
---------------------------------------------------------------------------
local copyButton, copyWindow, copyEdit, copyScroll

local function PlainLine(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "(Battle.net name)") -- protected names can't be copied
    return text
end

local function ChatText(frame)
    local lines = {}
    if frame and frame.GetNumMessages then
        for i = 1, frame:GetNumMessages() do
            local text = frame:GetMessageInfo(i)
            if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
                lines[#lines + 1] = PlainLine(text)
            end
        end
    end
    return table.concat(lines, "\n")
end

local function BuildCopyWindow()
    local window = CreateFrame("Frame", "KuroKitChatCopy", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(window)
    window:SetSize(640, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.SetTitle then window:SetTitle("Copy chat (Ctrl+C to copy, Esc to close)") end
    if window.Inset then
        window.Inset:ClearAllPoints()
        window.Inset:SetPoint("TOPLEFT", 8, -28)
        window.Inset:SetPoint("BOTTOMRIGHT", -6, 8)
    end

    local scroll = CreateFrame("ScrollFrame", nil, window, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(580)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(self, width) edit:SetWidth(width) end)
    window:Hide()
    copyWindow, copyEdit, copyScroll = window, edit, scroll
end

local function ShowCopyWindow()
    if not copyWindow then BuildCopyWindow() end
    copyEdit:SetText(ChatText(SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME))
    copyWindow:Show()
    copyEdit:SetFocus()
    copyEdit:HighlightText()
    C_Timer.After(0, function() copyScroll:SetVerticalScroll(copyScroll:GetVerticalScrollRange()) end)
end

local function BuildCopyButton()
    local anchor = ChatFrameMenuButton
    if not anchor then return end
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(27, 26)
    button:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    button:SetFrameStrata(anchor:GetFrameStrata())
    button:SetNormalAtlas("chatframe-button-up")
    button:SetPushedAtlas("chatframe-button-down")
    button:SetHighlightAtlas("chatframe-button-highlight", "ADD")
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetSize(15, 15)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button:SetScript("OnClick", ShowCopyWindow)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy chat")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    copyButton = button
end

---------------------------------------------------------------------------
-- Idle fade
---------------------------------------------------------------------------
local IDLE_TIME = 30     -- seconds without activity before the chat fades
local IDLE_ALPHA = 0.5   -- the chat while idle (still readable)
local IDLE_FADE = 1.5    -- seconds for the fade out (back in at once)
local IDLE_POLL = 0.25
local idleAlpha = setmetatable({}, { __mode = "k" }) -- [chat frame] = alpha we set
local lastActivity = 0

local function NewestMessage(frame)
    local buffer = frame.historyBuffer
    if not (buffer and buffer.GetNumElements and buffer.GetEntryAtIndex) then return 0 end
    local n = buffer:GetNumElements()
    if not n or n == 0 then return 0 end
    local first, last = buffer:GetEntryAtIndex(1), buffer:GetEntryAtIndex(n)
    return math.max(first and first.timestamp or 0, last and last.timestamp or 0)
end

local function Active(frame)
    if frame:IsMouseOver() then return true end
    local tab = _G[frame:GetName() .. "Tab"]
    if tab and tab:IsShown() and tab:IsMouseOver() then return true end
    local editBox = frame.editBox
    return editBox and (editBox:HasFocus() or (editBox:IsShown() and editBox:GetText() ~= ""))
end

-- Every IDLE_POLL: is anything happening? (Sets idleWanted.)
local idleWanted = 1
local function IdleCheck()
    local now = GetTime()
    for _, name in ipairs(ChatFrameNames()) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            if Active(frame) then lastActivity = now end
            lastActivity = math.max(lastActivity, NewestMessage(frame))
        end
    end
    idleWanted = (now - lastActivity < IDLE_TIME) and 1 or IDLE_ALPHA
end

-- Every frame while a fade runs: the chat frames' alpha toward idleWanted
-- (out over IDLE_FADE, back in at once).
local function IdleFade(elapsed)
    for _, name in ipairs(ChatFrameNames()) do
        local frame = _G[name]
        if frame then
            local current = idleAlpha[frame] or frame:GetAlpha()
            local value = idleWanted >= current and idleWanted
                or math.max(idleWanted, current - elapsed * (1 - IDLE_ALPHA) / IDLE_FADE)
            if value ~= current or idleAlpha[frame] == nil then
                idleAlpha[frame] = value
                frame:SetAlpha(value)
            end
        end
    end
end

local function StartIdleFade()
    lastActivity = GetTime()
    local poller = CreateFrame("Frame")
    local waited = 0
    poller:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited >= IDLE_POLL then
            waited = 0
            ns.safecall(IdleCheck)
        end
        ns.safecall(IdleFade, elapsed)
    end)
end

---------------------------------------------------------------------------
-- Hover reveal
---------------------------------------------------------------------------
-- A Blizzard-faded frame's contents: its regions and direct child frames.
local function AddContents(list, frame)
    if not frame then return end
    for _, region in ipairs({ frame:GetRegions() }) do list[#list + 1] = region end
    for _, child in ipairs({ frame:GetChildren() }) do list[#list + 1] = child end
end

local function Targets(list)
    for _, name in ipairs(ChatFrameNames()) do
        local tab = _G[name .. "Tab"]
        if tab and tab:IsShown() then AddContents(list, tab) end
        local frame = _G[name]
        if frame and frame:IsShown() then
            AddContents(list, frame.buttonFrame)
            AddContents(list, frame.ScrollBar)
            AddContents(list, frame.ScrollToBottomButton)
        end
    end
    if GENERAL_CHAT_DOCK then AddContents(list, GENERAL_CHAT_DOCK.overflowButton) end
    AddContents(list, QuickJoinToastButton)
    if copyButton then list[#list + 1] = copyButton end
    AddContents(list, ChatFrameToggleVoiceDeafenButton)
    AddContents(list, ChatFrameToggleVoiceMuteButton)
end

local function Zone(list)
    for _, name in ipairs(ChatFrameNames()) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            list[#list + 1] = frame
            if frame.buttonFrame and frame.buttonFrame:IsShown() then list[#list + 1] = frame.buttonFrame end
        end
        local tab = _G[name .. "Tab"]
        if tab and tab:IsShown() then list[#list + 1] = tab end
    end
end

-- New/closed windows (whisper tabs, chat window changes): re-apply a frame later,
-- from our own dispatch.
local pending = false
local function WindowsChanged()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        ApplyBackground()
        ApplyEditBoxes()
        ApplyScreenEdge()
        reveal:Reapply()
        reveal:Refresh()
    end)
end

function M:OnEnable()
    BuildCopyButton()
    reveal = ns.NewHoverReveal({
        targets = Targets,
        zone = Zone,
        fade = true,
    })

    if not self.db.timestampsSeeded then
        self.db.timestampsSeeded = true
        if GetCVar("showTimestamps") == "none" then SetCVar("showTimestamps", DEFAULT_TIMESTAMPS) end
    end

    ApplyBackground()
    ApplyEditBoxes()
    ApplyScreenEdge()
    -- After moving the chat in Edit Mode: re-check the button side.
    EventRegistry:RegisterCallback("EditMode.Exit", function() RunNextFrame(ApplyScreenEdge) end, M)
    for _, event in ipairs({
        "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
        "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM",
    }) do
        ns:On(event, WindowsChanged)
    end
    ns:On("UI_SCALE_CHANGED", function() reveal:Refresh() end)
    ns:On("DISPLAY_SIZE_CHANGED", function() reveal:Refresh() end)

    reveal:Start()
    StartIdleFade()
end
