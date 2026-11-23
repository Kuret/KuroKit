-- Graphics: graphics settings Blizzard's menu doesn't offer. Every row reads
-- and writes the game's own setting (CVar), which the game saves itself, so
-- this module costs nothing at runtime.
--
-- HDR (replaces HDRTuner): an on/off checkbox and sliders for the monitor-
-- dependent tuning (peak brightness, brightness, highlight factor). The game
-- saves those values itself; KuroKit's defaults are applied once, and the
-- "override" switches that make the game use them stay on.
-- Switching HDR on or off can leave colours scrambled until the render format
-- changes, so after a toggle the format is briefly switched to 32-bit float
-- and back to 16-bit float (the trick HDRTuner uses).
local _, ns = ...

local function CVarToggle(cvar)
    return function() return GetCVarBool(cvar) end,
        function(value) SetCVar(cvar, value and "1" or "0") end
end

local getSharpen, setSharpen = CVarToggle("ResampleAlwaysSharpen")

-- The world's brightest is HDRBrightness x HDRFactor, capped at
-- HDRPeakBrightness (nits). Defaults tuned in game for the current monitor.
local HDR_OVERRIDES = { useHDRPeakBrightness = "1", useHDRBrightness = "1" }
local HDR_DEFAULTS = { HDRPeakBrightness = 1400, HDRBrightness = 200, HDRFactor = 1.5 }
local FORMAT_REFRESH_DELAY = 0.25
local FORMAT_FLOAT16, FORMAT_FLOAT32 = "2", "3"

local function SetCVarIf(cvar, value)
    local current = GetCVar(cvar)
    if current ~= nil and current ~= value then SetCVar(cvar, value) end
end

local function ApplyHDROverrides()
    for cvar, value in pairs(HDR_OVERRIDES) do SetCVarIf(cvar, value) end
end

-- Clear the colours an HDR toggle can scramble: 32-bit float, then 16-bit float.
local function RefreshRenderFormat()
    if GetCVar("RenderFormat") == nil then return end
    C_Timer.After(FORMAT_REFRESH_DELAY, function()
        SetCVar("RenderFormat", FORMAT_FLOAT32)
        C_Timer.After(FORMAT_REFRESH_DELAY, function() SetCVar("RenderFormat", FORMAT_FLOAT16) end)
    end)
end

local function GetHDR() return GetCVarBool("HDROutput") end

local function SetHDR(value)
    if GetCVarBool("HDROutput") == (value and true or false) then return end
    if value then ApplyHDROverrides() end
    SetCVar("HDROutput", value and "1" or "0")
    RefreshRenderFormat()
end

-- Slider rows over the game's own HDR values.
local function CVarNumber(cvar, decimals)
    return function() return tonumber(GetCVar(cvar)) or HDR_DEFAULTS[cvar] end,
        function(value)
            ApplyHDROverrides()
            SetCVarIf(cvar, ("%." .. decimals .. "f"):format(value))
        end
end
local getPeak, setPeak = CVarNumber("HDRPeakBrightness", 0)
local getBright, setBright = CVarNumber("HDRBrightness", 0)
local getFactor, setFactor = CVarNumber("HDRFactor", 1)
local function Nits(v) return ("%d nits"):format(v) end

local options = {
    { type = "header", name = "Image" },
    { type = "checkbox", name = "Always sharpen", default = true, get = getSharpen, set = setSharpen,
      tooltip = "Apply the sharpening filter even at 100% render scale (game setting ResampleAlwaysSharpen). "
          .. "Strength follows the Sharpness slider in Blizzard's graphics settings." },
}
if GetCVar("HDROutput") ~= nil then
    options[#options + 1] = { type = "header", name = "HDR" }
    options[#options + 1] = { type = "checkbox", name = "HDR output", default = true, get = GetHDR, set = SetHDR,
        tooltip = "Needs HDR switched on in Windows and a monitor that supports it.\n\n"
            .. "|cffff4040Switching it can briefly flash bright colours.|r" }
    options[#options + 1] = { type = "slider", name = "Peak brightness", min = 100, max = 2000, step = 10,
        default = HDR_DEFAULTS.HDRPeakBrightness, get = getPeak, set = setPeak, format = Nits,
        tooltip = "Your monitor's peak brightness (see its specs or Windows' HDR calibration). Caps the brightest highlights." }
    options[#options + 1] = { type = "slider", name = "Brightness", min = 50, max = 1000, step = 10,
        default = HDR_DEFAULTS.HDRBrightness, get = getBright, set = setBright, format = Nits,
        tooltip = "Brightness of the world and the interface. Raise it until the UI looks as bright as your desktop." }
    options[#options + 1] = { type = "slider", name = "Highlight factor", min = 1, max = 2, step = 0.1,
        default = HDR_DEFAULTS.HDRFactor, get = getFactor, set = setFactor,
        format = function(v) return ("%.1fx"):format(v) end,
        tooltip = "How far bright parts of the world can go above Brightness (up to the peak). Raise in small steps; "
            .. "stop when the ground loses colour or texture." }
end

local M = ns:NewModule("Graphics", {
    title = "Graphics",
    group = "General",
    alwaysOn = true,
    desc = "Graphics settings Blizzard's menu doesn't offer: always-on sharpening and HDR output with its tuning. Takes over EllesmereUI's UI scale once (into the game's UI Scale setting).",
    options = options,
})

-- Defaults applied once, the first time KuroKit runs; after that the
-- checkboxes and sliders (the game's own settings) decide.
function M:OnEnable()
    -- UI scale (replaces EllesmereUI's fixed scale, which it sets on the UI
    -- directly with the game's own setting off): taken over once, while
    -- EllesmereUI is still installed, into the game's UI Scale setting
    -- (Options > Graphics), which keeps it from then on.
    if not self.db.uiScaleTaken then
        local eui = rawget(_G, "EllesmereUIDB")
        local scale = type(eui) == "table" and tonumber(eui.ppUIScale)
        if scale and scale > 0 then
            self.db.uiScaleTaken = true
            SetCVar("useUiScale", "1")
            SetCVar("uiScale", tostring(scale))
        end
    end
    if not self.db.sharpenSeeded then
        self.db.sharpenSeeded = true
        setSharpen(true)
    end
    if GetCVar("HDROutput") ~= nil then
        ApplyHDROverrides()
        if not self.db.hdrSeeded then
            self.db.hdrSeeded = true
            for cvar, value in pairs(HDR_DEFAULTS) do SetCVarIf(cvar, tostring(value)) end
            SetHDR(true)
        end
    end
end
