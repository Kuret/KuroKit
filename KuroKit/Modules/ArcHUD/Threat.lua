-- Arc HUD part: your threat on your target tints its arc's frame lines, in
-- a group only (solo everything you fight is on you anyway):
--   yellow   you're about to pull it (more threat than its target)
--   orange   it's on you, someone is close behind
--   red      it's on you
-- (the game's own threat colours, GetThreatStatusColor). Off with no
-- target, a friendly one, or none of your threat on it.
-- How: the threat status (0..3) may be secret, so it's never tested: one
-- status bar per colour over (k - 1)..k, its value the status, so the bar
-- for k is full from status k on and empty below; the bars stack, the
-- highest on top (opaque), so the highest reached shows. The bars' texture
-- is the arc's frame lines (ArcRimRight, tools/make_arcs.py rim()).
-- Cost: three SetValue calls per threat or target change.
local _, ns = ...
local A = ns.ArcHUD
local MEDIA, sides, Secret = A.MEDIA, A.sides, A.Secret

local TINT_ALPHA = 0.9
local LEVELS = 3

local bars = {}

local function Build()
    local s = sides.target
    for k = 1, LEVELS do
        local bar = CreateFrame("StatusBar", nil, s.frame)
        bar:SetAllPoints(s.frame)
        bar:SetOrientation("VERTICAL")
        bar:SetStatusBarTexture(MEDIA .. "ArcRimRight")
        bar:SetMinMaxValues(k - 1, k)
        bar:SetValue(0)
        bar:SetAlpha(TINT_ALPHA)
        -- (over the fills; the portrait shows through the socket's hole, the
        -- level badge stays on top)
        bar:SetFrameLevel(s.power:GetFrameLevel() + k)
        local r, g, b = GetThreatStatusColor(k)
        bar:SetStatusBarColor(r, g, b)
        bars[k] = bar
    end
end

local function SetStatus(status)
    for _, bar in ipairs(bars) do pcall(bar.SetValue, bar, status) end
end

local function Update()
    if not (IsInGroup() and UnitExists("target")) then SetStatus(0) return end
    local ok, hostile = pcall(UnitCanAttack, "player", "target")
    if not ok or Secret(hostile) or not hostile then SetStatus(0) return end
    local okStatus, status = pcall(UnitThreatSituation, "player", "target")
    if not okStatus or type(status) == "nil" then SetStatus(0) return end
    SetStatus(status)
end

A.AddPart({
    Build = Build,
    Enable = function()
        local function OnUnit(_, unit)
            if unit == nil or unit == "player" or unit == "target" then Update() end
        end
        ns:On("UNIT_THREAT_SITUATION_UPDATE", OnUnit)
        ns:On("UNIT_THREAT_LIST_UPDATE", OnUnit)
        ns:On("PLAYER_TARGET_CHANGED", Update)
        ns:On("GROUP_ROSTER_UPDATE", Update)
        ns:On("PLAYER_REGEN_ENABLED", Update)
        ns:On("PLAYER_ENTERING_WORLD", Update)
        ns:On("UNIT_FLAGS", OnUnit)
    end,
})
