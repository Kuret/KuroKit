-- Minimap: a square minimap in the bronze frame of WoW Forever's windows.
--   title bar     zone name (PvP colours), centred
--   top-left      FPS, mail / crafting-order indicator under it
--   top-right     clock (game clock format; left-click calendar, right-click
--                 stopwatch/alarm)
--   bottom-left   addon menu, tracking, calendar   (only while hovering)
--   bottom-right  coordinates                       (only while hovering)
-- Blizzard's header strip (zone button, Blizzard clock, day/night ring) is
-- concealed. Addon minimap buttons are hidden and listed in Blizzard's addon
-- compartment menu instead.
--
-- Edit Mode keeps size and position. The map stays where Blizzard puts it; the
-- Edit Mode box (MinimapCluster.Selection) is fitted to the square map so the
-- map snaps, clamps and reaches the screen edge by its own outline, not by the
-- old header area. The empty cluster no longer catches mouse clicks.
--
-- Taint / safety:
--  * Blizzard frames are concealed with alpha 0 + mouse off, never Hide or
--    SetParent; moved ones only get new anchors (plain setters).
--  * Only post-hooks (hooksecurefunc) on Blizzard functions that re-anchor the
--    mail indicator; nothing replaced.
--  * Blizzard re-applies its round mask only on load and when rotation
--    changes, so we re-apply the square look from our own events after those.
--  * Addon buttons are addon frames: reparented to an invisible holder. Their
--    menu entries call the real button's own scripts, with the button moved
--    under the menu entry first, so tooltips and menus they open from their
--    button appear next to the menu.
-- Cost: a 1 s ticker (clock, FPS), zone on zone events, a 10 Hz check only
-- while the mouse is over the map, a 5 Hz Edit Mode box check only in Edit Mode.
local _, ns = ...

local M = ns:NewModule("Minimap", {
    title = "Square Minimap",
    group = "Chat & Map",
    desc = "A square minimap in the bronze frame of Forever's windows, the zone in its title bar and FPS, clock and mail inside it; addon menu, tracking, "
        .. "calendar and coordinates appear while you hover it. Addon minimap buttons move into Blizzard's addon menu. "
        .. "Mouse wheel zooms; left-click the clock for the calendar, right-click for the stopwatch and alarm. Size and position stay in Edit Mode.",
})

-- Spelled as Questie's waypoint lines compare it (file paths aren't case
-- sensitive, Lua strings are): they then know the map is square.
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
-- Text and icon distance from the map's edges, clear of the rim.
local PAD = { top = 6, side = 8, bottom = 8 }
local HOVER_INTERVAL = 0.1

local function Secret(v) return issecretvalue and issecretvalue(v) end

