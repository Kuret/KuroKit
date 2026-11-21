-- Graphics: shortcuts to graphics settings that Blizzard's menu doesn't offer.
-- Every row reads and writes the game's own setting (CVar), which the game saves
-- itself, so this module costs nothing at runtime.
local _, ns = ...

local function CVarToggle(cvar)
    return function() return GetCVarBool(cvar) end,
        function(value) SetCVar(cvar, value and "1" or "0") end
end

local getSharpen, setSharpen = CVarToggle("ResampleAlwaysSharpen")

ns:NewModule("Graphics", {
    title = "Graphics",
    group = "General",
    alwaysOn = true,
    desc = "Graphics settings Blizzard's menu doesn't offer, such as always-on sharpening.",
    options = {
        { type = "header", name = "Image" },
        { type = "checkbox", name = "Always sharpen", default = false, get = getSharpen, set = setSharpen,
          tooltip = "Apply the sharpening filter even at 100% render scale (game setting ResampleAlwaysSharpen). "
              .. "Strength follows the Sharpness slider in Blizzard's graphics settings." },
    },
})
