-- Flight timer: while on a flight path, a bar at the top centre with
-- "origin » destination" and the time left; the flight master's map shows the
-- flight time in a destination's tooltip.
--
--  * Position: top centre, just above Blizzard's zone text area (the zone
--    name shown on entering an area). Nothing to position in KuroKit.
--  * Look: the player cast bar's art (frame, fill, spark) a bit larger, with
--    a soft shadow; the route in gold on the left and the time on the right
--    above it, outlined so they read on bright backgrounds.
--  * Time: this account's own recording of that exact flight when there is
--    one; otherwise an estimate from the route's length at
--    the speed learned from earlier flights (30.4 yards/s to start with).
--    Every flight that lands at its destination is recorded.
--  * "Land at the next flight path" (the game's leave button): the bar
--    switches to the next stop on the route and its time.
--  * A reload or relog mid-flight picks the flight up again (saved in
--    KuroKitDB with the server time until landing).
--
-- How: a post-hook on TakeTaxiNode reads the route (hops from GetNumRoutes /
-- TaxiGetNodeSlot, world positions from the taxi map) while the map is open;
-- the flight starts on PLAYER_CONTROL_LOST and ends once UnitOnTaxi is false.
-- Cost: nothing on the ground; while flying, one bar update per frame.
local _, ns = ...

local M = ns:NewModule("FlightTimer", {
    title = "Flight Timer",
    group = "Gameplay",
    desc = "While on a flight path: origin, destination and time left at the top of the screen. Follows the game's "
        .. "'land at next flight path' button. The flight master's map shows each destination's flight time.",
})

local DEFAULT_SPEED = 30.4  -- yards/second along the route before any flight is recorded
local SPEED_WEIGHT = 0.3    -- share of a new flight in the learned speed
local BOARD_WINDOW = 10     -- seconds from picking a destination to being on the taxi
local MIN_FLIGHT, MAX_FLIGHT = 10, 3600 -- recordable flight times
local ZONE_GAP = 10         -- timer bar to the zone text area below it
local SCALE = 1.15          -- a bit larger than the cast bar itself
local RESUME_SLACK = 120    -- seconds past the expected landing a saved flight still resumes
local TIME_ROOM = 48        -- the time left's room on the bar's right ("12:34"): the route text stops short of it
local ARROW = " \194\187 "  -- " » "

local bar
local pending     -- route picked on the flight map, until boarding
local flight      -- the flight under way

---------------------------------------------------------------------------
-- Routes
---------------------------------------------------------------------------
local function ShortName(name)
    return type(name) == "string" and (name:match("^([^,]+)") or name) or "?"
end

-- The route to taxi slot `slot` (flight map open): node names, node ids, the
-- yards flown to reach each node (straight hops), the total, and a key for
-- recorded times.
local function Route(slot)
    local hops = GetNumRoutes(slot)
    if not hops or hops < 1 then return nil end
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local bySlot = {}
    for _, node in ipairs(mapID and C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
        bySlot[node.slotIndex] = node
    end
    local function WorldPos(nodeSlot)
        local node = bySlot[nodeSlot]
        if not (node and node.position) then return nil end
        local _, pos = C_Map.GetWorldPosFromMapPos(mapID, node.position)
        return pos
    end
    local first = TaxiGetNodeSlot(slot, 1, true)
    local route = {
        names = { ShortName(TaxiNodeName(first)) },
        ids = { bySlot[first] and bySlot[first].nodeID },
        yards = { 0 },
    }
    local total, last = 0, WorldPos(first)
    for hop = 1, hops do
        local to = TaxiGetNodeSlot(slot, hop, false)
        local pos = WorldPos(to)
        if total and last and pos then
            local dx, dy = pos.x - last.x, pos.y - last.y
            total = total + math.sqrt(dx * dx + dy * dy)
        else
            total = nil
        end
        last = pos
        route.names[hop + 1] = ShortName(TaxiNodeName(to))
        route.ids[hop + 1] = bySlot[to] and bySlot[to].nodeID
        route.yards[hop + 1] = total
    end
    route.total = total and total > 0 and total or nil
    local fromKey = route.ids[1] or route.names[1]
    local toKey = route.ids[hops + 1] or route.names[hops + 1]
    route.key = fromKey .. ">" .. toKey
    return route
end

-- Seconds for a route and whether that's an estimate; nil when unknown.
local function Duration(route)
    local recorded = M.db.flightTimes and M.db.flightTimes[route.key]
    if recorded then return recorded, false end
    if route.total then return route.total / (M.db.speed or DEFAULT_SPEED), true end
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return ("%d:%02d:%02d"):format(seconds / 3600, seconds % 3600 / 60, seconds % 60)
    end
    return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
-- The first of `atlases` this client has (art differs between game versions).
local function SetAtlasFrom(texture, useSize, ...)
    for i = 1, select("#", ...) do
        local atlas = select(i, ...)
        if C_Texture.GetAtlasInfo(atlas) then
            texture:SetAtlas(atlas, useSize)
            return true
        end
    end
    return false
end


local function BuildBar()
    bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetFrameStrata("HIGH")
    bar:SetScale(SCALE)
    bar:SetSize(208, 11) -- the player cast bar's size
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")

    -- The cast bar's own drop shadow art, else a dark offset copy.
    local shadow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    if SetAtlasFrom(shadow, false, "castbar_shadow_embedded") then
        shadow:SetPoint("TOPLEFT", -3, 3)
        shadow:SetPoint("BOTTOMRIGHT", 5, -5)
    else
        shadow:SetPoint("TOPLEFT", 0, 0)
        shadow:SetPoint("BOTTOMRIGHT", 3, -3)
        shadow:SetColorTexture(0, 0, 0, 0.6)
    end
    local background = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
    background:SetAtlas("ui-castingbar-background")
    background:SetPoint("TOPLEFT", -1, 1)
    background:SetPoint("BOTTOMRIGHT", 1, -1)
    local border = bar:CreateTexture(nil, "ARTWORK", nil, 4)
    border:SetAtlas("ui-castingbar-frame")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    bar.spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    bar.spark:SetAtlas("ui-castingbar-pip")
    bar.spark:SetSize(8, 20)

    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.time:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 6)
    -- The route: up to the time's room (cut off with "..." should even the
    -- destination alone not fit).
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.text:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 6)
    bar.text:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -TIME_ROOM, 6)
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)
    ns.OutlineText(bar.text)
    ns.OutlineText(bar.time)
    bar:Hide()
