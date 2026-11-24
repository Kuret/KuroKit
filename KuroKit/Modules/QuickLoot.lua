-- Quick loot: everything is taken the moment the loot opens, and Blizzard's
-- loot window stays invisible unless something is left in it (bags full, a
-- roll, a bind-on-pickup confirmation, locked loot). Holding the auto loot
-- toggle key (Shift by default) while looting shows the window as usual.
--
-- With the Loot Feed on, items your bags had no room for also show there, as
-- rows with a red "inventory is full", so you see what was left behind.
--
-- How: on LOOT_READY every slot is taken (LootSlot; locked slots skipped) and
-- the loot window is faded to alpha 0 (never hidden: it's Blizzard's). If
-- items are still there a moment later the window fades back in; LOOT_CLOSED
-- always restores it. The game's own auto loot delay between items
-- (autoLootRate, where the client has it) is set to 0 once.
-- Cost: nothing until you loot.
local _, ns = ...

local M = ns:NewModule("QuickLoot", {
    title = "Quick Loot",
    group = "Gameplay",
    desc = "Loot is taken instantly and the loot window stays out of sight unless something is left in it "
        .. "(bags full, a roll). Hold Shift while looting to see the window as usual.",
})

local REVEAL_DELAY = 0.4 -- seconds before a window with items still in it shows
local LEFT_COLOR = "|cffff5040"

local looting = false
local revealTimer

local function Restore()
    if revealTimer then revealTimer:Cancel(); revealTimer = nil end
    if LootFrame then LootFrame:SetAlpha(1) end
end

local function ItemsLeft()
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then return true end
    end
    return false
end

local function BagsFull()
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and family == 0 then return false end
    end
    return true
end

-- Items left behind for lack of bag space, as loot feed rows.
local function ReportLeft()
    if not (ns.LootFeedShow and BagsFull()) then return end
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then
            local icon, _, quantity, _, _, locked = GetLootSlotInfo(slot)
            local link = GetLootSlotLink(slot)
            if link and not locked then
                ns.LootFeedShow("left:" .. link, icon, quantity or 1, function()
                    return ("%s %s%s|r"):format(link, LEFT_COLOR, ERR_INV_FULL or "Inventory is full.")
                end)
            end
        end
    end
end

local function OnLootReady()
    if IsModifiedClick("AUTOLOOTTOGGLE") then return end -- the player wants to see it
    local count = GetNumLootItems()
    if count == 0 then return end
    looting = true
    if LootFrame then LootFrame:SetAlpha(0) end
    for slot = count, 1, -1 do
        local locked = select(6, GetLootSlotInfo(slot))
        if not locked then LootSlot(slot) end
    end
    if revealTimer then revealTimer:Cancel() end
    revealTimer = C_Timer.NewTimer(REVEAL_DELAY, function()
        revealTimer = nil
        if looting and ItemsLeft() then
            ReportLeft()
            Restore()
        end
    end)
end

function M:OnEnable()
    if not self.db.lootRateSeeded then
        if GetCVar("autoLootRate") ~= nil then SetCVar("autoLootRate", "0") end
        self.db.lootRateSeeded = true
    end
    ns:On("LOOT_READY", OnLootReady)
    ns:On("LOOT_CLOSED", function()
        looting = false
        Restore()
    end)
end
