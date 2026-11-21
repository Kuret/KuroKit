-- /kk (or /kurokit): opens the settings panel. A few extras for troubleshooting:
--   /kk list                 modules and their state in chat
--   /kk <module> [args]      module-specific command, if it has one
local _, ns = ...

local function listModules()
    ns:Print("v" .. ns.version .. " modules:")
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        local state = ns:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
        print(("  %s %s - %s"):format(state, m.title, m.desc))
    end
end

SLASH_KUROKIT1 = "/kk"
SLASH_KUROKIT2 = "/kurokit"
SlashCmdList.KUROKIT = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" then
        ns:OpenOptions()
    elseif cmd == "list" then
        listModules()
    else
        local m = ns:GetModule(cmd)
        if m and m.OnSlash then
            ns.safecall(m.OnSlash, m, rest)
        else
            ns:Print("unknown command: " .. cmd .. "  (/kk opens settings, /kk list shows modules)")
        end
    end
end