---------------------------------------------------------------------------
-- Frame: the bronze rim of WoW Forever's own windows (the UI-Frame-Metal
-- pieces) with the windows' dark title bar above the map (the zone name sits
-- in it). The rim's outer edge is RIM_OUT past the map's sides and bottom (the
-- map's square corners inside the rim's corner cuts) and RIM_TITLE above its
-- top, where the bar's divider ends on the map's top edge. Built from the atlas pieces on frames of ours:
--  * the four corners at their own size; the top ones cropped below the
--    title bar's divider, all cropped at the box's middle if the map is ever
--    too small for two;
--  * the four edges repeating along their length ("_" atlases tile across,
--    "!" atlases tile down), as wide/deep as the corners.
-- RIM: where the rim's outer edge lies inside the pieces' art (left, right,
-- top, bottom), and how much of the top pieces is rim + title bar (art units,
-- measured on Forever's art). TITLE_BAND: the bar's dark band, down from the
-- rim's outer edge.
---------------------------------------------------------------------------
local RIM = { left = 12.5, right = 2.5, top = 13, bottom = 7.5, topDepth = 43 }
local RIM_OUT, RIM_TITLE = 3, 27
local TITLE_BAND = { from = 6, to = 23 }
-- Built-in margin around the frame: the Edit Mode box reaches this far past the
-- rim (and its drop shadow), so snapping the map into a screen corner leaves
-- this gap instead of the rim touching the screen edge.
local EDGE_GAP = 10
local RIM_ART = {
    tl = "UI-Frame-Metal-CornerTopLeft", tr = "UI-Frame-Metal-CornerTopRight",
    bl = "UI-Frame-Metal-CornerBottomLeft", br = "UI-Frame-Metal-CornerBottomRight",
    te = "_UI-Frame-Metal-EdgeTop", be = "_UI-Frame-Metal-EdgeBottom",
    le = "!UI-Frame-Metal-EdgeLeft", re = "!UI-Frame-Metal-EdgeRight",
}
local rim -- { box, pieces = {}, info = {} }
local FitEditModeBox -- defined below

local function Cut(texture, info, u1, u2, v1, v2)
    local l, t = info.leftTexCoord, info.topTexCoord
    local w, h = info.rightTexCoord - l, info.bottomTexCoord - t
    texture:SetTexCoord(l + w * u1, l + w * u2, t + h * v1, t + h * v2)
end

-- Lay the pieces out for a box of w x h (the rim's outer edge).
local function LayoutRim(_, w, h)
    local I, p = rim.info, rim.pieces
    local cornerW, topH, bottomH0 = I.tl.width, RIM.topDepth, I.bl.height
    local cl = math.min(cornerW, w / 2 + RIM.left)
    local cr = math.min(cornerW, w / 2 + RIM.right)
    local bh = math.min(bottomH0, h + RIM.top + RIM.bottom - topH)
    local gapX = w + RIM.left + RIM.right - cl - cr
    local gapY = h + RIM.top + RIM.bottom - topH - bh
    p.tl:SetSize(cl, topH); Cut(p.tl, I.tl, 0, cl / cornerW, 0, topH / I.tl.height)
    p.tr:SetSize(cr, topH); Cut(p.tr, I.tr, 1 - cr / cornerW, 1, 0, topH / I.tr.height)
    p.bl:SetSize(cl, bh); Cut(p.bl, I.bl, 0, cl / cornerW, 1 - bh / bottomH0, 1)
    p.br:SetSize(cr, bh); Cut(p.br, I.br, 1 - cr / cornerW, 1, 1 - bh / bottomH0, 1)
    local te, be, le, re = I.te, I.be, I.le, I.re
    p.te:SetHeight(topH)
    p.te:SetTexCoord(0, gapX / te.width, te.topTexCoord, te.topTexCoord + (te.bottomTexCoord - te.topTexCoord) * topH / te.height)
    p.be:SetHeight(bh)
    p.be:SetTexCoord(0, gapX / be.width, be.bottomTexCoord - (be.bottomTexCoord - be.topTexCoord) * bh / be.height, be.bottomTexCoord)
    p.le:SetWidth(cl)
    p.le:SetTexCoord(le.leftTexCoord, le.leftTexCoord + (le.rightTexCoord - le.leftTexCoord) * cl / le.width, 0, gapY / le.height)
    p.re:SetWidth(cr)
    p.re:SetTexCoord(re.rightTexCoord - (re.rightTexCoord - re.leftTexCoord) * cr / re.width, re.rightTexCoord, 0, gapY / re.height)
    local roomX, roomY = gapX > 0.01, gapY > 0.01
    for key, piece in pairs(p) do
        piece:SetShown((key ~= "te" and key ~= "be" or roomX) and (key ~= "le" and key ~= "re" or roomY))
    end
end

local function BuildRim()
    local info = {}
    for key, name in pairs(RIM_ART) do
        info[key] = C_Texture.GetAtlasInfo(name)
        if not info[key] then return end -- art missing: no frame rather than a broken one
    end
    local holder = CreateFrame("Frame", nil, Minimap)
    holder:SetAllPoints(Minimap)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 3)
    local box = CreateFrame("Frame", nil, holder)
    box:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -RIM_OUT, RIM_TITLE)
    box:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", RIM_OUT, -RIM_OUT)
    rim = { box = box, info = info, pieces = {} }
    local p = rim.pieces
    for key, i in pairs(info) do
        local tex = holder:CreateTexture(nil, "ARTWORK")
        local across = key == "te" or key == "be"
        local down = key == "le" or key == "re"
        tex:SetTexture(i.file or i.filename, across and "REPEAT" or "CLAMP", down and "REPEAT" or "CLAMP")
        tex:SetTexelSnappingBias(0) -- drawn unsharpened, as Blizzard draws this frame
        tex:SetSnapToPixelGrid(false)
        p[key] = tex
    end
    p.tl:SetPoint("TOPLEFT", box, "TOPLEFT", -RIM.left, RIM.top)
    p.tr:SetPoint("TOPRIGHT", box, "TOPRIGHT", RIM.right, RIM.top)
    p.bl:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -RIM.left, -RIM.bottom)
    p.br:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", RIM.right, -RIM.bottom)
    p.te:SetPoint("TOPLEFT", p.tl, "TOPRIGHT"); p.te:SetPoint("TOPRIGHT", p.tr, "TOPLEFT")
    p.be:SetPoint("BOTTOMLEFT", p.bl, "BOTTOMRIGHT"); p.be:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.le:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT"); p.le:SetPoint("BOTTOMLEFT", p.bl, "TOPLEFT")
    p.re:SetPoint("TOPRIGHT", p.tr, "BOTTOMRIGHT"); p.re:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")
    box:SetScript("OnSizeChanged", LayoutRim)
    local w, h = box:GetSize()
    if w and w > 0 then LayoutRim(box, w, h) end
