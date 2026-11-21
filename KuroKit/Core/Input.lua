-- Input: are you playing with the controller right now, or mouse/keyboard?
-- Works with the game's gamepad UI off. Everything that follows the controller
-- (target tooltip, tooltip position) asks ns.PadActive() or listens with
-- ns.OnInputMode(fn(isPad)).
--
-- The game's own signal (GAME_PAD_ACTIVE_CHANGED) can lag, and typing alone may
-- not count, so we also watch for ourselves, read-only:
--  * keys: one 1x1 frame gets every key press and passes it straight on to the
--    game (propagated). Controller buttons arrive as PAD* keys -> controller;
--    any other key except Shift/Ctrl/Alt -> keyboard.
--  * mouse (only while on the controller): a click, or the pointer moving more
--    than a few pixels, unless the controller was just used or a stick is
--    being held (the game can move the hidden pointer itself then).
-- No polling while on mouse/keyboard; while on the controller a light 10 Hz
-- pointer check (no allocations unless the pointer moved).
local _, ns = ...

local MOUSE_MOVE = 12   -- pointer movement (cursor units) that counts as mouse use
local PAD_SETTLE = 0.5  -- seconds after controller use in which mouse input is ignored
local STICK_HELD = 0.2  -- stick deflection that counts as "controller in hand"
local POLL = 0.1

local pad = false
local reason = "start"
local lastPadUse = -10
local callbacks = {}

function ns.PadActive() return pad end
function ns.InputModeReason() return reason end
function ns.OnInputMode(fn) callbacks[#callbacks + 1] = fn end

local function PadEnabled()
    return GetCVar("GamePadEnable") == "1"
end

local watcher -- pointer check, runs only while on the controller

local function Set(isPad, why)
    isPad = isPad and PadEnabled() or false
    if isPad == pad then return end
    pad, reason = isPad, why
    if isPad then
        watcher.lastX, watcher.lastY = GetCursorPosition()
        watcher:Show()
        ns:On("GLOBAL_MOUSE_DOWN", watcher.OnMouseDown)
    else
        watcher:Hide()
        ns:Off("GLOBAL_MOUSE_DOWN", watcher.OnMouseDown)
    end
    for i = 1, #callbacks do ns.safecall(callbacks[i], pad) end
end

local function PadUsed(why)
    lastPadUse = GetTime()
    Set(true, why)
end

-- A stick held past STICK_HELD on the active controller (allocates: only called
-- when the pointer actually moved).
local function StickHeld()
    if not (C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetDeviceMappedState) then return false end
    local okID, id = pcall(C_GamePad.GetActiveDeviceID)
    if not okID or not id then return false end
    local ok, state = pcall(C_GamePad.GetDeviceMappedState, id)
    if not ok or type(state) ~= "table" then return false end
    for _, stick in ipairs(state.sticks or {}) do
        if type(stick) == "table" and type(stick.len) == "number" and stick.len > STICK_HELD then return true end
    end
    return false
end

local function MouseUse(why)
    if GetTime() - lastPadUse < PAD_SETTLE then return end
    Set(false, why)
end

watcher = CreateFrame("Frame")
watcher:Hide()
watcher.elapsed = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < POLL then return end
    self.elapsed = 0
    local x, y = GetCursorPosition()
    local moved = math.abs(x - (self.lastX or x)) + math.abs(y - (self.lastY or y)) > MOUSE_MOVE
    self.lastX, self.lastY = x, y
    if moved then
        if StickHeld() then lastPadUse = GetTime() else MouseUse("mouse moved") end
    end
end)
function watcher.OnMouseDown() MouseUse("mouse click") end

-- Keys: every press passes on to the game. Propagation can't be set in combat
-- (a /reload in combat), so keyboard input is only enabled together with it.
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true }
local keys = CreateFrame("Frame", nil, UIParent)
keys:SetSize(1, 1)
keys:SetPoint("TOPLEFT")
ns:OutOfCombat(function()
    keys:SetPropagateKeyboardInput(true)
    keys:EnableKeyboard(true)
end)
keys:SetScript("OnKeyDown", function(_, key)
    if type(key) ~= "string" or (issecretvalue and issecretvalue(key)) then return end
    if key:find("^PAD") then
        PadUsed("controller button")
    elseif not MODIFIERS[key] and GetTime() - lastPadUse > 0.1 then
        Set(false, "keyboard key")
    end
end)

-- The game's own signal counts too.
ns:On("GAME_PAD_ACTIVE_CHANGED", function(_, isActive)
    if issecretvalue and issecretvalue(isActive) then return end
    if isActive then PadUsed("game: controller") else Set(false, "game: mouse/keyboard") end
end)
ns:On("CVAR_UPDATE", function()
    if pad and not PadEnabled() then Set(false, "controller input turned off") end
end)
