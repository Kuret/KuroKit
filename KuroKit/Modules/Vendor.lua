-- Vendor: at a merchant, repair everything (guild funds first) and sell grey items.
--
-- Order matters: repair first, sell after. The guild's share of a repair can only
-- be worked out from your own gold going down, so no sale money may land while
-- that is being measured.
--
-- Selling is a sweep, not one call: the server silently drops sell requests past
-- its rate limit, and items whose data isn't cached yet are skipped. So we count
-- greys, sell, wait, and repeat with a growing delay until the count hits zero or
-- stops moving.
local _, ns = ...

local M = ns:NewModule("Vendor", {
    title = "Repair & Sell Greys",
    group = "General",
    desc = "At a merchant: repair everything (guild funds first) and sell grey items.",
    defaults = { repairMode = "guild", sellGreys = true },
    options = {
        { type = "dropdown", key = "repairMode", name = "Auto repair",
          tooltip = "Repair all items when you open a merchant that can repair.",
          values = {
              { "guild", "Guild funds first", "The guild bank pays what your rank's allowance covers; you pay the rest." },
              { "own", "Own gold only" },
              { "off", "Off" },
          } },
        { type = "checkbox", key = "sellGreys", name = "Sell grey items",
          tooltip = "Sell all poor-quality (grey) items when you open a merchant." },
    },
})

-- v0.2.0 stored two checkboxes; fold them into the dropdown.
function M:OnLoad()
    local db = self.db
    if db.repair ~= nil or db.useGuild ~= nil then
        db.repairMode = db.repair == false and "off" or (db.useGuild == false and "own" or "guild")
        db.repair, db.useGuild = nil, nil
    end
end

local MEASURE_DELAY = 0.5 -- time for the repair debit to land before we read it
local SWEEP_BASE, SWEEP_MAX = 0.4, 1.6
local SWEEP_PASSES, SWEEP_STALLS = 12, 3

local merchantOpen = false
local visit = 0 -- bumped on every open/close; stale timers compare and bail

local function Money(copper)
    return GetMoneyString(copper, true)
end

-- Greys we could sell, plus slots whose item data hasn't loaded yet.
local function CountGreys()
    local greys, loading = 0, 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if info.quality == nil then
                    loading = loading + 1
                elseif info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                    greys = greys + 1
                end
            end
        end
    end
    return greys, loading
end

local function SellPass()
    local cm = C_MerchantFrame
    if cm and cm.SellAllJunkItems and (not cm.IsSellAllJunkEnabled or cm.IsSellAllJunkEnabled()) then
        cm.SellAllJunkItems()
        return
    end
    -- Fallback: sell greys one by one (right-click equivalent).
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue and not info.isLocked then
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end
end

-- Runs the sell sweep; calls onDone() when finished (also when nothing to sell).
local function SweepGreys(onDone)
    local myVisit = visit
    local startMoney, startCount = GetMoney(), CountGreys()
    local passes, stalls, delay, last = 0, 0, SWEEP_BASE, math.huge

    local function Finish()
        if myVisit ~= visit then return end
        local left = CountGreys()
        local sold, earned = startCount - left, GetMoney() - startMoney
        if sold > 0 and earned > 0 then
            ns:Print(("Sold %d grey item%s for %s"):format(sold, sold == 1 and "" or "s", Money(earned)))
        end
        if left > 0 then
            ns:Print(("%d grey item%s could not be sold."):format(left, left == 1 and "" or "s"))
        end
        if onDone then onDone() end
    end

    local function Pass()
        if myVisit ~= visit then return end
        local greys, loading = CountGreys()
        if greys == 0 and loading == 0 then return Finish() end

        if greys >= last then
            stalls = stalls + 1
            delay = math.min(delay * 2, SWEEP_MAX)
            -- New greys appearing (item data loaded) isn't a stall.
            if greys > last then stalls, delay = 0, SWEEP_BASE end
        else
            stalls, delay = 0, SWEEP_BASE
        end
        if stalls >= SWEEP_STALLS or passes >= SWEEP_PASSES then
            -- Last sale may still be in flight: give it a moment, then report.
            return C_Timer.After(delay, Finish)
        end

        last = greys
        passes = passes + 1
        if greys > 0 then SellPass() end
        C_Timer.After(delay, Pass)
    end

    if not M.db.sellGreys then
        if onDone then onDone() end
        return
    end
    Pass()
end

-- Returns "sent", cost, moneyBefore, usedGuild  |  "broke", cost  |  nil (nothing to do)
local function SendRepair()
    local mode = M.db.repairMode
    if mode == "off" or not CanMerchantRepair() then return end
    local cost, needed = GetRepairAllCost()
    if not needed or cost <= 0 then return end
    local guild = mode == "guild" and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() or false
    -- With guild funds, let the server split the bill (like Blizzard's button does);
    -- it pays what the guild allowance covers and charges you the rest.
    if not guild and GetMoney() < cost then return "broke", cost end
    local before = GetMoney()
    RepairAllItems(guild)
    return "sent", cost, before, guild
end

local function ReportRepair(cost, before)
    local remaining, stillNeeded = GetRepairAllCost()
    if not stillNeeded then remaining = 0 end
    local paid = cost - remaining
    if paid <= 0 then return remaining end
    local own = math.max(0, math.min(before - GetMoney(), paid))
    local guildPart = paid - own
    local line = "Repaired for " .. Money(paid)
    if guildPart > 0 then
        line = line .. (own > 0 and (" (guild paid " .. Money(guildPart) .. ")") or " (guild funds)")
    end
    ns:Print(line)
    return remaining
end

-- After selling, try once more if we couldn't afford the repair before.
local function RepairAfterSelling()
    if not merchantOpen then return end
    local result, cost, before = SendRepair()
    if result == "sent" then
        local myVisit = visit
        C_Timer.After(MEASURE_DELAY, function()
            if myVisit == visit then ReportRepair(cost, before) end
        end)
    elseif result == "broke" then
        ns:Print("Not enough gold to repair (" .. Money(cost) .. ").")
    end
end

local function OnMerchantShow()
    merchantOpen = true
    visit = visit + 1
    local myVisit = visit

    local result, cost, before = SendRepair()
    if result == "sent" then
        C_Timer.After(MEASURE_DELAY, function()
            if myVisit ~= visit then return end
            local remaining = ReportRepair(cost, before)
            SweepGreys(remaining > 0 and RepairAfterSelling or nil)
        end)
    elseif result == "broke" then
        SweepGreys(RepairAfterSelling) -- the grey money may cover it
    else
        SweepGreys()
    end
end

function M:OnEnable()
    ns:On("MERCHANT_SHOW", OnMerchantShow)
    ns:On("MERCHANT_CLOSED", function()
        merchantOpen = false
        visit = visit + 1
    end)
end
