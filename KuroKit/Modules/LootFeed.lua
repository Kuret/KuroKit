-- Loot feed: short-lived rows for what you gain: items (looted, received,
-- created), money, reputation, currencies and skill ups. Each row is an icon
-- and outlined text; it fades after a few seconds, and gaining the same thing
-- again adds to its row (and keeps it up) instead of opening another.
--
-- Position: where Blizzard's loot window appears (LootFrame, an Edit Mode
-- system: move "Loot Window" in Edit Mode to move the feed). While the loot
-- window itself is showing, the rows sit beside it. Newest row on top.
--
-- How: the game's own chat messages (CHAT_MSG_LOOT / CURRENCY / SKILL /
-- COMBAT_FACTION_CHANGE) are matched against its localized format strings, so
-- it works in every client language; money is the rise in GetMoney. Messages
-- the game keeps secret (restricted content) are skipped.
-- Cost: a few string matches per loot message; rows are pooled.
local _, ns = ...

local M = ns:NewModule("LootFeed", {
    title = "Loot Feed",
    group = "Gameplay",
    desc = "Short-lived rows for items, money, reputation, currencies and skill ups you gain, where the loot window "
        .. "appears (move 'Loot Window' in Edit Mode to move it).",
})

local ROW_HEIGHT = 22
local ROW_GAP = 2
local ICON_SIZE = 20
local MAX_ROWS = 7
local SHOW_TIME = 5      -- seconds a row stays before fading
local FADE_TIME = 0.6
local LOOT_WINDOW_GAP = 10

local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local REP_ICON = "Interface\\Icons\\Achievement_Reputation_01"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"

local holder
local rows = {}   -- shown, newest first
local pool = {}
local lastMoney

local function Secret(v) return issecretvalue and issecretvalue(v) end

