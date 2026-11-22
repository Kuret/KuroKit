-- Quest reward marker: when a quest lets you choose a reward, the choice that
-- sells for the most (sell price x count) gets a gold coin on its icon, in
-- Blizzard's quest frame and in the quest log's reward list.
--
-- DialogueUI (on the keep-list) does the same in its own window and switches
-- the default quest frame off while it runs, so this shows only in the quest
-- log, or in the quest frame when DialogueUI is off.
--
-- How: a post-hook on QuestInfo_ShowRewards (runs after Blizzard laid out the
-- reward buttons); a coin texture of our own on the best button. Items not in
-- the cache yet are requested; GET_ITEM_INFO_RECEIVED marks again while the
-- rewards are on screen.
-- Cost: nothing until a reward list is shown.
local _, ns = ...

local M = ns:NewModule("QuestReward", {
    title = "Best Quest Reward",
    group = "Interface",
    desc = "When a quest lets you choose a reward, the one that sells for the most gets a gold coin on its icon "
        .. "(quest frame and quest log).",
})

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SIZE = 16

local coins = setmetatable({}, { __mode = "k" }) -- [reward button] = coin texture
local waiting = false -- a choice's item info is still loading

local function Coin(button)
    local coin = coins[button]
    if not coin then
        local icon = button.Icon or (button:GetName() and _G[button:GetName() .. "IconTexture"]) or button
        coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
        coin:SetTexture(COIN)
        coin:SetSize(COIN_SIZE, COIN_SIZE)
        coin:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
        coins[button] = coin
    end
    return coin
end

local function HideCoins()
    for _, coin in pairs(coins) do coin:Hide() end
end

-- Sell value of choice `index`: price x count; nil while the item loads, 0
-- when it can't be sold.
local function ChoiceValue(index, questLog)
    local link, count
    if questLog then
        link = GetQuestLogItemLink("choice", index)
        count = select(3, GetQuestLogChoiceInfo(index))
    else
        link = GetQuestItemLink("choice", index)
        count = select(3, GetQuestItemInfo("choice", index))
    end
    if not link then return nil end
    local price = select(11, C_Item.GetItemInfo(link))
    if price == nil then
        local itemID = C_Item.GetItemInfoInstant(link)
        if itemID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    return price * math.max(count or 1, 1)
end

local function Mark()
    HideCoins()
    waiting = false
    local info = QuestInfoFrame
    local rewards = info and info.rewardsFrame
    if not (rewards and rewards:IsVisible() and rewards.RewardButtons) then return end
    local questLog = info.questLog
    local best, bestValue, choices = nil, 0, 0
    for _, button in ipairs(rewards.RewardButtons) do
        if button:IsShown() and button.type == "choice" and button.objectType == "item" then
            choices = choices + 1
            local value = ChoiceValue(button:GetID(), questLog)
            if value == nil then
                waiting = true
            elseif value > bestValue then
                best, bestValue = button, value
            end
        end
    end
    if choices > 1 and best and not waiting then Coin(best):Show() end
end

function M:OnEnable()
    hooksecurefunc("QuestInfo_ShowRewards", Mark)
    ns:On("GET_ITEM_INFO_RECEIVED", function()
        if waiting then Mark() end
    end)
end