end

---------------------------------------------------------------------------
-- Square look (re-applied after Blizzard's UpdateMinimapConfig)
---------------------------------------------------------------------------
local function ApplySquare()
    Minimap:SetMaskTexture(SQUARE_MASK)
    MinimapCompassTexture:SetAlpha(0)
    if MinimapCompassTextureUnderlay then MinimapCompassTextureUnderlay:SetAlpha(0) end
    -- Quest / dig-site area rings are drawn for a round map.
    if Minimap.SetArchBlobRingScalar then
        Minimap:SetArchBlobRingScalar(0)
        Minimap:SetArchBlobRingAlpha(0)
        Minimap:SetQuestBlobRingScalar(0)
        Minimap:SetQuestBlobRingAlpha(0)
    end
end

---------------------------------------------------------------------------
-- Edit Mode box: fitted to the square map + its frame + EDGE_GAP. Edit Mode snaps and
-- clamps by this box (GetScaledSelectionSides / GetSelectionOffset read its
-- TOPLEFT and BOTTOMRIGHT anchors), so the map behaves like the whole system.
---------------------------------------------------------------------------
local fitted = {}

FitEditModeBox = function()
    local cluster = MinimapCluster
    local selection = cluster and cluster.Selection
    if not selection or InCombatLockdown() then return end
    local cl, cb, cw, ch = cluster:GetRect()
    local ml, mb, mw, mh = Minimap:GetRect()
    if not (cl and ml) then return end
    local k = Minimap:GetEffectiveScale() / cluster:GetEffectiveScale()
    local o = (RIM_OUT + EDGE_GAP) * k
    local left = ml * k - cl - o
    local bottom = mb * k - cb - o
    local right = (ml + mw) * k - (cl + cw) + o
    local top = (mb + mh) * k - (cb + ch) + (RIM_TITLE + EDGE_GAP) * k
    if fitted.left == left and fitted.top == top and fitted.right == right and fitted.bottom == bottom then return end
    fitted.left, fitted.top, fitted.right, fitted.bottom = left, top, right, bottom
    selection:ClearAllPoints()
    selection:SetPoint("TOPLEFT", cluster, "TOPLEFT", left, top)
    selection:SetPoint("BOTTOMRIGHT", cluster, "BOTTOMRIGHT", right, bottom)
    cluster:SetClampRectInsets(left, right, top, bottom)
    -- Edit Mode placed the map under the old clamp (it applies saved positions
    -- before we run): put it back at its saved spot. No-op while Edit Mode is open.
    ns.ReapplyEditModeAnchor(cluster)
end

-- While Edit Mode is open the map can be resized (Size setting) or the header
-- moved; re-fit a few times a second, only then.
local editWatch = CreateFrame("Frame")
editWatch:Hide()
editWatch.elapsed = 0
editWatch:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    FitEditModeBox()
end)