end

-- Just above Blizzard's zone text area (ZoneTextFrame: where the zone and
-- PvP status show on entering an area), so the two never overlap.
local function PlaceBar()
    bar:ClearAllPoints()
    local zone = ZoneTextFrame
    if zone then
        bar:SetPoint("BOTTOM", zone, "TOP", 0, ZONE_GAP)
    else
        bar:SetPoint("BOTTOM", UIParent, "TOP", 0, -128 + ZONE_GAP)
    end
end

local shownSecond
local function UpdateBar()
    local elapsed = GetTime() - flight.start
    if flight.test and elapsed > flight.duration + 2 or not flight.test and elapsed > 2 and not UnitOnTaxi("player") then
        M.Land()
        return
    end
    local duration = flight.duration
    if duration then
        local progress = math.min(elapsed / duration, 1)
        bar:SetValue(progress)
        bar.spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * progress, 0)
        local second = math.floor(duration - elapsed + 0.5)
        if second ~= shownSecond then
            shownSecond = second
            bar.time:SetText(Clock(duration - elapsed))
        end
    else
        bar:SetValue(0)
        bar.time:SetText("")
    end
end

-- "origin » destination" in `width`: the origin shortened ("Nethergarde Ke...")
-- until it fits, the destination whole; a destination too long on its own
-- alone, cut off by the font string. (Once per flight.)
local ELLIPSIS = "\226\128\166"
local function FitRoute(fs, from, to, width)
    fs:SetText(from .. ARROW .. to)
    if fs:GetUnboundedStringWidth() <= width then return end
    local chars = {}
    for c in from:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
    for n = #chars - 1, 1, -1 do
        local short = table.concat(chars, "", 1, n):gsub("%s+$", "")
        fs:SetText(short .. ELLIPSIS .. ARROW .. to)
        if fs:GetUnboundedStringWidth() <= width then return end
    end
    fs:SetText(to)
end

local function ShowBar()
    if not bar then BuildBar() end
    PlaceBar()
    shownSecond = nil
    FitRoute(bar.text, flight.from, flight.to, bar:GetWidth() - TIME_ROOM)
    bar.spark:SetShown(flight.duration ~= nil)
    bar:SetScript("OnUpdate", UpdateBar)
    bar:Show()
    UpdateBar()