---------------------------------------------------------------------------
-- Matching the game's format strings ("You receive loot: %sx%d.")
---------------------------------------------------------------------------
-- Pattern and capture order for global format string `key`; false when the
-- client has none. `loose`: may match inside a longer line.
local patterns = {}
local function Pattern(key, loose)
    local cached = patterns[key]
    if cached ~= nil then return cached end
    local fmt = _G[key]
    if type(fmt) ~= "string" or fmt == "" then patterns[key] = false return false end
    local order, out, i, n = {}, {}, 1, 0
    while true do
        local s, e, position, kind = fmt:find("%%(%d?)%$?([sd])", i)
        out[#out + 1] = fmt:sub(i, s and s - 1 or nil):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
        if not s then break end
        n = n + 1
        order[n] = tonumber(position) or n
        out[#out + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local pattern = table.concat(out)
    cached = { pattern = loose and pattern or ("^" .. pattern .. "$"), order = order }
    patterns[key] = cached
    return cached
end

-- Captures of `text` against format `key`, in the format's argument order.
local function Match(key, text, loose)
    local p = Pattern(key, loose)
    if not p then return nil end
    local caps = { text:match(p.pattern) }
    if caps[1] == nil then return nil end
    local args = {}
    for i, position in ipairs(p.order) do args[position] = caps[i] end
    return args[1], args[2]
end

local function FirstMatch(keys, text, loose)
    for _, key in ipairs(keys) do
        local a, b = Match(key, text, loose)
        if a then return a, b end
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Layout()
    local loot = LootFrame
    holder:ClearAllPoints()
    if loot and loot:IsShown() and loot:GetAlpha() > 0 then
        holder:SetPoint("TOPLEFT", loot, "TOPRIGHT", LOOT_WINDOW_GAP, 0)
    elseif loot then
        holder:SetPoint("TOPLEFT", loot, "TOPLEFT")
    else
        holder:SetPoint("TOPLEFT", UIParent, "LEFT", 40, 120)
    end
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
    end
end

local function Release(row)
    row:SetScript("OnUpdate", nil)
    row:Hide()
    row.key = nil
    pool[#pool + 1] = row
end

local function RowOnUpdate(row, elapsed)
    row.left = row.left - elapsed
    if row.left > 0 then return end
    local alpha = 1 + row.left / FADE_TIME
    if alpha > 0 then row:SetAlpha(alpha) return end
    for i, r in ipairs(rows) do
        if r == row then table.remove(rows, i) break end
    end
    Release(row)
    Layout()
end

local function NewRow()
    local row = table.remove(pool)
    if row then return row end
    row = CreateFrame("Frame", nil, holder)
    row:SetSize(300, ROW_HEIGHT)
    local iconBack = row:CreateTexture(nil, "BACKGROUND")
    iconBack:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
    iconBack:SetPoint("LEFT")
    iconBack:SetColorTexture(0, 0, 0, 0.8)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("CENTER", iconBack)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", iconBack, "RIGHT", 6, 0)
    row.text:SetJustifyH("LEFT")
    ns.OutlineText(row.text)
    return row
end

-- Shows (or adds to) the row for `key`: amount is added to its total;
-- Text(total) gives the row's text.
local function Show(key, icon, amount, Text)
    local row
    for i, r in ipairs(rows) do
        if r.key == key then
            row = r
            table.remove(rows, i)
            break
        end
    end
    if not row then
        row = NewRow()
        row.key, row.total = key, 0
        if #rows >= MAX_ROWS then Release(table.remove(rows)) end
    end
    row.total = row.total + (amount or 0)
    row.icon:SetTexture(icon)
    row.text:SetText(Text(row.total))
    row.left = SHOW_TIME
    row:SetAlpha(1)
    row:SetScript("OnUpdate", RowOnUpdate)
    row:Show()
    table.insert(rows, 1, row)
    Layout()
end

---------------------------------------------------------------------------
-- Gains
---------------------------------------------------------------------------
local ITEM_FORMATS = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL_SELF",
}
local CURRENCY_FORMATS = { "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }
local REP_FORMATS = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_GENERIC" }
local SKILL_FORMATS = { "ERR_SKILL_UP_SI" }

local function OnItem(_, text)
    if Secret(text) or type(text) ~= "string" then return end
    local link, count = FirstMatch(ITEM_FORMATS, text)
    if not link then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end
    local icon = C_Item.GetItemIconByID(itemID)
    Show("item:" .. itemID, icon, tonumber(count) or 1, function(total)
        return total > 1 and (link .. " |cffffffffx" .. total .. "|r") or link
    end)
end

local function OnCurrency(_, text)
    if Secret(text) or type(text) ~= "string" then return end
    local link, count = FirstMatch(CURRENCY_FORMATS, text)
    if not link then return end
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    Show("currency:" .. (info and info.name or link), info and info.iconFileID, tonumber(count) or 1, function(total)
        return total > 1 and (link .. " |cffffffffx" .. total .. "|r") or link
    end)
end

local function OnReputation(_, text)
    if Secret(text) or type(text) ~= "string" then return end
    local faction, amount = FirstMatch(REP_FORMATS, text, true)
    if not faction then return end
    Show("rep:" .. faction, REP_ICON, tonumber(amount) or 0, function(total)
        return total > 0 and ("%s |cffffffff+%d|r"):format(faction, total) or faction
    end)
end

local function OnSkill(_, text)
    if Secret(text) or type(text) ~= "string" then return end
    local skill, rank = FirstMatch(SKILL_FORMATS, text)
    if not skill then return end
    Show("skill:" .. skill, SKILL_ICON, 0, function()
        return ("%s |cffffffff%s|r"):format(skill, rank or "")
    end)
end

local function OnMoney()
    local money = GetMoney()
    local gained = lastMoney and money - lastMoney or 0
    lastMoney = money
    if gained <= 0 then return end
    Show("money", MONEY_ICON, gained, function(total)
        return "|cffffffff" .. GetCoinTextureString(total) .. "|r"
    end)
end

function M:OnEnable()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(300, 1)
    holder:SetFrameStrata("HIGH")
    lastMoney = GetMoney()
    Layout()
    ns:On("CHAT_MSG_LOOT", OnItem)
    ns:On("CHAT_MSG_CURRENCY", OnCurrency)
    ns:On("CHAT_MSG_COMBAT_FACTION_CHANGE", OnReputation)
    ns:On("CHAT_MSG_SKILL", OnSkill)
    ns:On("PLAYER_MONEY", OnMoney)
    -- Beside the loot window while it shows, in its place otherwise.
    ns:On("LOOT_OPENED", function() C_Timer.After(0, Layout) end)
    ns:On("LOOT_CLOSED", Layout)
    ns:On("EDIT_MODE_LAYOUTS_UPDATED", Layout)
    -- Quick Loot fades the loot window in when something is left in it.
    if LootFrame then hooksecurefunc(LootFrame, "SetAlpha", Layout) end
end