---------------------------------------------------------------------------
-- Conceal Blizzard's header pieces: alpha 0, no mouse (also child buttons).
---------------------------------------------------------------------------
local function DisableMouse(frame)
    if frame.EnableMouse and not frame:IsProtected() then frame:EnableMouse(false) end
    for _, child in ipairs({ frame:GetChildren() }) do DisableMouse(child) end
end

local function Conceal(frame)
    if not frame then return end
    frame:SetAlpha(0)
    DisableMouse(frame)
end

local function ConcealBlizzard()
    local cluster = MinimapCluster
    Conceal(cluster.ZoneTextButton)
    Conceal(cluster.DielFrame)
    Conceal(Minimap.ZoomIn)
    Conceal(Minimap.ZoomOut)
    Conceal(cluster.MinimapContainer and cluster.MinimapContainer.PlayerCoords) -- ours replaces it
    Conceal(TimeManagerClockButton) -- exists once Blizzard_TimeManager loaded
    if not cluster:IsProtected() then cluster:EnableMouse(false) end -- the empty header area
end

---------------------------------------------------------------------------
-- Icons inside the map: mail always, the rest while hovering.
---------------------------------------------------------------------------
local overlay, zoneText, fpsText, clockButton, clockText, coordsText, hoverWatch
local hoverIcons = {}
local ICON_GAP = 2 -- px between the hover row's buttons

local MAIL_SCALE = 0.8 -- Blizzard's mail icon is large next to the FPS text
local MAIL_GAP = 6     -- FPS text to the mail icon

local function PlaceMail()
    local indicator = MinimapCluster.IndicatorFrame
    if not (indicator and fpsText) then return end
    indicator:ClearAllPoints()
    indicator:SetScale(MAIL_SCALE)
    indicator:SetPoint("TOPLEFT", fpsText, "BOTTOMLEFT", 0, -MAIL_GAP) -- under the FPS
    indicator:SetFrameLevel(Minimap:GetFrameLevel() + 10)
end

-- What a hover icon looks like on screen: the tracking frame is a 17 px
-- holder with its 23 px button centred on it, so the button's size counts.
local function VisibleSize(icon)
    local shown = (icon == MinimapCluster.Tracking and icon.Button) or icon
    return shown:GetSize()
end

-- The addon menu button gets the calendar's plate (Forever draws it with its
-- own, slightly different art): its art faded out, the plate under its count.
local function RestyleAddonButton()
    local button = AddonCompartmentFrame
    if not button then return end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() ~= "HIGHLIGHT" then region:SetAlpha(0) end
    end
    ns.AddButtonPlate(button)
    if GameTimeFrame then button:SetSize(GameTimeFrame:GetSize()) end
end

-- Left to right, each centred on the row by its visible size, ICON_GAP apart.
local function PlaceIcons()
    local cluster = MinimapCluster
    local level = Minimap:GetFrameLevel() + 10
    local rowHeight = 0
    for _, icon in ipairs(hoverIcons) do
        local _, h = VisibleSize(icon)
        rowHeight = math.max(rowHeight, h)
    end
    local x, y = PAD.side - 3, PAD.bottom - 3 + rowHeight / 2
    for _, icon in ipairs(hoverIcons) do
        local w = VisibleSize(icon)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", Minimap, "BOTTOMLEFT", x + w / 2, y)
        icon:SetFrameLevel(level)
        x = x + w + ICON_GAP
    end
    PlaceMail()
    if cluster.Tracking and cluster.Tracking.Button then cluster.Tracking.Button:SetFrameLevel(level + 1) end
end

local function SetIconsShown(shown)
    for _, icon in ipairs(hoverIcons) do icon:SetAlpha(shown and 1 or 0) end
end

---------------------------------------------------------------------------
-- Text in the corners
---------------------------------------------------------------------------
local lastClock

local ZONE_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena = { 1.0, 0.1, 0.1 },
    friendly = { 0.1, 1.0, 0.1 },
    hostile = { 1.0, 0.1, 0.1 },
    contested = { 1.0, 0.7, 0.0 },
}

local function FitZoneWidth()
    -- The title bar's band between the side rims, a little air at each end.
    zoneText:SetWidth(math.max(20, Minimap:GetWidth() - 2 * (RIM_OUT + 4)))
