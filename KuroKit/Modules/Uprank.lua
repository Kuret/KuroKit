-- Spell uprank: when you learn a higher rank of a spell, every lower rank of
-- that spell on your action bars is replaced by the new one, with a line in
-- chat. Only learning triggers it, so a lower rank you place on purpose
-- afterwards stays. /kk uprank replaces every lower rank on the bars at once.
--
-- Pet abilities on your own bars follow the pet out now: a pet only knows its
-- highest rank, so an older rank on the bar is always replaced (also when a
-- different pet with other ranks comes out). The pet bar follows the pet's
-- spellbook by itself.
--
-- Placing actions needs no combat and an empty cursor, so the swap waits for
-- both. Covers the 180 normal action slots and the gamepad UI's own slots.
--
-- Cost: nothing until a spell is learned. A learned spell may not be in the
-- spellbook yet when the event fires, so it is looked up again on the next
-- SPELLS_CHANGED (given up after a few tries: recipes never show up there).
-- The pet's spellbook (a handful of slots) is read on SPELLS_CHANGED (the only
-- event a pet learning a rank fires), UNIT_PET and PET_BAR_UPDATE, at most once
-- per frame. The action slots are only walked when a rank went up or the pet's
-- spells changed.
local _, ns = ...

local M = ns:NewModule("Uprank", {
    title = "Spell Uprank",
    group = "Gameplay",
    desc = "When you or your pet learn a higher rank of a spell, the lower ranks on your action bars are replaced by "
        .. "it. /kk uprank replaces every lower rank on your bars right away.",
})

local MAX_ACTION_SLOT = 180
local MAX_GAMEPAD_SLOTS = 1000 -- upper bound on the gamepad UI's own slots
local MAX_TRIES = 5            -- lookups (SPELLS_CHANGED events) to wait for a learned spell to show up
local PLAYER = Enum.SpellBookSpellBank.Player
local PET = Enum.SpellBookSpellBank.Pet
local SPELL = Enum.SpellBookItemType.Spell

local learned = {}       -- spell ID -> lookups tried, until it shows up in the spellbook
local wanted = {}        -- spell names to uprank
local wantAll = false    -- /kk uprank: every spell
local wantPet = false    -- the pet's spells changed
local top = {}           -- highest known rank per spell name, read when upranking
local petTop = {}        -- the pet's spell ID per name
local petSlot = {}       -- pet spell ID -> its slot in the pet's spellbook
local petSeen            -- the pet spells last upranked for (spell IDs joined)
local petIDs = {}        -- scratch for the pet signature
local counts = {}        -- new spell ID -> slots swapped, for the chat line
local queued = false     -- waiting for combat to end
local waitingCursor = false
local petCheckQueued = false

local function Plain(v)
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end
end

local function ReadTop()
    wipe(top)
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if li and not li.offSpecID then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER)
                if info and info.itemType == SPELL and not info.isPassive and info.spellID and info.name
                   and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) then
                    top[info.name] = info.spellID
                end
            end
        end
    end
end

-- The pet's spells (stances and commands carry no spell ID); false without a pet.
local function ReadPet()
    wipe(petTop)
    wipe(petSlot)
    local n = C_SpellBook.HasPetSpells()
    if not n or n == 0 then return false end
    for slot = 1, n do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET)
        if info and info.spellID and info.name and not info.isPassive
           and not C_SpellBook.IsSpellBookItemLowRank(slot, PET) then
            petTop[info.name] = info.spellID
            petSlot[info.spellID] = slot
        end
    end
    return true
end

-- A spell on the bar you know, with a higher rank known under the same name;
-- or a spell you don't know that your pet has in another rank.
local function SwapSlot(action, player, pet)
    local kind, id = GetActionInfo(action)
    id = kind == "spell" and Plain(id)
    if not id then return end
    local name = C_Spell.GetSpellName(id)
    if not name then return end
    local new
    if C_SpellBook.IsSpellKnown(id) then
        new = player and (wantAll or wanted[name]) and top[name]
        if not new or new == id then return end
        if C_ActionBar.IsHighestSpellRank and C_ActionBar.IsHighestSpellRank(id) then return end
        C_Spell.PickupSpell(new)
    else
        new = pet and petTop[name]
        if not new or new == id then return end
        C_SpellBook.PickupSpellBookItem(petSlot[new], PET)
    end
    PlaceAction(action)
    ClearCursor()
    counts[new] = (counts[new] or 0) + 1
