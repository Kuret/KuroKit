-- Fishing: one key (and a double right-click) to fish, and a fishing mode that
-- makes the bobber easy to spot and hear.
--
--  * Key (Key Bindings > KuroKit > Fishing): casts Fishing; while the line is
--    out it reels in (interacts with the bobber, which soft targeting picks).
--  * Double right-click in the world (fishing pole equipped): casts, or casts
--    again while already fishing.
--  * While fishing: sound effects at full volume, music / ambience / pet
--    sounds muted, sound kept on in the background; nameplates and NPC names
--    hidden; soft targeting set to find the bobber (with its icon). Everything
--    comes back RESTORE_DELAY seconds after the line ends, so recasting doesn't
--    flick music on and off. The saved values are kept in KuroKitDB until
--    restored, so a crash mid-fishing is repaired at the next login.
--
-- How the key and click cast without breaking secure rules: casting needs a
-- secure button, and only override bindings (set out of combat) can route a key
-- or a mouse button to it. So: out of combat the key is overridden to click our
-- secure Fishing button, or to INTERACTTARGET while fishing; a double
-- right-click overrides the right mouse button for that one click. Combat
-- clears every override (the key then does nothing until combat ends).
local _, ns = ...

local M = ns:NewModule("Fishing", {
    title = "Fishing",
    group = "Gameplay",
    desc = "Bind a key in Key Bindings > KuroKit to cast Fishing and reel in, or double right-click in the world with a "
        .. "fishing pole. While fishing, the splash is loud, music and nameplates are off, and the bobber is easy to target.",
})

BINDING_NAME_KUROKIT_FISH = "Fishing: cast and reel in"

local DOUBLE_CLICK = 0.2       -- max seconds between the two right-clicks
local DOUBLE_CLICK_MIN = 0.04  -- ignore bounces
local RESTORE_DELAY = 5        -- seconds after the line ends before settings come back

local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, [51294] = true,
    [88868] = true, [110410] = true, [131474] = true, [131476] = true, [131490] = true, [158743] = true,
}

-- Game settings while fishing. Nameplate settings are protected in combat, so
-- the whole set only changes out of combat.
local FISHING_CVARS = {
    Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_EnableSoundWhenGameIsInBG = "1",
    Sound_MasterVolume = "1", Sound_SFXVolume = "1",
    Sound_MusicVolume = "0", Sound_EnableAmbience = "0", Sound_EnablePetSounds = "0",
    nameplateShowEnemies = "0", nameplateShowFriendlyPlayers = "0",
    UnitNameNPC = "0", UnitNameNonCombatCreatureName = "0", UnitNameInteractiveNPC = "0",
    UnitNameFriendlySpecialNPCName = "0",
    SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "60",
    SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1",
}

local button          -- secure Fishing button (key)
local clickButton     -- secure Fishing button for the double right-click, casts on release
local keyOwner        -- owner of the key overrides
local mouseOwner      -- owner of the one-click right-button override
local fishing = false
local restoreTimer
local lastRightClick = 0

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function FishingName()
    return C_Spell.GetSpellName(7620) or C_Spell.GetSpellName(131474)
end

local function IsFishingSpell(spellID)
    if not spellID or Secret(spellID) then return false end
    if FISHING_SPELLS[spellID] then return true end
    return C_Spell.GetSpellName(spellID) == FishingName()
end

local function ChannelingFishing()
    local spellID = select(8, UnitChannelInfo("player"))
    return IsFishingSpell(spellID)
end

local function PoleEquipped()
    local itemID = GetInventoryItemID("player", INVSLOT_MAINHAND)
    if not itemID then return false end
    local subclass = select(7, C_Item.GetItemInfoInstant(itemID))
    return subclass == Enum.ItemWeaponSubclass.Fishingpole
end

---------------------------------------------------------------------------
-- Fishing mode (game settings), saved in KuroKitDB until restored
---------------------------------------------------------------------------
local function ApplyFishingMode()
    if InCombatLockdown() then return end
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    local db = M.db
    if not db.savedCVars then
        local saved = {}
        for cvar in pairs(FISHING_CVARS) do saved[cvar] = GetCVar(cvar) end
        db.savedCVars = saved
    end
    for cvar, value in pairs(FISHING_CVARS) do
        if GetCVar(cvar) ~= nil and GetCVar(cvar) ~= value then SetCVar(cvar, value) end
    end
end

local function RestoreSettings()
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    local saved = M.db.savedCVars
    if not saved or InCombatLockdown() then return end
    for cvar, value in pairs(saved) do
        if GetCVar(cvar) ~= nil and GetCVar(cvar) ~= value then SetCVar(cvar, value) end
    end
    M.db.savedCVars = nil
end

local function RestoreSoon()
    if restoreTimer then restoreTimer:Cancel() end
    restoreTimer = C_Timer.NewTimer(RESTORE_DELAY, function()
        restoreTimer = nil
        if not fishing then ns:OutOfCombat(RestoreSettings) end
    end)
end

---------------------------------------------------------------------------
-- Key: overridden to cast (pole equipped) or to reel in (fishing), out of combat
---------------------------------------------------------------------------
local function UpdateKey()
    if InCombatLockdown() then return end
    ClearOverrideBindings(keyOwner)
    local action
    if fishing then
        action = "INTERACTTARGET"
    elseif PoleEquipped() then
        action = "CLICK " .. button:GetName() .. ":LeftButton"
    end
    if not action then return end
    for _, key in ipairs({ GetBindingKey("KUROKIT_FISH") }) do
        SetOverrideBinding(keyOwner, true, key, action)
    end