end

local function UpdateZone()
    local text = GetMinimapZoneText()
    zoneText:SetText(Secret(text) and "" or text)
    local pvpType = C_PvP.GetZonePVPInfo()
    local color = ZONE_COLORS[Secret(pvpType) and "" or pvpType or ""]
    if color then
        zoneText:SetTextColor(color[1], color[2], color[3])
    else
        zoneText:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
end

-- Clock in the game's own format: local or realm time and 12/24 hour, as set
-- in Blizzard's clock options (timeMgrUseLocalTime / timeMgrUseMilitaryTime).
local function ClockString()
    if GameTime_GetTime then
        return (GameTime_GetTime(not GetCVarBool("timeMgrUseMilitaryTime")))
    end
    return date("%H:%M")
end

local function Tick()
    local clock = ClockString()
    if clock ~= lastClock then
        lastClock = clock
        clockText:SetText(clock)
        clockButton:SetSize(clockText:GetStringWidth() + 4, clockText:GetStringHeight() + 4)
        FitZoneWidth()
    end
    fpsText:SetFormattedText("%d FPS", math.floor(GetFramerate() + 0.5))
end

-- Coordinates in Blizzard's format (MINIMAP_PLAYER_COORDS*, coordsByTenths).
local function UpdateCoords()
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and not Secret(mapID) and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if position then x, y = position:GetXY() end
    if not x or Secret(x) or Secret(y) or (x == 0 and y == 0) then
        coordsText:SetText("")
        return
    end
    if GetCVarBool("coordsByTenths") then
        coordsText:SetFormattedText(MINIMAP_PLAYER_COORDS or "%.1f, %.1f", x * 100, y * 100)
    else
        coordsText:SetFormattedText(MINIMAP_PLAYER_COORDS_INTEGER or "%d, %d",
            math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
    end
end

local function ClockTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(ClockString(), 1, 1, 1)
    GameTooltip:AddLine("Left-click: calendar", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: stopwatch and alarm", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function ClockClick(_, button)
    if button == "RightButton" then
        if not TimeManager_Toggle and C_AddOns then C_AddOns.LoadAddOn("Blizzard_TimeManager") end
        if TimeManager_Toggle then TimeManager_Toggle() end
    elseif ToggleCalendar then
        ToggleCalendar()
    end
end

-- Hover: icons + coordinates while the mouse is over the map (or a menu we
-- opened from it is still open).
local function MenuOpen()
    local tracking = MinimapCluster.Tracking and MinimapCluster.Tracking.Button
    return (AddonCompartmentFrame and AddonCompartmentFrame.IsMenuOpen and AddonCompartmentFrame:IsMenuOpen())
        or (tracking and tracking.IsMenuOpen and tracking:IsMenuOpen())
end

local function Reveal()
    if hoverWatch:IsShown() then return end
    UpdateCoords()
    coordsText:Show()
    SetIconsShown(true)
    hoverWatch:Show()
end

local function BuildText()
    overlay = CreateFrame("Frame", nil, Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)

    zoneText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Centred in the title bar's band above the map.
    zoneText:SetPoint("CENTER", Minimap, "TOP", 0, RIM_TITLE - (TITLE_BAND.from + TITLE_BAND.to) / 2)
    zoneText:SetJustifyH("CENTER")
    zoneText:SetWordWrap(false)

    fpsText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fpsText:SetPoint("TOPLEFT", Minimap, "TOPLEFT", PAD.side, -PAD.top)

    clockButton = CreateFrame("Button", nil, overlay)
    clockButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -PAD.side + 2, -PAD.top + 2) -- the button has 2 px around its text
    clockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    clockButton:SetScript("OnClick", ClockClick)
    clockButton:SetScript("OnEnter", ClockTooltip)
    clockButton:SetScript("OnLeave", GameTooltip_Hide)
    clockText = clockButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    clockText:SetPoint("CENTER")

    coordsText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordsText:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -PAD.side, PAD.bottom)
    coordsText:Hide()

    hoverWatch = CreateFrame("Frame", nil, overlay)
    hoverWatch:Hide()
    local elapsed = 0
    hoverWatch:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < HOVER_INTERVAL then return end
        elapsed = 0
        -- The frame's own method; the global MouseIsOver helper errors now and then on this client.
        if Minimap:IsMouseOver() or MenuOpen() then
            UpdateCoords()
        else
            self:Hide()
            coordsText:Hide()
            SetIconsShown(false)
        end
    end)
    Minimap:HookScript("OnEnter", Reveal)
