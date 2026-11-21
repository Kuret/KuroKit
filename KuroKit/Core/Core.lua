-- KuroKit core: namespace, events, saved settings, module registry, combat queue.
local ADDON, ns = ...
_G.KuroKit = ns -- handy for /dump KuroKit in game

ns.name = ADDON
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
ns.modules = {}
ns.moduleOrder = {}

local errorHandler = geterrorhandler

function ns:Print(...)
    print("|cff7fbfffKuroKit|r:", ...)
end

-- Errors: also shown in chat (once per distinct message), because Lua error
-- popups are usually off and a failing feature would otherwise just do nothing.
-- The error still goes to the game's handler (and BugSack, if installed).
local reported = {}
local function OnError(err)
    local msg = tostring(err)
    if not reported[msg] then
        reported[msg] = true
        print("|cffff5555KuroKit error:|r " .. msg)
    end
    return errorHandler()(err)
end
ns.OnError = OnError

-- Calls fn without letting one failing module break the rest.
local function safecall(fn, ...)
    return xpcall(fn, OnError, ...)
end
ns.safecall = safecall

---------------------------------------------------------------------------
-- Events: ns:On("EVENT", fn) / ns:Off("EVENT", fn). fn receives (event, ...).
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        safecall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

function ns:Off(event, fn)
    local list = handlers[event]
    if not list then return end
    local kept = {}
    for i = 1, #list do
        if list[i] ~= fn then kept[#kept + 1] = list[i] end
    end
    if #kept == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        handlers[event] = kept -- new table, so a dispatch in progress is unaffected
    end
end

---------------------------------------------------------------------------
-- Combat: protected frames can't be moved/shown/hidden in combat. Anything
-- that touches them goes through ns:OutOfCombat(fn).
---------------------------------------------------------------------------
local combatQueue = {}

function ns:OutOfCombat(fn)
    if InCombatLockdown() then
        combatQueue[#combatQueue + 1] = fn
    else
        safecall(fn)
    end
end

ns:On("PLAYER_REGEN_ENABLED", function()
    local queue = combatQueue
    combatQueue = {}
    for i = 1, #queue do safecall(queue[i]) end
end)

---------------------------------------------------------------------------
-- Saved settings: one account-wide table, shared by all characters.
--   KuroKitDB = { enabled = { [module] = bool }, modules = { [module] = {...} } }
---------------------------------------------------------------------------
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end
ns.applyDefaults = applyDefaults

---------------------------------------------------------------------------
-- Modules
--   local M = ns:NewModule("Name", {
--       title = "Shown in settings",  desc = "one line",
--       group = "Interface",          -- settings tab (General, Interface, Chat & Map, Gameplay, Developer)
--       alwaysOn = true,              -- pure settings module: no Enabled checkbox
--       defaults = { key = value, ... },
--       options = { ... },            -- settings rows, see Core/Options.lua
--       enabledByDefault = true,
--   })
--   function M:OnLoad() ... end                    -- optional: settings loaded (migrations); always runs
--   function M:OnEnable() ... end                  -- runs at PLAYER_LOGIN if enabled
--   function M:OnOptionChanged(key, value) ... end -- optional: apply a setting live
--   function M:OnSlash(args) ... end               -- optional: /kk name <args>
-- Settings live in M.db. Turning a module off takes effect after /reload
-- (hooks into Blizzard's UI can't be undone).
---------------------------------------------------------------------------
function ns:NewModule(name, opts)
    assert(not self.modules[name], "duplicate module " .. name)
    opts = opts or {}
    local m = {
        name = name,
        title = opts.title or name,
        desc = opts.desc or "",
        defaults = opts.defaults or {},
        options = opts.options,
        group = opts.group or "General",
        alwaysOn = opts.alwaysOn,
        enabledByDefault = opts.enabledByDefault ~= false,
    }
    self.modules[name] = m
    self.moduleOrder[#self.moduleOrder + 1] = name
    return m
end

function ns:GetModule(name)
    if self.modules[name] then return self.modules[name] end
    local lower = name:lower()
    for key, m in pairs(self.modules) do
        if key:lower() == lower then return m end
    end
end

function ns:IsModuleEnabled(name)
    local flag = KuroKitDB.enabled[name]
    if flag == nil then return self.modules[name].enabledByDefault end
    return flag
end

function ns:SetModuleEnabled(name, value)
    KuroKitDB.enabled[name] = value and true or false
end

ns:On("ADDON_LOADED", function(_, loaded)
    if loaded ~= ADDON then return end
    KuroKitDB = applyDefaults(KuroKitDB or {}, { enabled = {}, modules = {} })
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        KuroKitDB.modules[name] = applyDefaults(KuroKitDB.modules[name] or {}, m.defaults)
        m.db = KuroKitDB.modules[name]
        if m.OnLoad then safecall(m.OnLoad, m) end -- settings migrations, before the panel reads them
    end
    safecall(ns.BuildOptions, ns)
end)

ns:On("PLAYER_LOGIN", function()
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        if ns:IsModuleEnabled(name) and m.OnEnable then
            m.enabled = safecall(m.OnEnable, m)
        end
    end
end)