end

local function Report(all)
    if all and not next(counts) then
        ns:Print("no lower spell ranks on your action bars.")
        return
    end
    for id, n in pairs(counts) do
        local spell = C_Spell.GetSpellLink(id) or C_Spell.GetSpellName(id) or "?"
        local rank = C_Spell.GetSpellSubtext(id)
        if rank and rank ~= "" then spell = spell .. " (" .. rank .. ")" end
        ns:Print(("upranked %s on %d action %s."):format(spell, n, n == 1 and "slot" or "slots"))
    end
end

local Run

local function OnCursor()
    if not GetCursorInfo() then Run() end
end

function Run()
    if not (wantAll or wantPet or next(wanted)) then return end
    if InCombatLockdown() then
        if not queued then
            queued = true
            ns:OutOfCombat(Run)
        end
        return
    end
    queued = false
    if GetCursorInfo() then -- something is being dragged: wait until it's dropped
        if not waitingCursor then
            waitingCursor = true
            ns:On("CURSOR_CHANGED", OnCursor)
        end
        return
    end
    if waitingCursor then
        waitingCursor = false
        ns:Off("CURSOR_CHANGED", OnCursor)
    end

    local player = wantAll or next(wanted) ~= nil
    if player then ReadTop() end
    local pet = (wantAll or wantPet) and ReadPet()
    wipe(counts)
    for action = 1, MAX_ACTION_SLOT do SwapSlot(action, player, pet) end
    local gamepad = C_GamepadUI
    local action = gamepad and gamepad.GetFirstGamepadActionStorageSlotIndex and gamepad.GetFirstGamepadActionStorageSlotIndex()
    local last = action and action + MAX_GAMEPAD_SLOTS - 1
    while action and action <= last and gamepad.IsValidGamepadActionStorageSlotIndex(action) do
        SwapSlot(action, player, pet)
        action = action + 1
    end

    local all = wantAll
    wantAll, wantPet = false, false
    wipe(wanted)
    Report(all)
end

-- Learned spells that are in the spellbook now: a top rank (not passive)
-- marks its name for upranking.
local function Resolve()
    if not next(learned) then return end
    for id, tries in pairs(learned) do
        local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(id)
        if slot then
            learned[id] = nil
            local name = C_Spell.GetSpellName(id)
            if name and bank == PLAYER and not C_SpellBook.IsSpellBookItemPassive(slot, PLAYER)
               and not C_SpellBook.IsSpellBookItemLowRank(slot, PLAYER) then
                wanted[name] = true
            end
        elseif tries >= MAX_TRIES then
            learned[id] = nil
        else
            learned[id] = tries + 1
        end
    end
    Run()
end

-- The pet's spell IDs in spellbook order: a new rank or another pet changes it.
-- No pet (or its spells not loaded yet) leaves the last one, so dismissing and
-- calling the same pet walks nothing.
local function CheckPet()
    petCheckQueued = false
    local n = C_SpellBook.HasPetSpells()
    if not n or n == 0 then return end
    wipe(petIDs)
    for slot = 1, n do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET)
        petIDs[slot] = info and info.spellID or 0
    end
    local seen = table.concat(petIDs, ",")
    if seen == petSeen then return end
    petSeen = seen
    wantPet = true
    Run()
end

local function QueuePetCheck()
    if petCheckQueued then return end
    petCheckQueued = true
    C_Timer.After(0, CheckPet)
end

function M:OnSlash()
    wantAll = true
    Run()
end

function M:OnEnable()
    ns:On("LEARNED_SPELL_IN_SKILL_LINE", function(_, spellID)
        spellID = Plain(spellID)
        if not spellID then return end
        learned[spellID] = learned[spellID] or 0
        C_Timer.After(0, Resolve)
    end)
    ns:On("SPELLS_CHANGED", function()
        Resolve()
        QueuePetCheck()
    end)
    ns:On("PET_BAR_UPDATE", QueuePetCheck)
    ns:On("UNIT_PET", function(_, unit)
        if unit == "player" then QueuePetCheck() end
    end)
end
