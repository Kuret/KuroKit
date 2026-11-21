-- Errors: hide the red "spam" errors in the middle of the screen (not ready yet,
-- not enough mana, out of range, no target...). Useful errors such as "Inventory
-- is full" or "Quest log is full" still show.
--
-- Uses UIErrorsFrame's own per-type switch, so a hidden error also plays no
-- error voice. Types are only ever switched off, never back on during a
-- session: writing them back taints Blizzard's code. /kk off Errors + /reload
-- restores everything.
local _, ns = ...

local M = ns:NewModule("Errors", {
    title = "Hide Error Spam",
    group = "General",
    desc = "Hide the red cooldown, resource, range and target errors. Useful ones (bags full, quest log full) still show.",
})

-- Names after the LE_GAME_ERR_ prefix. Names this client doesn't have are skipped.
local SPAM = {
    -- not ready yet
    "ABILITY_COOLDOWN", "SPELL_COOLDOWN", "ITEM_COOLDOWN", "SPELL_FAILED_ANOTHER_IN_PROGRESS",
    -- not enough resource
    "OUT_OF_RAGE", "OUT_OF_ENERGY", "OUT_OF_MANA", "OUT_OF_FOCUS", "OUT_OF_COMBO_POINTS",
    "OUT_OF_POWER_DISPLAY", "OUT_OF_HEALTH",
    -- range / facing
    "OUT_OF_RANGE", "SPELL_OUT_OF_RANGE", "BADATTACKFACING", "BADATTACKPOS",
    -- no or wrong target
    "GENERIC_NO_TARGET", "NO_ATTACK_TARGET", "GENERIC_NO_VALID_TARGETS", "INVALID_ATTACK_TARGET",
}

local hiddenHere, hiddenElsewhere, missing = {}, {}, {}

function M:OnEnable()
    local f = UIErrorsFrame
    if not (f and f.SetMessageTypeEnabled) then
        ns:Print("Errors: this client has no per-type error switch; module inactive.")
        return
    end
    local already = BLACK_LISTED_MESSAGE_TYPES or {}
    for _, name in ipairs(SPAM) do
        local messageType = _G["LE_GAME_ERR_" .. name]
        if type(messageType) ~= "number" then
            missing[#missing + 1] = name
        elseif already[messageType] then -- leave Blizzard's / other addons' picks alone
            hiddenElsewhere[#hiddenElsewhere + 1] = name
        else
            f:SetMessageTypeEnabled(messageType, false)
            hiddenHere[#hiddenHere + 1] = name
        end
    end
end

function M:OnSlash()
    ns:Print(("Errors: hiding %d type(s): %s"):format(#hiddenHere, table.concat(hiddenHere, ", ")))
    if #hiddenElsewhere > 0 then
        print("  already hidden by the game or another addon: " .. table.concat(hiddenElsewhere, ", "))
    end
    if #missing > 0 then
        print("  not on this client: " .. table.concat(missing, ", "))
    end
end