end

---------------------------------------------------------------------------
-- Addon minimap buttons -> Blizzard's addon compartment menu
---------------------------------------------------------------------------
local holder               -- invisible parent for the real buttons
local collected = {}       -- [button] = true

local function StripCodes(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")):lower()
end

local function InCompartment(title)
    local wanted = StripCodes(title)
    for _, data in ipairs(AddonCompartmentFrame.registeredAddons or {}) do
        if StripCodes(data.text) == wanted then return true end
    end
    return false
end

local function ButtonIcon(button)
    local icon = button.icon or button.Icon
    if icon and icon.GetTexture then return icon:GetTexture() end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" and region:GetTexture() then
            return region:GetTexture()
        end
    end
end

-- Readable name from a frame name: "IshkorsAddonManagerMinimapButton" -> "Ishkors Addon Manager".
local function NameFromFrame(name)
    name = name:gsub("MinimapButton$", ""):gsub("Minimap$", ""):gsub("Button$", "")
    return (name:gsub("(%l)(%u)", "%1 %2"))
end

-- Put the (invisible) real button under the menu entry, so anything it anchors
-- to itself (tooltip, its own menu) shows up next to the menu.
local function PlaceUnder(button, owner)
    if not (owner and owner.GetCenter) then return end
    local x, y = owner:GetCenter()
    if not x then return end
    local k = owner:GetEffectiveScale() / button:GetEffectiveScale()
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * k, y * k)
end

local function CallScript(button, script, ...)
    local fn = button:GetScript(script)
    if fn then ns.safecall(fn, button, ...) end
    return fn ~= nil
end

local function MenuEntry(button, title, icon)
    local owner
    return {
        text = title,
        icon = icon,
        notCheckable = true,
        func = function(_, input)
            PlaceUnder(button, owner)
            local mouse = input and input.buttonName or "LeftButton"
            if button:GetScript("OnClick") then
                button:Click(mouse)
            else
                CallScript(button, "OnMouseDown", mouse)
                CallScript(button, "OnMouseUp", mouse)
            end
        end,
        funcOnEnter = function(menuButton)
            owner = menuButton
            PlaceUnder(button, menuButton)
            CallScript(button, "OnEnter")
        end,
        funcOnLeave = function()
            CallScript(button, "OnLeave")
        end,
    }
end

local function Collect(button)
    if collected[button] or button:IsForbidden() then return end
    local name = button:GetName()
    if not name or Secret(name) then return end
    local secure, addon = issecurevariable(name)
    if secure or not addon or addon == ns.name then return end -- Blizzard's own, or ours
    if not (button:GetScript("OnClick") or button:GetScript("OnMouseUp")) then return end

    local title, icon
    local brokerName = name:match("^LibDBIcon10_(.+)$")
    if brokerName then
        local object = button.dataObject
        title = (object and object.label) or brokerName
        icon = object and object.icon
    else
        title = C_AddOns.GetAddOnMetadata(addon, "Title") or NameFromFrame(name)
        icon = ButtonIcon(button) or C_AddOns.GetAddOnMetadata(addon, "IconTexture")
    end

    collected[button] = true
    button:SetParent(holder)
    button:EnableMouse(false)
    if button.EnableMouseWheel then button:EnableMouseWheel(false) end

    -- Already in the menu (AddonCompartmentFunc in its TOC, or registered itself): just hide the button.
    local hasEntry = (not brokerName and C_AddOns.GetAddOnMetadata(addon, "AddonCompartmentFunc")) or InCompartment(title)
    if not hasEntry then
        AddonCompartmentFrame:RegisterAddon(MenuEntry(button, title, icon))
    end
end