end

local function HideBar()
    if not bar then return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
end

---------------------------------------------------------------------------
-- Flight life cycle
---------------------------------------------------------------------------
-- Saved until landing, so a reload or relog picks it up again.
local function Save()
    M.db.current = flight and {
        from = flight.from, to = flight.to, key = flight.key, names = flight.names, yards = flight.yards,
        total = flight.total, duration = flight.duration, estimated = flight.estimated, early = flight.early,
        startServer = GetServerTime() - (GetTime() - flight.start),
    } or nil
end

local function Start(route)
    local duration, estimated = Duration(route)
    flight = {
        from = route.names[1], to = route.names[#route.names], key = route.key,
        names = route.names, yards = route.yards, total = route.total,
        duration = duration, estimated = estimated, start = GetTime(),
    }
    Save()
    ShowBar()
end

function M.Land()
    local f = flight
    flight = nil
    M.db.current = nil
    HideBar()
    if not f or f.early or f.test then return end
    local elapsed = GetTime() - f.start
    if elapsed < MIN_FLIGHT or elapsed > MAX_FLIGHT then return end
    M.db.flightTimes = M.db.flightTimes or {}
    M.db.flightTimes[f.key] = math.floor(elapsed + 0.5)
    if f.total then
        local speed = M.db.speed or DEFAULT_SPEED
        M.db.speed = speed + (f.total / elapsed - speed) * SPEED_WEIGHT
    end
end

-- The game's "land at the next flight path": the next stop ahead becomes the
-- destination; the time left is the distance to it at this flight's pace.
local function OnEarlyLanding()
    local f = flight
    if not (f and f.duration and f.total) or f.early then return end
    local elapsed = GetTime() - f.start
    local flown = math.min(elapsed / f.duration, 1) * f.total
    for i = 2, #f.names - 1 do
        local at = f.yards[i]
        if at and at > flown then
            f.to = f.names[i]
            f.duration = elapsed + (at - flown) * f.duration / f.total
            f.early = true
            Save()
            ShowBar()
            return
        end
    end
end

local function OnTakeTaxiNode(slot)
    pending = Route(slot)
    if pending then pending.at = GetTime() end
end

local function OnControlLost()
    if not pending or GetTime() - pending.at > BOARD_WINDOW then return end
    local route = pending
    pending = nil
    Start(route)
end

-- Login / reload while flying: the saved flight, if it fits.
local function Resume()
    local saved = M.db.current
    if not saved then return end
    local elapsed = GetServerTime() - (saved.startServer or 0)
    local limit = (saved.duration or MAX_FLIGHT) + RESUME_SLACK
    if not UnitOnTaxi("player") or elapsed < 0 or elapsed > limit then
        M.db.current = nil
        return
    end
    flight = saved
    flight.start = GetTime() - elapsed
    flight.startServer = nil
    ShowBar()
end

---------------------------------------------------------------------------
-- Flight map tooltip
---------------------------------------------------------------------------
local function OnNodeEnter(button)
    local slot = button:GetID()
    if TaxiNodeGetType(slot) ~= "REACHABLE" then return end
    local route = Route(slot)
    local duration = route and Duration(route)
    if not duration then return end
    GameTooltip:AddDoubleLine("Flight time", Clock(duration), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:Show()
end

-- /kk flighttimer test: a 30-second sample flight on the ground, to look at
-- the timer.
local TEST_SECONDS = 30
function M:OnSlash(args)
    if (args or ""):lower():match("^test") == nil then
        ns:Print("/kk flighttimer test: show a sample flight for " .. TEST_SECONDS .. " seconds")
        return
    end
    if flight and not flight.test then ns:Print("you're on a flight already") return end
    flight = { from = "Darkshire", to = "Stormwind", duration = TEST_SECONDS, start = GetTime(), test = true }
    ShowBar()
end

function M:OnEnable()
    hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
    hooksecurefunc("TaxiRequestEarlyLanding", OnEarlyLanding)
    if TaxiNodeOnButtonEnter then hooksecurefunc("TaxiNodeOnButtonEnter", OnNodeEnter) end
    ns:On("PLAYER_CONTROL_LOST", OnControlLost)
    ns:On("PLAYER_CONTROL_GAINED", function()
        if flight and not UnitOnTaxi("player") then M.Land() end
    end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        if not flight then Resume() end
    end)
end