end

-- The binding itself does nothing: when fishing is possible the key is
-- overridden to the secure button or the interact action.
function KuroKit_FishKey() end

---------------------------------------------------------------------------
-- Double right-click in the world
---------------------------------------------------------------------------
local debug = false -- /kk fishing debug: say why a double right-click didn't cast

local function Debug(text)
    if debug then ns:Print("fishing: " .. text) end
end

local function OverWorld()
    local foci = GetMouseFoci and GetMouseFoci()
    local focus = foci and foci[1]
    return focus == nil or focus == WorldFrame
end

-- Any rank of Fishing (each rank has its own spell ID on this client).
local function KnowsFishing()
    for spellID in pairs(FISHING_SPELLS) do
        if C_SpellBook.IsSpellKnown(spellID) then return true end
    end
    return false
end

-- nil when casting is possible, else the reason (for debug).
local function CannotCast()
    if not PoleEquipped() then return "no fishing pole equipped" end
    if not KnowsFishing() then return "Fishing not known" end
    if IsPlayerMoving() or IsFalling() then return "moving" end
    if IsFlying() or IsSwimming() then return "flying or swimming" end
    if IsStealthed() then return "stealthed" end
    if not HasFullControl() or UnitHasVehicleUI("player") then return "no control" end
end

local function OnMouseDown(_, mouseButton)
    if mouseButton ~= "RightButton" then return end
    if InCombatLockdown() then Debug("in combat") return end
    if IsMouseButtonDown("LeftButton") then return end
    if GetNumLootItems() > 0 then Debug("loot window open") return end
    if not OverWorld() then Debug("mouse over a window, not the world") return end
    local now = GetTime()
    local gap = now - lastRightClick
    lastRightClick = now
    if gap < DOUBLE_CLICK_MIN or gap > DOUBLE_CLICK then return end
    lastRightClick = 0
    local reason = CannotCast()
    if reason then Debug(reason) return end
    -- This click's release goes to the click button (casts on release); the
    -- override is cleared right after.
    SetOverrideBindingClick(mouseOwner, true, "BUTTON2", clickButton:GetName(), "LeftButton")
    Debug(("double-click (%.2f s): casting"):format(gap))
end

local function OnMouseUp(_, mouseButton)
    if mouseButton ~= "RightButton" then return end
    C_Timer.After(0, function()
        if not InCombatLockdown() then ClearOverrideBindings(mouseOwner) end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not IsFishingSpell(spellID) then return end
    fishing = true
    ApplyFishingMode()
    UpdateKey()
end

local function OnChannelStop(_, unit, _, spellID)
    if unit ~= "player" or not fishing then return end
    if spellID and not Secret(spellID) and not IsFishingSpell(spellID) then return end
    fishing = false
    ns:OutOfCombat(UpdateKey)
    RestoreSoon()
end

function M:OnSlash(args)
    if args and args:lower():match("^debug") then
        debug = not debug
        ns:Print("fishing debug " .. (debug and "on: double right-clicks say why they don't cast" or "off"))
    else
        ns:Print("/kk fishing debug: explain double right-clicks that don't cast")
    end
end

function M:OnEnable()
    button = CreateFrame("Button", "KuroKitFishingButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", FishingName())
    -- The double right-click's press may already have gone to turning the
    -- camera before our override exists, so this one casts on the release;
    -- and since the release then doesn't reach the camera, stop turning.
    clickButton = CreateFrame("Button", "KuroKitFishingClickButton", UIParent, "SecureActionButtonTemplate")
    clickButton:RegisterForClicks("AnyUp", "AnyDown")
    clickButton:SetAttribute("type", "spell")
    clickButton:SetAttribute("spell", FishingName())
    clickButton:SetAttribute("useOnKeyDown", false)
    clickButton:SetScript("PostClick", function(_, _, down)
        if not down then MouselookStop() end
    end)
    keyOwner = CreateFrame("Frame")
    mouseOwner = CreateFrame("Frame")

    -- A crash or disconnect while fishing left the fishing settings in place.
    RestoreSettings()
    fishing = ChannelingFishing()
    UpdateKey()

    ns:On("UNIT_SPELLCAST_CHANNEL_START", OnChannelStart)
    ns:On("UNIT_SPELLCAST_CHANNEL_STOP", OnChannelStop)
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() ns:OutOfCombat(UpdateKey) end)
    ns:On("UPDATE_BINDINGS", function() ns:OutOfCombat(UpdateKey) end)
    ns:On("GLOBAL_MOUSE_DOWN", OnMouseDown)
    ns:On("GLOBAL_MOUSE_UP", OnMouseUp)
    -- Entering combat: still allowed to change things in this event. Drop the
    -- overrides (no fishing casts in combat) and put the settings back.
    ns:On("PLAYER_REGEN_DISABLED", function()
        ClearOverrideBindings(keyOwner)
        ClearOverrideBindings(mouseOwner)
        RestoreSettings()
    end)
    ns:On("PLAYER_REGEN_ENABLED", function()
        UpdateKey()
        if fishing then ApplyFishingMode() end
    end)
    ns:On("PLAYER_LOGOUT", function()
        fishing = false
        RestoreSettings()
    end)
end