local function CollectButtons()
    if not AddonCompartmentFrame then return end
    for _, parent in ipairs({ Minimap, MinimapBackdrop }) do
        if parent then
            for _, child in ipairs({ parent:GetChildren() }) do
                if child:IsObjectType("Button") or child:IsObjectType("Frame") then Collect(child) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Another module's button joins the hover row, after the calendar (the quest
-- tracker's toggle). false while the square minimap isn't running.
function M.AddHoverIcon(icon)
    if not hoverWatch then return false end
    hoverIcons[#hoverIcons + 1] = icon
    PlaceIcons()
    icon:SetAlpha(hoverWatch:IsShown() and 1 or 0)
    icon:HookScript("OnEnter", Reveal)
    return true
end

function M:OnEnable()
    if not (MinimapCluster and Minimap and MinimapCompassTexture) then return end
    local cluster = MinimapCluster

    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER")
    holder:SetAlpha(0)

    -- Hover row, left to right: addon menu, tracking, calendar.
    for _, icon in ipairs({ AddonCompartmentFrame, cluster.Tracking, GameTimeFrame }) do
        if icon then hoverIcons[#hoverIcons + 1] = icon end
    end

    -- The shared convention for a square minimap (HereBeDragons pins in Questie,
    -- Polestar's pins, LibDBIcon): without it they assume a round map and pull
    -- edge and corner pins onto a circle. Left alone if another addon set one.
    if GetMinimapShape == nil then
        _G.GetMinimapShape = function() return "SQUARE" end -- a deliberate global (the convention)
    end
    ApplySquare()
    RestyleAddonButton()
    BuildRim()
    ConcealBlizzard()
    BuildText()
    PlaceIcons()
    SetIconsShown(false)
    for _, icon in ipairs({ AddonCompartmentFrame, cluster.Tracking and cluster.Tracking.Button, GameTimeFrame }) do
        if icon then icon:HookScript("OnEnter", Reveal) end
    end
    UpdateZone()
    Tick()
    C_Timer.NewTicker(1, Tick)
    RunNextFrame(FitEditModeBox)

    -- Blizzard re-anchors the mail indicator when tracking shows/hides or the
    -- header setting changes; put it back after.
    if MiniMapIndicatorFrame_UpdatePosition then hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", PlaceMail) end
    if cluster.SetHeaderUnderneath then
        hooksecurefunc(cluster, "SetHeaderUnderneath", function()
            PlaceIcons()
            RunNextFrame(FitEditModeBox)
        end)
    end

    EventUtil.ContinueOnAddOnLoaded("Blizzard_TimeManager", function() Conceal(TimeManagerClockButton) end)
    EventUtil.ContinueOnAddOnLoaded("Blizzard_HybridMinimap", function()
        local canvas, mask = HybridMinimap and HybridMinimap.MapCanvas, HybridMinimap and HybridMinimap.CircleMask
        if canvas and mask then
            canvas:SetUseMaskTexture(false)
            mask:SetTexture(SQUARE_MASK)
            canvas:SetUseMaskTexture(true)
        end
    end)

    -- Addon buttons appear at different times (login, later registrations).
    CollectButtons()
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon and LDBIcon.RegisterCallback then
        LDBIcon.RegisterCallback(M, "LibDBIcon_IconCreated", function() RunNextFrame(CollectButtons) end)
    end

    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        ns:On(event, UpdateZone)
    end
    local firstWorld = true
    ns:On("PLAYER_ENTERING_WORLD", function()
        UpdateZone()
        RunNextFrame(function()
            ApplySquare()
            PlaceIcons()
            FitEditModeBox()
            CollectButtons()
        end)
        if firstWorld then
            firstWorld = false
            C_Timer.After(3, CollectButtons)
            C_Timer.After(10, CollectButtons)
        end
    end)
    ns:On("CVAR_UPDATE", function(_, cvar)
        if type(cvar) == "string" and not Secret(cvar) and cvar:lower() == "rotateminimap" then RunNextFrame(ApplySquare) end
    end)
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        RunNextFrame(FitEditModeBox)
        editWatch:Show()
    end, M)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        editWatch:Hide()
        RunNextFrame(function()
            FitEditModeBox()
            PlaceIcons()
            FitZoneWidth()
        end)
    end, M)
end
