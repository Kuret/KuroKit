-- Arc HUD (ArcHUD / IceHUD inspired): curved bars around your character.
--   left    your health (outer arc) and power (inner arc), bottom to top
--   right   your target's health (outer) and power (inner)
--   below   your cast (fills left to right; channels drain), the spell icon
--           by its left tip, the spell name under it, the time left by its right tip, and a red latency zone
--           at its end (at its start for channels) to time the next cast;
--           Blizzard's own player cast bar is faded out while this is on
-- Above each arc's top tip a round portrait in a bronze ring (gold for
-- elites, silver for rares), the name (class / reaction colour) and level
-- (difficulty colour, "+" for elites) beside it, and the faction icon while
-- PvP flagged. Values and percentages under the arcs' lower tips (1.1K  81%
-- on your side, 81%  1.1K on your target's). Health in class colour for players (you
-- too; names in full: Forever's first name and surname), reaction colour for
-- NPCs; power in Blizzard's power colours. In the Forever plate's materials (dark outline,
-- bronze line, dark track).
-- Where and when: each arc's outer edge lines up with its unit frame's (yours
-- with the player frame's left edge, your target's with the target frame's
-- right one: move them in Edit Mode, which shows the arcs too), vertically
-- centred on your character as before. In combat or
-- with a target you can attack, the arcs pop up (fade in, sliding up) and
-- the frames step back (fade out, their target buffs / debuffs and your class
-- resources stay); otherwise the frames are back (Frame Fading still fades
-- yours). The target side only with a target, the cast arc only while
-- casting; the HUD's own target cast bar beside the target arc (its own
-- fill, icon, spell name, time left, a lock for casts you can't interrupt).
-- The cast arc sits on Blizzard's player cast bar (hidden, but Edit Mode
-- still moves it: it shows there, with the cast arc, while Edit Mode is open).
-- Trims: thin rings along your arc, per class. Inside the power ring: the
-- five-second rule (mana users: drains over the 5 s after you spend mana,
-- then fills to each 2 s mana tick) or the energy tick (fills to each 2 s
-- tick), faded out at full power; your pet's health (Hunters, Warlocks).
-- Priests: your absorb shield as a short arc beside your character (full
-- when it goes up, draining as it soaks damage) and a blue glow round your
-- portrait while you have one, a red ring bursting round your character when
-- it breaks or runs out; Weakened Soul as a red countdown sweep with its
-- seconds over your portrait, a blue ring round your character and its icon
-- pulsing above you when it ends (your shield's own cooldown pulse held back
-- while it lasts: the shield can't go up anyway) (from the aura, or in combat, where the HUD
-- can't see it, from your own shield landing on you: your clock). Ticks are timed from when your power
-- changes without a cast of yours spending it (values stay secret; only the
-- events count). The Cooldown Manager rails move out of their way.
-- Target of target beside your target's portrait (inward): its name and a
-- small health bar; click it to target it.
-- Clicks: the portraits and the arcs are unit buttons while they show (left:
-- target, right: the unit menu, the game's click casting as on any unit
-- frame); hovering shows the unit's tooltip. The frames stay clickable.
--
-- How: on this client health and power are secret to addons, so nothing is
-- computed here. Each arc is a status bar whose fill is a curved image in the
-- cast bar's style (tools/make_arcs.py; a straight texture masked to the arc
-- shows its sheen as straight lines across the curve): the client crops it to
-- the value, so it fills along the curve; status bars accept secret values.
-- Percentages:
-- UnitHealthPercent / UnitPowerPercent scaled to 100, written with
-- SetFormattedText; your health colour: a colour curve the client evaluates.
-- The cast arc runs off the cast's duration object (SetTimerDuration).
-- Cooldown Manager on the HUD's curves: its Essential cooldowns along the
-- outside of your arc (from below the level badge down, more rows further
-- out), its tracked buffs / procs (Buff Icons) along the inside of your arc,
-- its Utility cooldowns along the inside of your target's; each in one row,
-- the icons shrunk to fit it.
-- Blizzard's icons themselves, re-placed after each of the viewer's layouts
-- and whenever an icon shows or hides (shown ones only, packed); Edit Mode's
-- icon size and padding still apply, its position for these three doesn't.
-- They fade with their HUD side (essentials and procs with yours, utility with
-- your target's): the viewer's alpha is Blizzard's times the side's.
-- Clicks: SecureUnitButtonTemplate buttons (type1 target, type2 togglemenu;
-- its OnClick runs the game's click bindings), a row of small ones along
-- each arc (the arcs' inside stays free for clicking the world), shown by a
-- secure state driver with the arcs' own conditions ([combat], [harm]).
-- Created at login, out of combat. They hang off a fixed anchor per side, not
-- the sliding arc (a frame protected frames hang off can't move in combat).
-- Blizzard's frames step back through their parts' alpha (Blizzard's own
-- alpha times ours, kept through a SetAlpha hook), never Show / Hide.
-- Cost: a SetValue per health / power change; nothing per frame except the
-- short alpha fades.
local _, ns = ...

local M = ns:NewModule("ArcHUD", {
    title = "Arc HUD",
    group = "Interface",
    desc = "Curved health and power bars (you left, your target right) with portraits, names and levels, and a cast "
        .. "arc below your character. The arcs line up with the player and target frames' outer edges (move those in "
        .. "Edit Mode) and pop up in combat or with a hostile target while the frames step back; click them as you would those "
        .. "frames. Replaces the player cast bar.",
    defaults = { cooldowns = true },
    options = {
        { type = "checkbox", key = "cooldowns", name = "Cooldown Manager on the HUD", reload = true,
          tooltip = "The Cooldown Manager's icons along the HUD's curves (Essential outside your arc, tracked buffs "
              .. "inside it, Utility inside your target's), fading with the HUD, and the Essential cooldowns' flash "
              .. "and big icon pulse above your character as they come off cooldown. Off: the Cooldown Manager "
              .. "stays where Edit Mode puts it." },
    },
})

local MEDIA = "Interface\\AddOns\\KuroKit\\Media\\"
local SCALE = 0.5            -- texture pixels -> UI units
local SIDE_W, SIDE_H = 256 * SCALE, 512 * SCALE
local CAST_W, CAST_H = 512 * SCALE, 128 * SCALE
-- The cast fill's columns (texture px; tools/make_arcs.py: the same numbers):
-- the bars sit over just these, so the fill shows from the cast's start.
local CAST_FILL_LEFT = math.floor(256 - 600 * math.sin(math.rad(17)))
local CAST_FILL_RIGHT = math.ceil(256 + 600 * math.sin(math.rad(17)))
-- Each arc's outer edge on its unit frame's outer edge, moved outward by
-- this (UI units; negative: inward); vertically ARC_Y from the HUD's centre.
local FRAME_X = -60
local ARC_Y = -20             -- the arcs' middle, below the HUD's centre (your character's middle)
local POP_DIST = 24          -- the arcs slide up this far as they fade in
local BACK_ALPHA = 0.3       -- the arcs' frame and empty track
local FILL_ALPHA = 0.5       -- the arcs' fill and the portraits
-- The arcs' geometry in texture pixels (tools/make_arcs.py): circle centre,
-- the middle radius of the two rings, half the angle they span.
local ARC_CX, ARC_CY, ARC_R, ARC_HALF = 412, 256, 373, math.rad(36)
-- The portrait sits in the arcs' socket (part of the arc texture: its centre
-- on the rings' middle line at SOCKET_ANGLE, a 100 px hole), the level in a
-- small badge on its lower outer edge, right where the health ring meets it
-- (covering that seam), the name beside it, the PvP icon on its top. The fills run on under the portrait, which covers their
-- end (tools/make_arcs.py: SOCKET_ANGLE, SOCKET_R, FILL_TOP; angles there are
-- mirrored).
local PORTRAIT_SIZE = 50
local SOCKET_ANGLE = math.rad(-30)
local SOCKET_HOLE = 50       -- texture px: the portrait's radius
local OUTER_RING, INNER_RING = { 372, 400 }, { 347, 365 } -- texture px
local RING_SIZE = PORTRAIT_SIZE * 128 / 104 -- ring texture: 128 px canvas, 104 px hole
local BADGE_SIZE = 22
local NAME_UP = 8            -- the name beside the portrait, above its middle (clear of the level badge)
local BADGE_OUT = 6          -- the level badge nudged this far outward from where the health ring meets the portrait
local ID_GAP = 6             -- the name beside the medallion
local FACTION_SIZE = 22
local CLICK_SEGMENTS = 6     -- click buttons along each arc
local CLICK_WIDTH = 40
local RINGS = { elite = "ArcRingElite", worldboss = "ArcRingElite", rareelite = "ArcRingElite", rare = "ArcRingRare" }
local FACTION_ATLAS = { Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance", Horde = "UI-HUD-UnitFrame-SmallCircle-Horde" }
local FFA_ATLAS = "UI-HUD-UnitFrame-Player-PVP-FFAIcon"
local RESTED_COLOR = { 0.45, 0.72, 1 } -- your level while resting (as the Unit Frames module)
-- Cooldown Manager on the curves. Rails: just inside the arcs' inner edge or
-- just outside their outer edge (texture px, tools/make_arcs.py: rings 347 to
-- 400, outline 8), from their start to RAIL_END (shares of the arc's half
-- angle, negative: above the middle), one row: icons shrink to fit it (never
-- larger than Edit Mode's icon size).
local ARC_INNER_EDGE, ARC_OUTER_EDGE = 339, 408
local RAIL_GAP = 4              -- UI units between the arc and its icons
local RAIL_START = -0.45        -- inside: just below the portrait
local OUTSIDE_RAIL_START = -0.33 -- outside: just below the level badge
local RAIL_END = 0.8            -- the last icon's centre: clear of the numbers under the arcs
local CDM_GAP = 4               -- extra space between icons along a curve
local CDM_LAYOUTS = {
    { viewer = "EssentialCooldownViewer", side = "player", outside = true, flash = true },
    { viewer = "BuffIconCooldownViewer", side = "player" },
    { viewer = "UtilityCooldownViewer", side = "target" },
}
-- Trims (texture px; tools/make_arcs.py TRIMS, same numbers): ring radii,
-- each on its own canvas from its lower tip to TRIM_CLEAR round the socket (T.CLEAR).
local TRIMS = {
    tick = { 329, 335, texture = "ArcTrimTick" },
    pet = { 319, 325, texture = "ArcTrimPet" },
    mana = { 319, 325, texture = "ArcTrimPet" }, -- druids' mana while shapeshifted (the pet's place: no pet)
}
-- The shield's sheen and glow, Weakened Soul's sweep.
local GLOW_ALPHA, GLOW_SIZE = 1, 79 -- (ArcGlow: its ring 46 / 64 of the canvas; this puts it just outside the socket)
local SOUL_SWEEP_ALPHA, SOUL_FONT_SIZE = 0.6, 15
local TRIM_CLASSES = {   -- which trims a class gets (tick: every class but these)
    pet = { HUNTER = true, WARLOCK = true },
    mana = { DRUID = true },
    shield = { PRIEST = true },
    soul = { PRIEST = true },
}

local T = {                    -- (one table: the main chunk is near Lua's 200-local limit)
    NO_TICK = { WARRIOR = true },
    CLEAR = 60,                -- texture px round the socket's centre (socket 50 + outline 8 + 2)
    W = 128, H = 512, MARGIN = 2,
    TRACK_ALPHA = 0.5,
    RAIL_PAD = 2,              -- texture px between a trim and the Cooldown Manager icons
    FSR_TIME = 5, TICK_TIME = 2,
    SPEND_WINDOW = 0.15,       -- seconds: a power change this close to a spend of yours is the spend
    FSR_COLOR = { 1, 0.78, 0.25 },
    MANA_TICK_COLOR = { 0.45, 0.7, 1 },
    ENERGY_TICK_COLOR = { 1, 0.9, 0.3 },
    SHIELD_COLOR = { 0.25, 0.58, 1 },
    -- Bursts (seen from the corner of your eye): your shield broken or run
    -- out (red) and Weakened Soul ending (blue: you can shield again). A
    -- glowing ring round your character swelling outward, twice.
    BREAK_COLOR = { 1, 0.25, 0.1 },
    READY_COLOR = { 0.3, 0.62, 1 },
    BURST_TIME = 0.55, BURST_PULSES = 2, BURST_SCALE = 2.4, BURST_SIZE = 112, BURST_Y = 0,
    SOUL_COLOR = { 1, 0.3, 0.22 },
    SOUL_SPELL = 6788,         -- Weakened Soul (found by name: every rank)
    SHIELD_SPELL = 17,         -- Power Word: Shield (by name: every rank)
    -- The shield's mini arc beside your character (tools/make_arcs.py MINI_*):
    -- canvas, its circle's centre, outer radius, half angle; placed from the
    -- HUD's centre.
    MINI_W = 64, MINI_H = 256, MINI_CX = 236, MINI_CY = 128, MINI_R_OUT = 226, MINI_HALF = math.rad(24),
    MINI_X = -88, MINI_Y = 0, MINI_BACK_ALPHA = 0.85, MINI_FILL_ALPHA = 0.95,
    -- Combo points: gems along the outside of the target's arc, below its
    -- middle (texture px radius, angles in degrees, down positive).
    PIP_COUNT = 5, PIP_SIZE = 14, PIP_R = 424, PIP_FIRST = 5, PIP_STEP = 4.8,
    PIP_COLOR = { 1, 0.78, 0.2 }, PIP_LAST_COLOR = { 1, 0.3, 0.15 },
    -- Essential cooldowns coming off cooldown: a gold ring swelling off the
    -- icon (cooldowns of at least READY_MIN seconds: not the global one).
    READY_COLOR_CD = { 1, 0.85, 0.35 }, READY_TIME = 0.6, READY_FROM = 1.43, READY_TO = 2.85, READY_MIN = 2,
    -- ...and its icon pulsing big just above your character (one after
    -- another when several come back at once): pops in, holds, fades out.
    PULSE_SIZE = 46, PULSE_Y = 92, PULSE_IN = 0.12, PULSE_HOLD = 0.5, PULSE_OUT = 0.45, PULSE_GAP = 0.25,
    SOUL_DURATION = 15,        -- Weakened Soul's seconds (until read from the aura out of combat)
    SHIELD_CAPTURE = 0.5,      -- seconds after your shield cast that absorb changes set its size
    -- Target of target beside the target's portrait (inward).
    TOT_W = 90, TOT_BAR_H = 4, TOT_FONT_SIZE = 11, TOT_GAP = 6,
    TOT_INTERVAL = 0.2,
}
-- The target cast bar beside the right arc (heights from the target's
-- portrait centre, x from the arc's outermost point).
local TCAST_W, TCAST_H, TCAST_ICON = 170, 12, 20
local TCAST_Y = -88                      -- the cast bar, below the portrait's centre
local TCAST_X = 8                        -- its icon, right of the arc's outermost point
local INTERRUPT_HOLD = 0.8               -- seconds an interrupted / failed cast stays up
local INTERRUPT_GRACE = 0.3              -- a cast stopped this close to its end finished (not interrupted)
local INTERRUPT_COLOR = { 0.9, 0.1, 0.05 }
local TCAST_INTERRUPTED = "ui-castingbar-interrupted"
local TCAST_FILL = "ui-castingbar-filling-standard"
local TCAST_CHANNEL_FILL = "ui-castingbar-filling-channel"
local TCAST_BACK = "ui-castingbar-background"
local TCAST_LOCK = "ui-castingbar-shield"
local HEALTH_FONT_SIZE = 16  -- health value / percentage (read at a glance: execute range)
local POWER_FONT_SIZE = 12
local NAME_FONT_SIZE = 13
local CENTER_Y = -20         -- the HUD's centre (the cast arc's), from the screen centre (your character)
local CAST_Y = 0             -- the cast arc's centre, from the player cast bar's (Edit Mode)
local CAST_TIP_X, CAST_TIP_Y = 0.86, -0.55 -- the time left: by the arc's right tip (share of its frame)
local CAST_ICON_X = 0.14     -- the spell icon: by the arc's left tip
local CAST_ICON_SIZE = 24
local TIMER_INTERVAL = 0.05  -- seconds between time-left updates
local LATENCY_COLOR = { 1, 0.15, 0.1, 0.6 }
local TEXT_X = 0.45          -- texts: under the arcs' lower tips, right (left side) / left (right side)
                             -- edge this far into the arc frame (the tip's middle)
local FADE_TIME = 0.25
local TEXT_GAP = 2
local TEXT_LIFT = 0.45       -- texts: the bar colour mixed toward white (pure blue / red are unreadable)

local HEALTH_RED = CreateColor(0.9, 0.15, 0.1)
local HEALTH_YELLOW = CreateColor(0.95, 0.8, 0.15)
local HEALTH_GREEN = CreateColor(0.25, 0.8, 0.25)
local CAST_COLOR = { 1, 0.7, 0 }
local CHANNEL_COLOR = { 0.3, 0.8, 0.3 }

local hud
-- (defined further down)
local BuildTrims, BuildToT, UpdateTrims, UpdateToT, UpdatePet, UpdateShieldTrim, UpdateSoul
local UpdateFormMana, UpdateCombo
local OnSpent, OnPowerChanged, UpdateTickShown
local sides = {}        -- .player, .target: { anchor, frame, health, power, healthText, powerText, portrait,
                        --   ring, name, level, faction, id, alpha, wanted }
local cast              -- { frame, bar, latency, name, timer, alpha, wanted, channel }
local healthCurve, healthTextCurve

local function Lift(r, g, b)
    local l = TEXT_LIFT
    return r + (1 - r) * l, g + (1 - g) * l, b + (1 - b) * l
end

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Scale100() return CurveConstants and CurveConstants.ScaleTo100 end

-- A bar value, eased where the client supports it.
local function SetBarValue(bar, value)
    local ease = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if ease then bar:SetValue(value, ease) else bar:SetValue(value) end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- An arc: a status bar whose fill is a curved image (cropped to the value).
local function NewBar(parent, shape, orientation)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetAllPoints(parent)
    bar:SetOrientation(orientation)
    bar:SetStatusBarTexture(shape)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

-- A point on the arcs' middle line in the side frame (from its top left, y
-- down); angle 0 is the arc's middle, negative up.
local function ArcPoint(angle, left)
    local x = (ARC_CX - ARC_R * math.cos(angle)) * SCALE
    local y = (ARC_CY + ARC_R * math.sin(angle)) * SCALE
    if not left then x = SIDE_W - x end
    return x, y
end

-- The portrait's centre (the socket's) in the side frame (from its top left,
-- y down).
local function PortraitPoint(left)
    return ArcPoint(SOCKET_ANGLE, left)
end

-- Where the health ring's outer edge meets the portrait's edge (the corner
-- where a gap shows), from the portrait's centre (UI units, y up; the left
-- side, mirror x for the right): the level badge sits there.
local function HealthJunction()
    local mid = OUTER_RING[2]
    local cosine = (mid * mid + ARC_R * ARC_R - SOCKET_HOLE * SOCKET_HOLE) / (2 * mid * ARC_R)
    local angle = SOCKET_ANGLE + math.acos(math.min(1, cosine))
    local cx, cy = ArcPoint(SOCKET_ANGLE, true)
    local x = (ARC_CX - mid * math.cos(angle)) * SCALE
    local y = (ARC_CY + mid * math.sin(angle)) * SCALE
    return x - cx, -(y - cy)
end

-- A side fill's value range: the status bar crops its texture vertically over
-- the whole 512 px canvas, while the ring shows from its lower tip to where it
-- meets the portrait's edge; 0 maps to the tip and 1 to that edge.
local function FillRange(ring)
    local outer = ring[2]
    local bottom = (512 - (ARC_CY + outer * math.sin(ARC_HALF))) / 512
    -- the fill's highest point: where one of the ring's edges meets the
    -- portrait's (the fill is cut out there)
    local highest = 0
    for _, r in ipairs(ring) do
        local cosine = (r * r + ARC_R * ARC_R - SOCKET_HOLE * SOCKET_HOLE) / (2 * r * ARC_R)
        local edge = SOCKET_ANGLE + math.acos(math.min(1, cosine))
        highest = math.max(highest, 512 - (ARC_CY + r * math.sin(edge)))
    end
    local top = highest / 512
    local span = top - bottom
    return -bottom / span, (1 - bottom) / span
end

-- Outlined text with a small soft shadow, `size` points.
local function NewText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local file = fs:GetFont()
    if file then fs:SetFont(file, size or 12, "OUTLINE") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    return fs
end

local function NewSide(key, side)
    local left = side == "Left"
    -- A fixed anchor on the unit frame (the click buttons hang off it) and
    -- the arc itself, which slides up from below it as it fades in.
    local anchor = CreateFrame("Frame", nil, hud)
    anchor:SetSize(SIDE_W, SIDE_H)
    local frame = CreateFrame("Frame", nil, anchor)
    frame:SetSize(SIDE_W, SIDE_H)
    frame:SetPoint("CENTER", anchor, "CENTER", 0, -POP_DIST)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetAlpha(BACK_ALPHA)
    back:SetTexture(MEDIA .. "ArcBack" .. side)
    local s = { anchor = anchor, frame = frame, alpha = 0, wanted = 0, pop = true }
    s.health = NewBar(frame, MEDIA .. "ArcOuter" .. side, "VERTICAL")
    s.power = NewBar(frame, MEDIA .. "ArcInner" .. side, "VERTICAL")
    s.health:SetMinMaxValues(FillRange(OUTER_RING))
    s.power:SetMinMaxValues(FillRange(INNER_RING))
    s.health:SetAlpha(FILL_ALPHA)
    s.power:SetAlpha(FILL_ALPHA)
    -- Texts under the arcs' lower tips (outside the arc, clear of the cast
    -- arc): health, power under it.
    s.healthText = NewText(frame, HEALTH_FONT_SIZE)
    s.healthText:SetPoint(left and "TOPRIGHT" or "TOPLEFT", frame, left and "BOTTOMLEFT" or "BOTTOMRIGHT",
        (left and 1 or -1) * SIDE_W * TEXT_X, -TEXT_GAP)
    s.healthText:SetJustifyH(left and "RIGHT" or "LEFT")
    s.powerText = NewText(frame, POWER_FONT_SIZE)
    s.powerText:SetPoint(left and "TOPRIGHT" or "TOPLEFT", s.healthText, left and "BOTTOMRIGHT" or "BOTTOMLEFT",
        0, -TEXT_GAP)
    s.powerText:SetJustifyH(left and "RIGHT" or "LEFT")
    -- Identity: the portrait in the arc's socket, the level badge where the
    -- health ring meets it, the name beside it (away from the character), the
    -- faction icon on its top. The ring over it only for elites (gold)
    -- and rares (silver): the socket has the bronze one.
    local px, py = PortraitPoint(left)
    local id = CreateFrame("Frame", nil, frame)
    id:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    PixelUtil.SetPoint(id, "CENTER", frame, "TOPLEFT", px, -py) -- whole pixels: the text stays centred
    id:SetFrameLevel(s.power:GetFrameLevel() + 2)
    s.id = id
    -- (see-through like the fills: the socket's dark bed shows behind it)
    s.portrait = id:CreateTexture(nil, "ARTWORK")
    s.portrait:SetAllPoints()
    s.portrait:SetAlpha(FILL_ALPHA)
    s.ring = id:CreateTexture(nil, "OVERLAY")
    s.ring:SetSize(RING_SIZE, RING_SIZE)
    s.ring:SetPoint("CENTER")
    s.ring:SetTexture(MEDIA .. "ArcRing")
    s.ring:Hide()
    local outer = left and "LEFT" or "RIGHT"
    local sign = left and -1 or 1
    local edge = RING_SIZE / 2 * 0.72 -- 45 degrees round the ring
    -- Level badge: a small dark disc in the same ring.
    local badge = CreateFrame("Frame", nil, id)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    local jx, jy = HealthJunction() -- where the health ring meets the portrait: covers that seam
    jx = jx - BADGE_OUT
    PixelUtil.SetPoint(badge, "CENTER", id, "CENTER", left and jx or -jx, jy)
    badge:SetFrameLevel(id:GetFrameLevel() + 2)
    local badgeFill = badge:CreateTexture(nil, "BACKGROUND")
    badgeFill:SetAllPoints()
    badgeFill:SetColorTexture(0.05, 0.05, 0.05, 1)
    local badgeMask = badge:CreateMaskTexture()
    badgeMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    badgeMask:SetAllPoints(badgeFill)
    badgeFill:AddMaskTexture(badgeMask)
    local badgeRing = badge:CreateTexture(nil, "OVERLAY")
    badgeRing:SetSize(BADGE_SIZE * 128 / 104, BADGE_SIZE * 128 / 104)
    badgeRing:SetPoint("CENTER")
    badgeRing:SetTexture(MEDIA .. "ArcRing")
    s.badgeRing = badgeRing
    -- Centred in the badge both ways (no shadow: it pulls small text off
    -- centre).
    s.level = NewText(badge, 10)
    s.level:SetAllPoints(badge)
    s.level:SetJustifyH("CENTER")
    s.level:SetJustifyV("MIDDLE")
    s.level:SetShadowOffset(0, 0)
    s.name = NewText(id, NAME_FONT_SIZE)
    s.name:SetPoint(left and "RIGHT" or "LEFT", id, outer, sign * (RING_SIZE - PORTRAIT_SIZE) / 2 + sign * ID_GAP, NAME_UP)
    s.faction = id:CreateTexture(nil, "OVERLAY", nil, 1)
    s.faction:SetSize(FACTION_SIZE, FACTION_SIZE)
    s.faction:SetPoint("CENTER", id, "TOP", 0, (RING_SIZE - PORTRAIT_SIZE) / 2)
    s.faction:Hide()
    frame:SetAlpha(0)
    sides[key] = s
    return s
end

-- The arcs' anchors: x from the unit frames' outer edges, y the HUD's centre
-- (one anchor point can't take x and y from different frames, so the
-- offset is measured). Again whenever the frames may have moved; not in combat
-- once the click buttons hang off the anchors.
local clicksBuilt = false
local UNIT_FRAMES = { player = "PlayerFrame", target = "TargetFrame" }

local function PlaceSides()
    if not hud or (clicksBuilt and InCombatLockdown()) then return end
    local hx = hud:GetCenter()
    if not hx then return end
    for key, s in pairs(sides) do
        local left = key == "player"
        local unitFrame = _G[UNIT_FRAMES[key]]
        local edge = unitFrame and (left and unitFrame:GetLeft() or unitFrame:GetRight())
        local x
        if edge then
            x = edge * unitFrame:GetEffectiveScale() / hud:GetEffectiveScale() - hx + (left and -FRAME_X or FRAME_X)
        else
            x = left and -40 - SIDE_W or 40 + SIDE_W
        end
        if s.placedX ~= x then
            s.placedX = x
            s.anchor:ClearAllPoints()
            s.anchor:SetPoint(left and "LEFT" or "RIGHT", hud, "CENTER", x, ARC_Y)
        end
    end
end

local function Build()
    hud = CreateFrame("Frame", "KuroKitArcHUD", UIParent)
    hud:SetSize(1, 1)
    hud:SetPoint("CENTER", UIParent, "CENTER", 0, CENTER_Y)
    hud:SetFrameStrata("LOW")
    hud:EnableMouse(false)
    NewSide("player", "Left")
    NewSide("target", "Right")
    PlaceSides()

    local frame = CreateFrame("Frame", nil, hud)
    frame:SetSize(CAST_W, CAST_H)
    if PlayerCastingBarFrame then
        frame:SetPoint("CENTER", PlayerCastingBarFrame, "CENTER", 0, CAST_Y)
    else
        frame:SetPoint("TOP", hud, "CENTER", 0, -128)
    end
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetAlpha(BACK_ALPHA)
    back:SetTexture(MEDIA .. "ArcCastBack")
    cast = { frame = frame, alpha = 0, wanted = 0 }
    local cols = CreateFrame("Frame", nil, frame)
    cols:SetPoint("TOPLEFT", frame, "TOPLEFT", CAST_FILL_LEFT * SCALE, 0)
    cols:SetSize((CAST_FILL_RIGHT - CAST_FILL_LEFT) * SCALE, CAST_H)
    cast.bar = NewBar(cols, MEDIA .. "ArcCastFill", "HORIZONTAL")
    local flashFrame = CreateFrame("Frame", nil, frame)
    flashFrame:SetAllPoints()
    flashFrame:SetFrameLevel(cast.bar:GetFrameLevel() + 2)
    cast.flash = flashFrame:CreateTexture(nil, "ARTWORK")
    cast.flash:SetAllPoints()
    cast.flash:SetTexture(MEDIA .. "ArcCast")
    cast.flash:SetVertexColor(INTERRUPT_COLOR[1], INTERRUPT_COLOR[2], INTERRUPT_COLOR[3])
    cast.flash:Hide()
    cast.bar:SetAlpha(FILL_ALPHA)
    -- Latency: the same arc from the cast's end (reverse fill), translucent red.
    cast.latency = NewBar(cols, MEDIA .. "ArcCastFill", "HORIZONTAL")
    cast.latency:SetFrameLevel(cast.bar:GetFrameLevel() + 1)
    cast.latency:SetStatusBarColor(LATENCY_COLOR[1], LATENCY_COLOR[2], LATENCY_COLOR[3], LATENCY_COLOR[4])
    local texts = CreateFrame("Frame", nil, frame)
    texts:SetAllPoints()
    texts:SetFrameLevel(cast.latency:GetFrameLevel() + 1)
    cast.name = NewText(texts, NAME_FONT_SIZE)
    cast.name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    cast.name:SetPoint("TOP", frame, "BOTTOM", 0, -TEXT_GAP)
    -- The spell icon by the left tip, in the action bar's icon look.
    local icon = texts:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CAST_ICON_SIZE, CAST_ICON_SIZE)
    icon:SetPoint("RIGHT", frame, "TOPLEFT", CAST_W * CAST_ICON_X, CAST_H * CAST_TIP_Y)
    local mask = texts:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetPoint("CENTER", icon, "CENTER")
    mask:SetSize(CAST_ICON_SIZE * 1.5, CAST_ICON_SIZE * 1.5) -- as on Blizzard's small action buttons
    icon:AddMaskTexture(mask)
    local iconFrame = texts:CreateTexture(nil, "OVERLAY")
    iconFrame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    iconFrame:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", CAST_ICON_SIZE / 45, 0)
    cast.icon = icon
    cast.timer = NewText(texts, NAME_FONT_SIZE)
    cast.timer:SetTextColor(1, 1, 1)
    cast.timer:SetPoint("LEFT", frame, "TOPLEFT", CAST_W * CAST_TIP_X, CAST_H * CAST_TIP_Y)
    frame:SetAlpha(0)

    if C_CurveUtil and C_CurveUtil.CreateColorCurve then
        healthCurve = C_CurveUtil.CreateColorCurve()
        healthCurve:AddPoint(0, HEALTH_RED)
        healthCurve:AddPoint(0.35, HEALTH_YELLOW)
        healthCurve:AddPoint(0.7, HEALTH_GREEN)
        healthCurve:AddPoint(1, HEALTH_GREEN)
        -- The same, lifted, for the text (the curve's result may be secret:
        -- no arithmetic on it).
        healthTextCurve = C_CurveUtil.CreateColorCurve()
        for _, point in ipairs({ { 0, HEALTH_RED }, { 0.35, HEALTH_YELLOW }, { 0.7, HEALTH_GREEN }, { 1, HEALTH_GREEN } }) do
            healthTextCurve:AddPoint(point[1], CreateColor(Lift(point[2]:GetRGB())))
        end
    end
end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------
local function HealthColor(s, unit)
    local bar = s.health
    do
        -- Players (you too) in their class colour, NPCs in their reaction
        -- colour. (Class token and colours may be secret: only type-checked,
        -- passed on.)
        local isPlayer = UnitIsPlayer(unit)
        if not Secret(isPlayer) and isPlayer then
            local _, class = UnitClass(unit)
            local color = type(class) ~= "nil" and C_ClassColor.GetClassColor(class)
            if color and pcall(bar.SetStatusBarColor, bar, color:GetRGB()) then return end
        end
        local ok, r, g, b = pcall(UnitSelectionColor, unit)
        if ok and type(r) == "number" and pcall(bar.SetStatusBarColor, bar, r, g, b) then return end
    end
    if healthCurve then
        local ok, color = pcall(UnitHealthPercent, unit, true, healthCurve)
        if ok and color and color.GetRGB and pcall(bar.SetStatusBarColor, bar, color:GetRGB()) then return end
    end
    bar:SetStatusBarColor(HEALTH_GREEN:GetRGB())
end

-- "1.1K  81%" (left side) / "81%  1.1K" (right side); both may be secret
-- (passed to the font string only).
local function SetValueText(fs, percent, value, valueFirst)
    local fmt = valueFirst and "%2$s  %1$.0f%%" or "%1$.0f%%  %2$s"
    local ok = AbbreviateNumbers and pcall(function() fs:SetFormattedText(fmt, percent, AbbreviateNumbers(value)) end)
    if not ok then
        fs:SetFormattedText(valueFirst and "%2$d  %1$.0f%%" or "%1$.0f%%  %2$d", percent, value)
    end
end

local function UpdateHealth(key)
    local s, unit = sides[key], key
    if not (s and UnitExists(unit)) then return end
    SetBarValue(s.health, UnitHealthPercent(unit, true))
    if Scale100() then
        SetValueText(s.healthText, UnitHealthPercent(unit, true, Scale100()), UnitHealth(unit), key == "player")
    end
    HealthColor(s, unit)
    -- Text: the bar colour lifted toward white.
    local r, g, b = s.health:GetStatusBarColor()
    if not (Secret(r) or Secret(g) or Secret(b)) and type(r) == "number" then
        s.healthText:SetTextColor(Lift(r, g, b))
    elseif healthTextCurve then
        local ok, color = pcall(UnitHealthPercent, unit, true, healthTextCurve)
        if ok and color and color.GetRGB then pcall(s.healthText.SetTextColor, s.healthText, color:GetRGB()) end
    end
end

local function UpdatePower(key)
    local s, unit = sides[key], key
    if not (s and UnitExists(unit)) then return end
    -- No power at all (most beasts, undead): an empty arc, no text.
    local max = UnitPowerMax(unit)
    if not Secret(max) and (max or 0) <= 0 then
        s.power:SetValue(0)
        s.powerText:SetText("")
        return
    end
    local ok, value = pcall(UnitPowerPercent, unit, nil, false)
    if ok and type(value) ~= "nil" then SetBarValue(s.power, value) end
    local okText, percent = pcall(UnitPowerPercent, unit, nil, false, Scale100())
    if okText and type(percent) ~= "nil" then
        SetValueText(s.powerText, percent, UnitPower(unit), key == "player")
    else
        s.powerText:SetText("")
    end
    local _, token = UnitPowerType(unit)
    local color = not Secret(token) and token and PowerBarColor and PowerBarColor[token]
    if color then
        s.power:SetStatusBarColor(color.r, color.g, color.b)
        s.powerText:SetTextColor(Lift(color.r, color.g, color.b))
    end
end

local function UpdateUnit(key)
    UpdateHealth(key)
    UpdatePower(key)
end

---------------------------------------------------------------------------
-- Identity
---------------------------------------------------------------------------
local function UnitRGB(unit)
    local isPlayer = UnitIsPlayer(unit)
    if not Secret(isPlayer) and isPlayer then
        local _, class = UnitClass(unit)
        local color = type(class) ~= "nil" and C_ClassColor.GetClassColor(class)
        if color then return color:GetRGB() end
    end
    local ok, r, g, b = pcall(UnitSelectionColor, unit)
    if ok and type(r) == "number" then return r, g, b end
    return 1, 1, 1
end

local function UpdateIdentity(key)
    local s, unit = sides[key], key
    if not (s and UnitExists(unit)) then return end
    SetPortraitTexture(s.portrait, unit)
    -- Forever players have a surname: the full name when it can be read.
    local fullName = ns.UnitFullName(unit)
    if fullName then s.name:SetText(fullName) else s.name:SetText(UnitName(unit)) end
    pcall(s.name.SetTextColor, s.name, UnitRGB(unit))
    local classification = UnitClassification(unit)
    if Secret(classification) then classification = nil end
    local metal = RINGS[classification]
    s.ring:SetShown(metal ~= nil)
    if metal then s.ring:SetTexture(MEDIA .. metal) end
    s.badgeRing:SetTexture(MEDIA .. (metal or "ArcRing"))
    local level = UnitLevel(unit)
    if Secret(level) then
        s.level:SetText(level)
        s.level:SetTextColor(1, 1, 1)
    elseif level and level < 0 then
        s.level:SetText("??")
        s.level:SetTextColor(1, 0.1, 0.1)
    elseif level then
        local elite = classification == "elite" or classification == "rareelite" or classification == "worldboss"
        s.level:SetText(elite and (level .. "+") or level)
        if key == "player" then
            -- Rested blue while resting (as the Unit Frames module colours the
            -- player frame's level), gold otherwise.
            if IsResting() then
                s.level:SetTextColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3])
            else
                s.level:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
            end
        else
            local c = GetCreatureDifficultyColor(level)
            s.level:SetTextColor(c.r, c.g, c.b)
        end
    end
    local atlas
    local ffa, pvp = UnitIsPVPFreeForAll(unit), UnitIsPVP(unit)
    if not Secret(ffa) and ffa then
        atlas = FFA_ATLAS
    elseif not Secret(pvp) and pvp then
        local faction = UnitFactionGroup(unit)
        atlas = not Secret(faction) and FACTION_ATLAS[faction]
    end
    if atlas and C_Texture.GetAtlasInfo(atlas) then
        s.faction:SetAtlas(atlas)
        s.faction:Show()
    else
        s.faction:Hide()
    end
end

---------------------------------------------------------------------------
-- Clicks: secure unit buttons on the portraits and along the arcs
---------------------------------------------------------------------------
local function OnEnterUnit(self)
    local unit = self:GetAttribute("unit")
    if not (unit and UnitExists(unit)) then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function NewUnitButton(parent, unit)
    local button = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
    button:SetAttribute("unit", unit)
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnEnter", OnEnterUnit)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function BuildClicks(key, condition)
    local s, left = sides[key], key == "player"
    local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    header:SetAllPoints(s.anchor)
    header:SetFrameStrata("LOW")
    header:SetFrameLevel(s.frame:GetFrameLevel() + 20)
    RegisterStateDriver(header, "visibility", condition)
    local px, py = PortraitPoint(left)
    local portrait = NewUnitButton(header, key)
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portrait:SetPoint("CENTER", header, "TOPLEFT", px, -py)
    local height = 2 * ARC_R * math.sin(ARC_HALF) * SCALE / CLICK_SEGMENTS
    for i = 1, CLICK_SEGMENTS do
        local angle = -ARC_HALF + (i - 0.5) * 2 * ARC_HALF / CLICK_SEGMENTS
        local x, y = ArcPoint(angle, left)
        local button = NewUnitButton(header, key)
        button:SetSize(CLICK_WIDTH, height)
        button:SetPoint("CENTER", header, "TOPLEFT", x, -y)
    end
    if key == "target" then
        -- Target of target (shown while it exists).
        local tot = NewUnitButton(header, "targettarget")
        tot:SetSize(T.TOT_W, T.TOT_FONT_SIZE + 2 + T.TOT_BAR_H)
        tot:SetPoint("RIGHT", header, "TOPLEFT", px - RING_SIZE / 2 - T.TOT_GAP, -py)
        RegisterStateDriver(tot, "visibility", "[@targettarget,exists] show; hide")
    end
end

-- Blizzard's player cast bar out of sight: alpha 0 (kept there, except in
-- Edit Mode, to move it), and its fade animations (interrupted / failed
-- casts) fade from 0 to 0, since an animation sets the alpha without
-- SetAlpha.
local editingCastBar = false
local function HideCastBar(bar)
    if not bar then return end
    bar:SetAlpha(0)
    hooksecurefunc(bar, "SetAlpha", function(self, alpha)
        if not editingCastBar and alpha ~= 0 then self:SetAlpha(0) end
    end)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function()
            editingCastBar = true
            bar:SetAlpha(1)
            -- (and the cast arc on it)
            cast.name:SetText(HUD_EDIT_MODE_CAST_BAR_LABEL or "Cast Bar")
            cast.wanted = 1
        end)
        EditModeManagerFrame:HookScript("OnHide", function()
            editingCastBar = false
            bar:SetAlpha(0)
            if not cast.casting and not cast.holdUntil then cast.wanted = 0 end
        end)
    end
    for _, group in ipairs({ bar:GetAnimationGroups() }) do
        for _, anim in ipairs({ group:GetAnimations() }) do
            if anim:GetObjectType() == "Alpha" then
                anim:SetFromAlpha(0)
                anim:SetToAlpha(0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Blizzard's player and target frames step back while the arcs show
---------------------------------------------------------------------------
-- Each part's alpha is Blizzard's own (kept from its SetAlpha calls) times
-- its frame's step (1 shown .. 0 stepped back). Parts: the frames' children
-- and regions, except your class resources and the target's buffs / debuffs
-- (which live in the content's contextual part, so that one goes part by
-- part). Gathered again on each change (the Unit Frames skin adds its own).
local step = { player = 1, target = 1 }
local partKey, partBase = {}, {}
local settingPart = false
local castAnims = {}    -- the target cast bar's fade animations: { anim, from, to }

local function SetPartAlpha(part)
    local base, k = partBase[part], step[partKey[part]]
    settingPart = true
    if Secret(base) then
        part:SetAlpha(k >= 1 and base or 0)
    else
        part:SetAlpha((base or 1) * k)
    end
    settingPart = false
end

local function AddPart(key, part)
    if not part or partKey[part] or not part.SetAlpha then return end
    partKey[part] = key
    partBase[part] = part:GetAlpha()
    hooksecurefunc(part, "SetAlpha", function(self, alpha)
        if settingPart then return end
        partBase[self] = alpha
        SetPartAlpha(self)
    end)
end

local function AddChildren(key, frame, except)
    if not frame then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not except[child] then AddPart(key, child) end
    end
    for _, region in ipairs({ frame:GetRegions() }) do AddPart(key, region) end
end

local function GatherParts()
    if PlayerFrame then
        local keep = { [PlayerFrame.classPowerBar or false] = true }
        for _, child in ipairs({ PlayerFrame:GetChildren() }) do
            local name = child:GetName()
            if name and name:find("ManagedFrames") then keep[child] = true end
        end
        AddChildren("player", PlayerFrame, keep)
    end
    if TargetFrame then
        local content = TargetFrame.TargetFrameContent
        local contextual = content and content.TargetFrameContentContextual
        local auras = TargetFrame.GetAuraContainer and TargetFrame:GetAuraContainer()
        AddChildren("target", TargetFrame, { [content or false] = true })
        AddChildren("target", content, { [contextual or false] = true })
        AddChildren("target", contextual, { [auras or false] = true })
    end
end

-- The target cast bar's interrupted / failed fade sets the alpha without
-- SetAlpha: from 0 to 0 while the frame steps back.
local function MuteCastAnims(muted)
    for _, a in ipairs(castAnims) do
        a[1]:SetFromAlpha(muted and 0 or a[2])
        a[1]:SetToAlpha(muted and 0 or a[3])
    end
end

local function StepFrame(key, value)
    if step[key] == value then return end
    local wasShown = step[key] >= 1
    step[key] = value
    GatherParts()
    for part, k in pairs(partKey) do
        if k == key then SetPartAlpha(part) end
    end
    if key == "target" and wasShown ~= (value >= 1) then MuteCastAnims(value < 1) end
end

---------------------------------------------------------------------------
-- Target cast bar (ours, on the arc; Blizzard's steps back with its frame)
---------------------------------------------------------------------------
local tcast  -- { bar, back, icon, name, timer, lock, casting, channel }

-- An interrupted / failed cast: the bar full in red with the reason for
-- INTERRUPT_HOLD, then the fade. Only for a cast that was showing.
-- Whether an interrupted / failed event (its cast GUID and spell) is about
-- the cast shown. Pressing another spell mid-cast or mid-channel reports
-- that attempt as failed (or interrupted) too: Blizzard's own cast bar
-- ignores those, and so does this. GUIDs first, then spell IDs (either may
-- be secret or empty: then the next); neither readable: only while it runs.
local function SameCast(item, guid, spellID)
    local function Usable(a, b) return a ~= nil and b ~= nil and a ~= "" and b ~= "" and not Secret(a) and not Secret(b) end
    if Usable(guid, item.guid) then return guid == item.guid end
    if Usable(spellID, item.spellID) then return spellID == item.spellID end
    return item.casting
end

-- The cast's end time (seconds; nil if unreadable), from its info's end in ms.
local function CastEnd(endMS)
    if type(endMS) ~= "number" or Secret(endMS) then return nil end
    return endMS / 1000
end

local function ShowInterrupted(item, reason, guid, spellID)
    if not (item.casting or item.alpha > 0) then return end
    if not SameCast(item, guid, spellID) then return end
    -- Stopped at (about) its own end: it finished, whatever comes after.
    if not item.casting and item.endsAt and item.stoppedAt and item.stoppedAt >= item.endsAt - INTERRUPT_GRACE then
        return
    end
    item.casting = false
    item.flash:Show()
    item.name:SetText(reason)
    item.timer:SetText("")
    if item.latency then item.latency:SetValue(0) end
    item.wanted = 1
    item.holdUntil = GetTime() + INTERRUPT_HOLD
end

local function ClearInterrupted(item)
    item.flash:Hide()
    item.holdUntil = nil
end


local function AtlasOr(texture, atlas)
    if C_Texture.GetAtlasInfo(atlas) then texture:SetAtlas(atlas) return true end
end

local function BuildTargetCast()
    local bar = CreateFrame("StatusBar", nil, sides.target.frame)
    bar:SetSize(TCAST_W, TCAST_H)
    local _, py = PortraitPoint(false)
    local portraitY = SIDE_H / 2 - py -- the portrait's centre, from the arc frame's middle
    bar:SetPoint("LEFT", sides.target.frame, "RIGHT", TCAST_X + TCAST_ICON + 4, portraitY + TCAST_Y)
    bar:SetMinMaxValues(0, 1)
    if C_Texture.GetAtlasInfo(TCAST_FILL) then
        bar:SetStatusBarTexture(TCAST_FILL)
    else
        bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
        bar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    end
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    if not AtlasOr(back, TCAST_BACK) then back:SetColorTexture(0, 0, 0, 0.7) end
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TCAST_ICON, TCAST_ICON)
    icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    local mask = bar:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetPoint("CENTER", icon, "CENTER")
    mask:SetSize(TCAST_ICON * 1.5, TCAST_ICON * 1.5)
    icon:AddMaskTexture(mask)
    local iconFrame = bar:CreateTexture(nil, "OVERLAY")
    iconFrame:SetAtlas("UI-HUD-ActionBar-IconFrame")
    iconFrame:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", TCAST_ICON / 45, 0)
    local lock = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    lock:SetSize(TCAST_H + 8, TCAST_H + 8)
    lock:SetPoint("CENTER", bar, "LEFT", 0, 0)
    if not AtlasOr(lock, TCAST_LOCK) then lock:SetTexture(nil) end
    lock:SetAlpha(0)
    local name = NewText(bar, NAME_FONT_SIZE)
    name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    name:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -TEXT_GAP)
    local timer = NewText(bar, NAME_FONT_SIZE)
    timer:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -TEXT_GAP)
    local flash = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    flash:SetAllPoints(bar)
    if not AtlasOr(flash, TCAST_INTERRUPTED) then
        flash:SetColorTexture(INTERRUPT_COLOR[1], INTERRUPT_COLOR[2], INTERRUPT_COLOR[3], 1)
    end
    flash:Hide()
    bar:SetAlpha(0)
    tcast = { bar = bar, icon = icon, name = name, timer = timer, lock = lock, flash = flash, alpha = 0, wanted = 0,
        frame = bar }
end

local function TargetCastDuration()
    return (tcast.channel and UnitChannelDuration or UnitCastingDuration)("target")
end

local function StartTargetCast(channel, guid, spellID)
    if not UnitExists("target") then tcast.wanted = 0 return end
    local info = { (channel and UnitChannelInfo or UnitCastingInfo)("target") }
    if type(info[1]) == "nil" then tcast.wanted = 0 tcast.casting = false return end
    ClearInterrupted(tcast)
    tcast.channel = channel
    tcast.guid, tcast.spellID, tcast.endsAt, tcast.stoppedAt = guid, spellID, CastEnd(info[5]), nil
    local duration = TargetCastDuration()
    if not duration then tcast.wanted = 0 return end
    local direction = Enum.StatusBarTimerDirection
    tcast.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
        direction and (channel and direction.RemainingTime or direction.ElapsedTime))
    local fill = channel and TCAST_CHANNEL_FILL or TCAST_FILL
    if C_Texture.GetAtlasInfo(fill) then tcast.bar:GetStatusBarTexture():SetAtlas(fill) end
    tcast.name:SetText(info[1])
    pcall(tcast.icon.SetTexture, tcast.icon, info[3])
    -- Not interruptible (may be secret): the lock through SetAlphaFromBoolean.
    local locked = info[channel and 7 or 8]
    if type(locked) == "nil" then
        tcast.lock:SetAlpha(0)
    elseif not pcall(tcast.lock.SetAlphaFromBoolean, tcast.lock, locked, 1, 0) then
        tcast.lock:SetAlpha(0)
    end
    tcast.casting = true
    tcast.wanted = 1
end

local function StopTargetCast()
    tcast.casting = false
    tcast.stoppedAt = GetTime()
    if not tcast.holdUntil then tcast.wanted = 0 end
end

-- A cast already running when you pick the target.
local function CheckTargetCast()
    -- (These return nothing at all without a cast: into a local first.)
    local casting = UnitCastingInfo("target")
    local channeling = UnitChannelInfo("target")
    if type(casting) ~= "nil" then
        StartTargetCast(false)
    elseif type(channeling) ~= "nil" then
        StartTargetCast(true)
    else
        StopTargetCast()
    end
end

local sinceTargetTimer = 0
local function UpdateTargetCastTimer(elapsed)
    if not tcast.casting then return end
    sinceTargetTimer = sinceTargetTimer + elapsed
    if sinceTargetTimer < TIMER_INTERVAL then return end
    sinceTargetTimer = 0
    local duration = TargetCastDuration()
    if duration and duration.GetRemainingDuration then
        tcast.timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        tcast.timer:SetText("")
    end
end

---------------------------------------------------------------------------
-- Cast
---------------------------------------------------------------------------
local function CastDuration()
    return (cast.channel and UnitChannelDuration or UnitCastingDuration)("player")
end

-- The latency zone: latency / cast time of the arc, from the end the next
-- cast queues at (the end for casts, the start for channels).
local function PlaceLatency()
    local _, _, _, startMS, endMS = (cast.channel and UnitChannelInfo or UnitCastingInfo)("player")
    local _, _, _, latency = GetNetStats()
    if Secret(startMS) or Secret(endMS) or type(startMS) ~= "number" or type(endMS) ~= "number"
        or endMS <= startMS or not latency or latency <= 0 then
        cast.latency:SetValue(0)
        return
    end
    local style = Enum.StatusBarFillStyle
    if style then cast.latency:SetFillStyle(cast.channel and style.Standard or style.Reverse) end
    cast.latency:SetValue(math.min(1, latency / (endMS - startMS)))
end

local function StartCast(channel, guid, spellID)
    ClearInterrupted(cast)
    cast.channel = channel
    local _, _, _, _, endMS = (channel and UnitChannelInfo or UnitCastingInfo)("player")
    cast.guid, cast.spellID, cast.endsAt, cast.stoppedAt = guid, spellID, CastEnd(endMS), nil
    local duration = CastDuration()
    if not duration then return end
    local direction = Enum.StatusBarTimerDirection
    cast.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
        direction and (channel and direction.RemainingTime or direction.ElapsedTime))
    local color = channel and CHANNEL_COLOR or CAST_COLOR
    cast.bar:SetStatusBarColor(color[1], color[2], color[3])
    local name, _, texture = (channel and UnitChannelInfo or UnitCastingInfo)("player")
    if type(name) == "nil" then cast.name:SetText("") else cast.name:SetText(name) end
    if not pcall(cast.icon.SetTexture, cast.icon, texture) then cast.icon:SetTexture(nil) end
    PlaceLatency()
    cast.casting = true
    cast.wanted = 1
end

local function StopCast()
    cast.casting = false
    cast.stoppedAt = GetTime()
    if not cast.holdUntil then cast.wanted = 0 end
end

-- Time left, while casting.
local sinceTimer = 0
local function UpdateCastTimer(elapsed)
    if not cast.casting then return end
    sinceTimer = sinceTimer + elapsed
    if sinceTimer < TIMER_INTERVAL then return end
    sinceTimer = 0
    local duration = CastDuration()
    if duration and duration.GetRemainingDuration then
        cast.timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
    else
        cast.timer:SetText("")
    end
end

---------------------------------------------------------------------------
-- Trims (thin rings along your arc) and target of target
---------------------------------------------------------------------------
do -- (a block: its locals don't count toward the main chunk's limit)
local trims = {}   -- [key] = { frame, bar, track } for this class's trims
local BuildCombo   -- (defined with the combo points below)
local fullCurve       -- power percent -> alpha: 1 below full, 0 at full

-- A trim's top end (angle, negative up): where its ring would meet
-- TRIM_CLEAR round the socket (T.CLEAR).
local function TrimTop(rIn, rOut)
    local best = 0
    for _, r in ipairs({ rIn, rOut }) do
        local c = (r * r + ARC_R * ARC_R - T.CLEAR * T.CLEAR) / (2 * r * ARC_R)
        if c < 1 then best = math.max(best, math.acos(c)) end
    end
    return SOCKET_ANGLE + best
end

local function NewTrim(key, spec)
    local s = sides.player
    local rIn, rOut = spec[1], spec[2]
    local yTop = ARC_CY + rOut * math.sin(TrimTop(rIn, rOut))
    local extent = ARC_CY + rOut * math.sin(ARC_HALF) - yTop
    local frame = CreateFrame("Frame", nil, s.frame)
    frame:SetPoint("TOPLEFT", s.frame, "TOPLEFT", (ARC_CX - rOut - T.MARGIN) * SCALE, -yTop * SCALE)
    frame:SetSize(T.W * extent / T.H * SCALE, extent * SCALE)
    frame:SetFrameLevel(s.power:GetFrameLevel())
    local track = frame:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(MEDIA .. spec.texture)
    track:SetVertexColor(0.05, 0.05, 0.05)
    track:SetAlpha(spec.trackAlpha or T.TRACK_ALPHA)
    local bar = NewBar(frame, MEDIA .. spec.texture, "VERTICAL")
    bar:SetAlpha(spec.fillAlpha or FILL_ALPHA)
    trims[key] = { frame = frame, bar = bar, track = track }
    return trims[key]
end

-- The mini arc's fill rows (px from its top): ArcMiniFill is the fill cut to
-- these (tools/make_arcs.py mini_rows: the same numbers).
local function MiniRows()
    local reach = T.MINI_R_OUT * math.sin(T.MINI_HALF)
    return math.floor(T.MINI_CY - reach), math.ceil(T.MINI_CY + reach)
end

-- A burst: a glowing ring round your character swelling outward and
-- fading, BURST_PULSES times. `gated` (the shield's): each flash sits
-- in a clipping window that is the empty part of a bar whose value is your
-- absorb over 0..1: any shield fills the bar and closes the window, none
-- leaves it open. The window is anchored to the bar's fill, so the client
-- lays it out from the secret amount; the addon never reads it. The burst
-- plays on every absorb change and only shows when the shield is gone.
-- Where that anchoring fails: shown only for a readable 0 (out of combat).
local function NewGate(parent, level)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(level)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetClipsChildren(true)
    local ok = pcall(function()
        clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
        clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    end)
    if not ok then
        clip:ClearAllPoints()
        clip:SetAllPoints(bar)
    end
    return { bar = bar, clip = clip }, ok
end
local function AddPulse(group, target, order, peak, scaleTo)
    local fade = group:CreateAnimation("Alpha")
    fade:SetTarget(target)
    fade:SetOrder(order)
    fade:SetFromAlpha(peak)
    fade:SetToAlpha(0)
    fade:SetDuration(T.BURST_TIME)
    fade:SetSmoothing("OUT")
    if scaleTo then
        local grow = group:CreateAnimation("Scale")
        grow:SetTarget(target)
        grow:SetOrder(order)
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(scaleTo, scaleTo)
        grow:SetOrigin("CENTER", 0, 0)
        grow:SetDuration(T.BURST_TIME)
        grow:SetSmoothing("OUT")
    end
end

local function NewBurst(color, gated)
    local s = sides.player
    local burst = { gates = {}, gated = gated }
    -- A ring round your character (the HUD's centre), swelling outward.
    local parent = s.frame
    if gated then
        local gate, ok = NewGate(s.frame, s.id:GetFrameLevel() + 4)
        local size = T.BURST_SIZE * T.BURST_SCALE * 2 -- (generous: the swell and its soft edge never reach it)
        gate.bar:SetSize(size, size)
        gate.bar:SetPoint("CENTER", hud, "CENTER", 0, T.BURST_Y)
        burst.gates = { gate }
        burst.gated = ok
        parent = gate.clip
    end
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(T.BURST_SIZE, T.BURST_SIZE)
    ring:SetPoint("CENTER", hud, "CENTER", 0, T.BURST_Y)
    ring:SetFrameLevel(s.id:GetFrameLevel() + 5)
    local tex = ring:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "ArcGlow")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(color[1], color[2], color[3])
    ring:SetAlpha(0)
    burst.group = s.frame:CreateAnimationGroup()
    for i = 1, T.BURST_PULSES do AddPulse(burst.group, ring, i, 1, T.BURST_SCALE) end
    return burst
end

local function PlayBurst(burst)
    burst.group:Stop()
    burst.group:Play()
end

-- The shield's burst, on each absorb change (see NewBurst).
local function ShieldBurst(amount)
    local burst = trims.shield and trims.shield.burst
    if not burst then return end
    if burst.gated then
        for _, gate in ipairs(burst.gates) do pcall(gate.bar.SetValue, gate.bar, amount) end
    elseif Secret(amount) or amount > 0 then
        return
    end
    PlayBurst(burst)
end

-- The shield: a sheen over your health arc (a bar over just the fill's
-- rows, so its value maps straight on: absorb over the shield's size) and
-- a glow round your portrait, itself a bar over 0..1 whose value is the
-- absorb, so any shield shows it whole and none hides it (the amount may be
-- secret: never tested, only handed to the bars).
local function NewShield()
    local s = sides.player
    -- The mini arc beside your character: its back a bar too (full with any
    -- shield, empty without), the fill a bar over just the fill's rows.
    local frame = CreateFrame("Frame", nil, s.frame)
    frame:SetSize(T.MINI_W * SCALE, T.MINI_H * SCALE)
    frame:SetPoint("CENTER", hud, "CENTER", T.MINI_X, T.MINI_Y)
    frame:SetFrameLevel(s.id:GetFrameLevel())
    local back = NewBar(frame, MEDIA .. "ArcMiniBack", "HORIZONTAL")
    back:SetAlpha(T.MINI_BACK_ALPHA)
    local top, bottom = MiniRows()
    local rows = CreateFrame("Frame", nil, frame)
    rows:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top * SCALE)
    rows:SetSize(T.MINI_W * SCALE, (bottom - top) * SCALE)
    local bar = NewBar(rows, MEDIA .. "ArcMiniFill", "VERTICAL")
    bar:SetFrameLevel(back:GetFrameLevel() + 1)
    bar:SetAlpha(T.MINI_FILL_ALPHA)
    local glow = CreateFrame("StatusBar", nil, s.id)
    glow:SetSize(GLOW_SIZE, GLOW_SIZE)
    glow:SetPoint("CENTER", s.id, "CENTER")
    glow:SetFrameLevel(math.max(0, s.id:GetFrameLevel() - 1))
    glow:SetStatusBarTexture(MEDIA .. "ArcGlow")
    glow:GetStatusBarTexture():SetBlendMode("ADD")
    glow:SetMinMaxValues(0, 1)
    glow:SetValue(0)
    glow:SetAlpha(GLOW_ALPHA)
    glow:SetStatusBarColor(T.SHIELD_COLOR[1], T.SHIELD_COLOR[2], T.SHIELD_COLOR[3])
    bar:SetStatusBarColor(T.SHIELD_COLOR[1], T.SHIELD_COLOR[2], T.SHIELD_COLOR[3])
    trims.shield = { frame = frame, bar = bar, track = glow, back = back, burst = NewBurst(T.BREAK_COLOR, true) }
end

-- Weakened Soul: a cooldown sweep over your portrait, red, with its seconds.
local function NewSoul()
    local s = sides.player
    local cd = CreateFrame("Cooldown", nil, s.id, "CooldownFrameTemplate")
    cd:SetAllPoints(s.portrait)
    cd:SetFrameLevel(s.id:GetFrameLevel() + 1)
    cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    cd:SetSwipeColor(T.SOUL_COLOR[1], T.SOUL_COLOR[2], T.SOUL_COLOR[3], SOUL_SWEEP_ALPHA)
    if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(false)
    local text = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if text then
        local file = text:GetFont()
        if file then text:SetFont(file, SOUL_FONT_SIZE, "OUTLINE") end
        text:SetTextColor(1, 0.85, 0.8)
    end
    local t = { cooldown = cd, burst = NewBurst(T.READY_COLOR), burstAt = 0 }
    -- Its end: the ready burst (once: the aura's end and the sweep's may
    -- both report it).
    function t.Ready()
        if GetTime() - t.burstAt < 2 then return end
        t.burstAt = GetTime()
        PlayBurst(t.burst) -- (blue round your character: you can shield again)
        -- and Weakened Soul's icon pulsing above your character, blue
        local ok, icon = pcall(C_Spell.GetSpellTexture, T.SOUL_SPELL)
        if ok and icon then M.QueuePulse(icon, T.READY_COLOR) end
    end
    cd:SetScript("OnCooldownDone", function()
        t.finished = true -- (its state is cleared with the clock, below)
        t.Ready()
    end)
    trims.soul = t
end

function BuildTrims()
    local _, class = UnitClass("player")
    for key, spec in pairs(TRIMS) do
        local wanted
        if key == "tick" then wanted = not T.NO_TICK[class] else wanted = TRIM_CLASSES[key][class] end
        if wanted then NewTrim(key, spec) end
    end
    if TRIM_CLASSES.shield[class] then NewShield() end
    BuildCombo()
    if trims.mana then
        local c = PowerBarColor and PowerBarColor.MANA
        if c then trims.mana.bar:SetStatusBarColor(c.r, c.g, c.b) end
    end
    if TRIM_CLASSES.soul[class] then NewSoul() end
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        fullCurve = C_CurveUtil.CreateCurve()
        if fullCurve.SetType and Enum.LuaCurveType then fullCurve:SetType(Enum.LuaCurveType.Step) end
        fullCurve:AddPoint(0, 1)
        fullCurve:AddPoint(1, 0)
    end
end

-- The Cooldown Manager rails' arc edge (texture px): past this class's trims.
function M.RailEdge(layout)
    local edge = layout.outside and ARC_OUTER_EDGE or ARC_INNER_EDGE
    if layout.side ~= "player" then return edge end
    for key in pairs(trims) do
        local spec = TRIMS[key] or { ARC_R, ARC_R } -- (shield, soul: not beside the arc)
        if layout.outside and spec[1] > ARC_R then
            edge = math.max(edge, spec[2] + T.RAIL_PAD)
        elseif not layout.outside and spec[2] < ARC_R then
            edge = math.min(edge, spec[1] - T.RAIL_PAD)
        end
    end
    return edge
end

-- Five-second rule / ticks ------------------------------------------------
local fsrStart, lastSpend, lastTick, pendingTick = -100, -100, nil, nil
local tickColor

local function PowerToken()
    local _, token = UnitPowerType("player")
    if Secret(token) then return nil end
    return token
end

-- Does the spell cost `powerType`? (Your own casts' costs are readable.)
local function Costs(spellID, powerType)
    if type(spellID) ~= "number" or Secret(spellID) or not (C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local ok, result = pcall(function()
        for _, cost in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
            if cost.type == powerType and ((cost.cost or 0) > 0 or (cost.costPercent or 0) > 0) then return true end
        end
        return false
    end)
    return ok and result
end

local shieldMax           -- your shield's size when it went up (may be secret)
local captureUntil = 0    -- a shield of yours just went up: absorb changes until then set its size
local shieldSpell = { spell = T.SHIELD_SPELL }
-- Weakened Soul by your own clock (combat hides the aura from the HUD): your
-- shield cast followed by an absorb change on you means it landed on you, and
-- Weakened Soul with it.
local soulCastAt          -- your shield cast, waiting for an absorb change on you
local soulStart           -- Weakened Soul on you since (your clock)
local soulDuration = T.SOUL_DURATION
local lastAbsorbChange = -100

function OnSpent(spellID)
    local now = GetTime()
    -- Your Power Word: Shield (any rank, by name): its size comes next.
    if type(spellID) == "number" and not Secret(spellID) and trims.shield then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if shieldSpell.name == nil then
            local okShield, shieldName = pcall(C_Spell.GetSpellName, shieldSpell.spell)
            shieldSpell.name = (okShield and type(shieldName) == "string") and shieldName or false
        end
        if ok and type(name) == "string" and not Secret(name) and name == shieldSpell.name then
            captureUntil = now + T.SHIELD_CAPTURE
            -- (the absorb change may come first)
            if now - lastAbsorbChange <= T.SHIELD_CAPTURE then soulStart = now else soulCastAt = now end
            UpdateShieldTrim()
        end
    end
    if Costs(spellID, Enum.PowerType.Mana) then
        fsrStart, lastSpend = now, now
    elseif Costs(spellID, Enum.PowerType.Energy) then
        lastSpend = now
    end
end

local function UpdateTickAlpha()
    local t = trims.tick
    if not (t and fullCurve) then return end
    local token = PowerToken()
    local powerType = token == "MANA" and Enum.PowerType.Mana or token == "ENERGY" and Enum.PowerType.Energy
    if not powerType then return end
    local ok, alpha = pcall(UnitPowerPercent, "player", powerType, false, fullCurve)
    if ok and type(alpha) ~= "nil" then pcall(t.frame.SetAlpha, t.frame, alpha) end
end

function OnPowerChanged(token)
    if token == "MANA" or token == "ENERGY" then
        -- A tick, unless a spend of yours turns up close to it (either order).
        if GetTime() - lastSpend > T.SPEND_WINDOW then pendingTick = GetTime() end
        UpdateTickAlpha()
    end
end

function UpdateTickShown()
    local t = trims.tick
    if not t then return end
    local token = PowerToken()
    t.frame:SetShown(token == "MANA" or token == "ENERGY")
    UpdateTickAlpha()
end

local function SetTickColor(color)
    if tickColor == color then return end
    tickColor = color
    trims.tick.bar:SetStatusBarColor(color[1], color[2], color[3])
end

local function UpdateTick()
    local now = GetTime()
    if pendingTick and now - pendingTick > T.SPEND_WINDOW then
        if math.abs(lastSpend - pendingTick) > T.SPEND_WINDOW then
            local token = PowerToken()
            if token == "ENERGY" or pendingTick - fsrStart >= T.FSR_TIME then lastTick = pendingTick end
        end
        pendingTick = nil
    end
    local token, bar = PowerToken(), trims.tick.bar
    if token == "MANA" and now - fsrStart < T.FSR_TIME then
        SetTickColor(T.FSR_COLOR)
        bar:SetValue(1 - (now - fsrStart) / T.FSR_TIME) -- drains to regen
    elseif (token == "MANA" or token == "ENERGY") and lastTick then
        SetTickColor(token == "MANA" and T.MANA_TICK_COLOR or T.ENERGY_TICK_COLOR)
        bar:SetValue(((now - lastTick) % T.TICK_TIME) / T.TICK_TIME) -- fills to the next tick
    else
        bar:SetValue(0)
    end
end

-- Pet, shield, Weakened Soul ------------------------------------------------
function UpdatePet()
    local t = trims.pet
    if not t then return end
    if not UnitExists("pet") then t.frame:Hide() return end
    t.frame:Show()
    local ok, value = pcall(UnitHealthPercent, "pet", true)
    if ok and type(value) ~= "nil" then SetBarValue(t.bar, value) end
    local colored = false
    if healthCurve then
        local okColor, color = pcall(UnitHealthPercent, "pet", true, healthCurve)
        colored = okColor and color and color.GetRGB and pcall(t.bar.SetStatusBarColor, t.bar, color:GetRGB())
    end
    if not colored then t.bar:SetStatusBarColor(HEALTH_GREEN:GetRGB()) end
end

-- Your absorb shields as a share of the shield's own size: full when it
-- goes up, draining as it soaks damage. The size: the amount right after
-- your Power Word: Shield (secret in combat, so kept as it is and handed to
-- the bar, never compared); out of combat (readable) also any larger amount.
-- No size known: your max health.
function UpdateShieldTrim(absorbChanged)
    local t = trims.shield
    if not t then return end
    if absorbChanged then
        lastAbsorbChange = GetTime()
        if soulCastAt and lastAbsorbChange - soulCastAt <= T.SHIELD_CAPTURE then
            soulStart, soulCastAt = soulCastAt, nil
        end
    end
    local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
    if not ok or type(amount) == "nil" then return end
    if GetTime() <= captureUntil then
        shieldMax = amount
    elseif not Secret(amount) then
        if amount <= 0 then
            shieldMax = nil
        elseif shieldMax == nil or Secret(shieldMax) or amount > shieldMax then
            shieldMax = amount
        end
    end
    local max = shieldMax
    if max == nil then
        local okMax, health = pcall(UnitHealthMax, "player")
        max = okMax and health or 1
    end
    pcall(t.bar.SetMinMaxValues, t.bar, 0, max)
    pcall(SetBarValue, t.bar, amount)
    pcall(t.track.SetValue, t.track, amount) -- (0..1: full with any shield, empty without)
    pcall(t.back.SetValue, t.back, amount)
    if absorbChanged then ShieldBurst(amount) end
end

-- Weakened Soul: found by name (every rank), else by ID. Lookups return
-- nothing for an aura the client keeps secret; a shown one then runs on
-- while the client still has a duration for its instance.
local soul = { spell = T.SOUL_SPELL, filter = "HARMFUL" }

local function SpellName(t)
    if t.name == nil then
        local ok, name = pcall(C_Spell.GetSpellName, t.spell)
        t.name = (ok and type(name) == "string") and name or false
    end
    return t.name
end

local function FindAura(t)
    local aura
    if SpellName(t) and C_UnitAuras.GetAuraDataBySpellName then
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", t.name, t.filter)
        if ok then aura = a end
    end
    if not aura and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, t.spell)
        if ok then aura = a end
    end
    return aura
end

local function ShowSoul(id)
    local t = trims.soul
    local ok, duration = pcall(C_UnitAuras.GetAuraDuration, "player", id)
    if not (ok and duration) then return false end
    soul.id = id
    soulStart, soulCastAt = nil, nil -- (the aura itself wins over your clock)
    t.clockStart = nil
    t.cooldown:SetCooldownFromDurationObject(duration)
    return true
end

local function HideSoul()
    soul.id = nil
    local t = trims.soul
    t.clockStart = nil
    if not soulStart then
        t.cooldown:Clear()
        t.Ready()
    end -- (your clock still running: it takes over)
end

-- Whether the client hides auras from the HUD right now (in combat).
local function AurasHidden()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
    if not ok or Secret(hidden) then return true end
    return hidden and true or false
end

-- On UNIT_AURA. (Its update info's lists are secret in combat: not read.)
-- Not found: gone, or only hidden from the lookup; the shown instance stays
-- while the client still has a duration for it (refreshed: re-read).
function UpdateSoul()
    if not trims.soul then return end
    local aura = FindAura(soul)
    local id = aura and aura.auraInstanceID
    if id ~= nil and not Secret(id) and ShowSoul(id) then
        soulStart = nil -- the aura itself wins
        if type(aura.duration) == "number" and not Secret(aura.duration) and aura.duration > 0 then
            soulDuration = aura.duration -- (learnt for your clock)
        end
        return
    end
    -- Not readable: gone, or (in combat) only hidden. Hidden: its sweep runs
    -- on to its own end.
    if soul.id and not ShowSoul(soul.id) and not AurasHidden() then HideSoul() end
end

-- Weakened Soul by your clock, while the aura itself isn't shown.
-- While Weakened Soul is on you, your shield can't go up: its cooldown
-- pulse (the Cooldown Manager's) is held back. The shield's icon, compared
-- by texture (readable; anything else: not held back).
function M.LockedOut(texture)
    if not (trims.soul and (soul.id or soulStart)) then return false end
    local ok, shieldIcon = pcall(C_Spell.GetSpellTexture, T.SHIELD_SPELL)
    if not ok or shieldIcon == nil or Secret(texture) or Secret(shieldIcon) then return false end
    return texture == shieldIcon
end

local function UpdateSoulClock()
    local t = trims.soul
    if not t then return end
    if t.finished then -- (its sweep ended: Weakened Soul is over)
        t.finished = false
        soul.id, soulStart, soulCastAt, t.clockStart = nil, nil, nil, nil
    end
    if soulStart and GetTime() >= soulStart + soulDuration then soulStart = nil end
    if soulStart and not soul.id and t.clockStart ~= soulStart then
        t.clockStart = soulStart
        t.cooldown:SetCooldown(soulStart, soulDuration)
    end
end

function UpdateTrims()
    if trims.tick and trims.tick.frame:IsShown() then UpdateTick() end
    UpdateSoulClock()
end

-- Druid mana while shapeshifted ----------------------------------------------
function UpdateFormMana()
    local t = trims.mana
    if not t then return end
    local token = PowerToken()
    if token == nil or token == "MANA" then t.frame:Hide() return end
    t.frame:Show()
    local ok, value = pcall(UnitPowerPercent, "player", Enum.PowerType.Mana, false)
    if ok and type(value) ~= "nil" then SetBarValue(t.bar, value) end
end

-- Combo points -----------------------------------------------------------------
-- Gems on the target's arc. The count may be secret: each gem's fill is a
-- bar over (i - 1)..i, so it's full from i points on and empty below.
local pips = {}

function BuildCombo()
    local _, class = UnitClass("player")
    if class ~= "ROGUE" and class ~= "DRUID" then return end
    local s = sides.target
    for i = 1, T.PIP_COUNT do
        local angle = math.rad(T.PIP_FIRST + (i - 1) * T.PIP_STEP)
        local x = SIDE_W - (ARC_CX - T.PIP_R * math.cos(angle)) * SCALE
        local y = (ARC_CY + T.PIP_R * math.sin(angle)) * SCALE
        local frame = CreateFrame("Frame", nil, s.frame)
        frame:SetSize(T.PIP_SIZE, T.PIP_SIZE)
        frame:SetPoint("CENTER", s.frame, "TOPLEFT", x, -y)
        frame:SetFrameLevel(s.health:GetFrameLevel() + 2)
        local back = frame:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetTexture(MEDIA .. "ArcPipBack")
        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetAllPoints()
        bar:SetStatusBarTexture(MEDIA .. "ArcPipFill")
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(i - 1)
        local color = i == T.PIP_COUNT and T.PIP_LAST_COLOR or T.PIP_COLOR
        bar:SetStatusBarColor(color[1], color[2], color[3])
        frame:Hide()
        pips[i] = { frame = frame, bar = bar }
    end
end

function UpdateCombo()
    if #pips == 0 then return end
    local _, class = UnitClass("player")
    local shown = class == "ROGUE" or PowerToken() == "ENERGY" -- (druids: in cat form)
    for _, pip in ipairs(pips) do pip.frame:SetShown(shown) end
    if not shown then return end
    local ok, points = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok or type(points) == "nil" then
        ok, points = pcall(GetComboPoints, "player", "target")
    end
    if not ok or type(points) == "nil" then return end
    for _, pip in ipairs(pips) do pcall(pip.bar.SetValue, pip.bar, points) end
end

-- Target of target -----------------------------------------------------------
local tot

function BuildToT()
    local s = sides.target
    local frame = CreateFrame("Frame", nil, s.id)
    frame:SetSize(T.TOT_W, T.TOT_FONT_SIZE + 2 + T.TOT_BAR_H)
    frame:SetPoint("RIGHT", s.id, "LEFT", -((RING_SIZE - PORTRAIT_SIZE) / 2 + T.TOT_GAP), 0)
    local name = NewText(frame, T.TOT_FONT_SIZE)
    name:SetPoint("TOPRIGHT")
    name:SetWidth(T.TOT_W)
    name:SetJustifyH("RIGHT")
    name:SetWordWrap(false)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("BOTTOMLEFT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetHeight(T.TOT_BAR_H)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    back:SetColorTexture(0, 0, 0, 0.6)
    frame:Hide()
    tot = { frame = frame, name = name, bar = bar, since = 0 }
end

function UpdateToT(elapsed)
    tot.since = tot.since + elapsed
    if tot.since < T.TOT_INTERVAL then return end
    tot.since = 0
    if not UnitExists("targettarget") then tot.frame:Hide() return end
    tot.frame:Show()
    local fullName = ns.UnitFullName("targettarget")
    if fullName then tot.name:SetText(fullName) else tot.name:SetText(UnitName("targettarget")) end
    local r, g, b = UnitRGB("targettarget")
    pcall(tot.name.SetTextColor, tot.name, r, g, b)
    pcall(tot.bar.SetStatusBarColor, tot.bar, r, g, b)
    local ok, value = pcall(UnitHealthPercent, "targettarget", true)
    if ok and type(value) ~= "nil" then tot.bar:SetValue(value) end
end

-- /kk archud shield: what the client lets the HUD see of your shields.
function M:OnSlash(args)
    if (args or ""):lower() ~= "shield" then
        ns:Print("/kk archud shield: what the HUD can see of your shields")
        return
    end
    local function Show(v)
        if Secret(v) then return "(secret)" end
        return tostring(v)
    end
    ns:Print("auras secret now: " .. Show(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()))
    local secrecy = C_Secrets and C_Secrets.GetSpellAuraSecrecy and C_Secrets.GetSpellAuraSecrecy(soul.spell)
    local aura = FindAura(soul)
    ns:Print(("%d %s: secrecy %s, found %s, instance %s, tracked %s"):format(soul.spell, tostring(SpellName(soul)),
        Show(secrecy), aura and "yes" or "no", aura and Show(aura.auraInstanceID) or "-", Show(soul.id)))
    local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
    ns:Print("absorbs: " .. (ok and Show(amount) or "error"))
    local burst = trims.shield and trims.shield.burst
    if burst then
        local gate = burst.gates[1]
        local ok, width = pcall(gate.clip.GetWidth, gate.clip)
        ns:Print(("break flash: %s, its window %s of %s wide"):format(burst.gated and "gated" or "out of combat only",
            ok and Show(width) or "error", Show(gate.bar:GetWidth())))
    end
end
end -- trims block

---------------------------------------------------------------------------
-- Cooldown Manager on the curves
---------------------------------------------------------------------------
local hookedItems = setmetatable({}, { __mode = "k" })
local queued = {}

-- The viewer's shown icons in their order (Blizzard's list: shown ones,
-- sorted by layout index).
local function ShownItems(viewer)
    local items = viewer:GetItemFrames()
    return type(items) == "table" and items or {}
end

-- All its icons, hidden ones too (to hook their show / hide).
local function AllItems(viewer)
    local all = {}
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child.layoutIndex then all[#all + 1] = child end
    end
    return all
end

-- An icon centred on (x, y) of `anchor`'s top left, in the anchor's units.
local function PlaceItem(item, anchor, x, y)
    local k = anchor:GetEffectiveScale() / item:GetEffectiveScale()
    item:ClearAllPoints()
    item:SetPoint("CENTER", anchor, "TOPLEFT", x * k, y * k)
end

local function ItemSize(item, anchor)
    return item:GetWidth() * item:GetEffectiveScale() / anchor:GetEffectiveScale()
end

-- Edit Mode's icon scale for the viewer's icons.
local function EditScale(viewer)
    return type(viewer.iconScale) == "number" and viewer.iconScale or 1
end

-- The largest icon size (UI units) for `n` icons in a row on a rail along
-- the arc edge at radius `edge` (`sign` -1 inside, +1 outside), their centres
-- spread over `span` radians.
local function FitSize(n, edge, sign, span)
    if n < 2 then return math.huge end
    -- (n - 1) * (size + gap) = (edge + sign * (size / 2 + RAIL_GAP)) * span
    local size = ((edge + sign * RAIL_GAP) * span - (n - 1) * CDM_GAP) / ((n - 1) - sign * span / 2)
    return math.max(8, size)
end

local function ArrangeRail(viewer, layout)
    local s = sides[layout.side]
    local items = ShownItems(viewer)
    if #items == 0 or not s then return end
    local left = layout.side == "player"
    local sign = layout.outside and 1 or -1
    local edge = M.RailEdge(layout) * SCALE
    local start = ARC_HALF * (layout.outside and OUTSIDE_RAIL_START or RAIL_START)
    -- Shrink the icons to fit the row (Edit Mode's size at most).
    local editScale = EditScale(viewer)
    local natural = ItemSize(items[1], s.frame) / items[1]:GetScale() * editScale
    local fit = math.min(1, FitSize(#items, edge, sign, ARC_HALF * RAIL_END - start) / natural)
    for _, item in ipairs(items) do
        if math.abs(item:GetScale() - editScale * fit) > 0.001 then item:SetScale(editScale * fit) end
    end
    local size = natural * fit
    local r = edge + sign * (size / 2 + RAIL_GAP)
    local angle = start
    for _, item in ipairs(items) do
        local x = ARC_CX * SCALE - r * math.cos(angle)
        if not left then x = SIDE_W - x end
        PlaceItem(item, s.frame, x, -(ARC_CY * SCALE + r * math.sin(angle)))
        angle = angle + (size + CDM_GAP) / r
    end
end

-- Edit Mode: Blizzard's own icon size back.
local function RestoreScale(viewer)
    local editScale = EditScale(viewer)
    for _, item in ipairs(ShownItems(viewer)) do
        if item:GetScale() ~= editScale then item:SetScale(editScale) end
    end
end

local function Arrange(layout)
    local viewer = _G[layout.viewer]
    if not viewer or not viewer.GetItemFrames then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then RestoreScale(viewer) return end
    -- Icons show and hide on their own (procs): re-place then too.
    for _, item in ipairs(AllItems(viewer)) do
        if not hookedItems[item] then
            hookedItems[item] = true
            local function Again() M.QueueArrange(layout) end
            item:HookScript("OnShow", Again)
            item:HookScript("OnHide", Again)
            if layout.flash then M.AddReadyFlash(item) end
        end
    end
    ArrangeRail(viewer, layout)
end

-- The cooldown pulse: the icon big above your character, in the action bar
-- icon look with a gold glow; queued when several come back at once.
do
    local pulse, playing
    local queue = {}

    local function Build()
        local frame = CreateFrame("Frame", nil, sides.player.frame)
        frame:SetSize(T.PULSE_SIZE, T.PULSE_SIZE)
        frame:SetPoint("CENTER", hud, "CENTER", 0, T.PULSE_Y)
        frame:SetFrameLevel(sides.player.id:GetFrameLevel() + 10)
        local glow = frame:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("CENTER")
        glow:SetSize(T.PULSE_SIZE * 2.35, T.PULSE_SIZE * 2.35)
        glow:SetTexture(MEDIA .. "ArcGlow")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(T.READY_COLOR_CD[1], T.READY_COLOR_CD[2], T.READY_COLOR_CD[3])
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        local mask = frame:CreateMaskTexture()
        mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
        mask:SetPoint("CENTER", icon, "CENTER")
        mask:SetSize(T.PULSE_SIZE * 1.5, T.PULSE_SIZE * 1.5)
        icon:AddMaskTexture(mask)
        local border = frame:CreateTexture(nil, "OVERLAY")
        border:SetAtlas("UI-HUD-ActionBar-IconFrame")
        border:SetPoint("TOPLEFT", icon, "TOPLEFT")
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", T.PULSE_SIZE / 45, 0)
        frame:SetAlpha(0)
        local group = frame:CreateAnimationGroup()
        local function Anim(kind, order, duration, smoothing)
            local a = group:CreateAnimation(kind)
            a:SetOrder(order)
            a:SetDuration(duration)
            if smoothing then a:SetSmoothing(smoothing) end
            return a
        end
        local inAlpha = Anim("Alpha", 1, T.PULSE_IN, "OUT")
        inAlpha:SetFromAlpha(0)
        inAlpha:SetToAlpha(1)
        local inScale = Anim("Scale", 1, T.PULSE_IN, "OUT")
        inScale:SetScaleFrom(0.5, 0.5)
        inScale:SetScaleTo(1, 1)
        local hold = Anim("Alpha", 2, T.PULSE_HOLD)
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        local outAlpha = Anim("Alpha", 3, T.PULSE_OUT, "IN")
        outAlpha:SetFromAlpha(1)
        outAlpha:SetToAlpha(0)
        local outScale = Anim("Scale", 3, T.PULSE_OUT, "IN")
        outScale:SetScaleFrom(1, 1)
        outScale:SetScaleTo(1.35, 1.35)
        pulse = { frame = frame, icon = icon, glow = glow, group = group }
        group:SetScript("OnFinished", function()
            playing = false
            C_Timer.After(T.PULSE_GAP, M.NextPulse)
        end)
    end

    function M.NextPulse()
        if playing then return end
        local entry = table.remove(queue, 1)
        if entry == nil then return end
        if not pulse then Build() end
        if not pcall(pulse.icon.SetTexture, pulse.icon, entry.texture) then return M.NextPulse() end
        local color = entry.color or T.READY_COLOR_CD
        pulse.glow:SetVertexColor(color[1], color[2], color[3])
        playing = true
        pulse.group:Stop()
        pulse.group:Play()
    end

    -- `color`: the glow's (default: the cooldowns' gold).
    function M.QueuePulse(texture, color)
        queue[#queue + 1] = { texture = texture, color = color }
        M.NextPulse()
    end
end

-- A cooldown icon coming off cooldown: a gold ring swelling off it. Timed by
-- its cooldown swipe (shown at the start, done at the end); only cooldowns
-- of READY_MIN seconds or more (not the global cooldown).
function M.AddReadyFlash(item)
    local cd = item.Cooldown or (item.GetCooldownFrame and item:GetCooldownFrame())
    if not cd then return end
    local frame = CreateFrame("Frame", nil, item)
    frame:SetAllPoints()
    frame:SetFrameLevel(item:GetFrameLevel() + 10)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "ArcGlow")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(T.READY_COLOR_CD[1], T.READY_COLOR_CD[2], T.READY_COLOR_CD[3])
    frame:SetAlpha(0)
    local group = frame:CreateAnimationGroup()
    local grow = group:CreateAnimation("Scale")
    grow:SetScaleFrom(T.READY_FROM, T.READY_FROM)
    grow:SetScaleTo(T.READY_TO, T.READY_TO)
    grow:SetOrigin("CENTER", 0, 0)
    grow:SetDuration(T.READY_TIME)
    grow:SetSmoothing("OUT")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(T.READY_TIME)
    fade:SetSmoothing("IN")
    local startedAt
    cd:HookScript("OnShow", function() startedAt = GetTime() end)
    cd:HookScript("OnCooldownDone", function()
        if startedAt and GetTime() - startedAt >= T.READY_MIN then
            group:Stop()
            group:Play()
            local icon = item.Icon or (item.GetIconTexture and item:GetIconTexture())
            if icon and icon.GetTexture then
                local ok, texture = pcall(icon.GetTexture, icon)
                if ok and texture ~= nil and not (M.LockedOut and M.LockedOut(texture)) then
                    M.QueuePulse(texture)
                end
            end
        end
        startedAt = nil
    end)
end

function M.QueueArrange(layout)
    if queued[layout] then return end
    queued[layout] = true
    C_Timer.After(0, function()
        queued[layout] = nil
        ns.safecall(Arrange, layout)
    end)
end

-- The viewers' alpha: Blizzard's own (kept from its SetAlpha calls) times
-- their HUD side's.
local viewerBase, viewerShown = {}, {}
local settingViewerAlpha = false

local function ApplyViewerAlpha(viewer, sideAlpha)
    if viewerShown[viewer] == sideAlpha then return end
    viewerShown[viewer] = sideAlpha
    settingViewerAlpha = true
    viewer:SetAlpha((viewerBase[viewer] or 1) * sideAlpha)
    settingViewerAlpha = false
end

function M.UpdateViewerAlphas()
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    for _, layout in ipairs(CDM_LAYOUTS) do
        local viewer = _G[layout.viewer]
        local side = sides[layout.side]
        if viewer and side then ApplyViewerAlpha(viewer, editing and 1 or side.alpha) end
    end
end

local function HookCooldownManager()
    for _, layout in ipairs(CDM_LAYOUTS) do
        local viewer = _G[layout.viewer]
        if viewer then
            viewerBase[viewer] = viewer:GetAlpha()
            hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
                if settingViewerAlpha then return end
                viewerBase[self] = alpha
                viewerShown[self] = nil -- re-apply ours on the next update
            end)
        end
        if viewer and type(viewer.Layout) == "function" then
            hooksecurefunc(viewer, "Layout", function() M.QueueArrange(layout) end)
            M.QueueArrange(layout)
        end
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", function()
            for _, layout in ipairs(CDM_LAYOUTS) do M.QueueArrange(layout) end
        end)
    end
end

---------------------------------------------------------------------------
-- Visibility (combat or a hostile target; Edit Mode; fades)
---------------------------------------------------------------------------
local function Editing()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

local function HostileTarget()
    if not UnitExists("target") then return false end
    local ok, hostile = pcall(UnitCanAttack, "player", "target")
    return ok and not Secret(hostile) and hostile or false
end

local function UpdateVisibility()
    local editing = Editing()
    local active = InCombatLockdown() or UnitAffectingCombat("player") or HostileTarget()
    sides.player.wanted = (active or editing) and 1 or 0
    sides.target.wanted = ((active and UnitExists("target")) or editing) and 1 or 0
end

local function Fade(item, elapsed)
    if item.holdUntil and GetTime() >= item.holdUntil then
        item.holdUntil = nil
        item.wanted = 0
    end
    if item.alpha == item.wanted then return end
    local step = elapsed / FADE_TIME
    item.alpha = item.wanted > item.alpha and math.min(item.wanted, item.alpha + step)
        or math.max(item.wanted, item.alpha - step)
    item.frame:SetAlpha(item.alpha)
    if item.pop then
        local rest = 1 - item.alpha
        item.frame:SetPoint("CENTER", item.anchor, "CENTER", 0, -POP_DIST * rest * rest)
    end
end

function M:OnEnable()
    Build()
    BuildTargetCast()
    BuildTrims()
    BuildToT()
    hud:SetScript("OnUpdate", function(_, elapsed)
        UpdateTrims(elapsed)
        UpdateToT(elapsed)
        Fade(sides.player, elapsed)
        Fade(sides.target, elapsed)
        -- The frames step back as the arcs come (fully back in Edit Mode).
        local editing = Editing()
        if editing then PlaceSides() end -- (frames being dragged)
        StepFrame("player", editing and 1 or 1 - sides.player.alpha)
        StepFrame("target", editing and 1 or 1 - sides.target.alpha)
        Fade(cast, elapsed)
        UpdateCastTimer(elapsed)
        Fade(tcast, elapsed)
        UpdateTargetCastTimer(elapsed)
        if M.db.cooldowns then M.UpdateViewerAlphas() end
    end)
    -- Blizzard's player cast bar out of sight (the cast arc replaces it).
    HideCastBar(PlayerCastingBarFrame)
    local spellbar = TargetFrame and TargetFrame.spellbar
    if spellbar then
        for _, group in ipairs({ spellbar:GetAnimationGroups() }) do
            for _, anim in ipairs({ group:GetAnimations() }) do
                if anim:GetObjectType() == "Alpha" then
                    castAnims[#castAnims + 1] = { anim, anim:GetFromAlpha(), anim:GetToAlpha() }
                end
            end
        end
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", UpdateVisibility)
        EditModeManagerFrame:HookScript("OnHide", function()
            UpdateVisibility()
            PlaceSides()
        end)
    end
    -- The frames moving (Edit Mode layouts, UI scale): the arcs follow.
    local function Replace() C_Timer.After(0, function() ns:OutOfCombat(PlaceSides) end) end
    for _, name in pairs(UNIT_FRAMES) do
        if _G[name] then hooksecurefunc(_G[name], "SetPoint", Replace) end
    end
    for _, event in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        ns:On(event, Replace)
    end
    if M.db.cooldowns then HookCooldownManager() end
    ns:OutOfCombat(function()
        BuildClicks("player", "[combat] show; [@target,harm] show; hide")
        BuildClicks("target", "[@target,noexists] hide; [combat] show; [@target,harm] show; hide")
        PlaceSides()
        clicksBuilt = true
    end)

    local function OnHealth(_, unit)
        if unit == "player" or unit == "target" then UpdateHealth(unit) end
        if unit == "pet" then UpdatePet() end
        if unit == "player" then UpdateShieldTrim() end
    end
    local function OnPower(_, unit) if unit == "player" or unit == "target" then UpdatePower(unit) end end
    ns:On("UNIT_HEALTH", OnHealth)
    ns:On("UNIT_MAXHEALTH", OnHealth)
    ns:On("UNIT_POWER_UPDATE", OnPower)
    ns:On("UNIT_MAXPOWER", OnPower)
    ns:On("UNIT_DISPLAYPOWER", OnPower)
    ns:On("PLAYER_TARGET_CHANGED", function()
        UpdateUnit("target")
        UpdateIdentity("target")
        CheckTargetCast()
        UpdateCombo()
        UpdateVisibility()
    end)
    ns:On("PLAYER_REGEN_DISABLED", UpdateVisibility)
    ns:On("PLAYER_REGEN_ENABLED", UpdateVisibility)
    -- (a target turning hostile or friendly)
    ns:On("UNIT_FLAGS", function(_, unit) if unit == "player" or unit == "target" then UpdateVisibility() end end)
    ns:On("UNIT_FACTION", function(_, unit) if unit == "target" then UpdateVisibility() end end)
    local function OnIdentity(_, unit) if unit == "player" or unit == "target" then UpdateIdentity(unit) end end
    for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED",
        "UNIT_FACTION" }) do
        ns:On(event, OnIdentity)
    end
    ns:On("PLAYER_FLAGS_CHANGED", OnIdentity)
    ns:On("PLAYER_LEVEL_UP", function() UpdateIdentity("player") end)
    ns:On("PLAYER_UPDATE_RESTING", function() UpdateIdentity("player") end)
    ns:On("UNIT_AURA", function(_, unit) if unit == "player" then UpdateSoul() end end)
    ns:On("UNIT_ABSORB_AMOUNT_CHANGED", function(_, unit) if unit == "player" then UpdateShieldTrim(true) end end)
    ns:On("UNIT_PET", function(_, unit) if unit == "player" then UpdatePet() end end)
    ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID) if unit == "player" then OnSpent(spellID) end end)
    ns:On("UNIT_POWER_FREQUENT", function(_, unit, token)
        if unit ~= "player" then return end
        OnPowerChanged(token)
        if token == "MANA" then UpdateFormMana() end
        if token == "COMBO_POINTS" then UpdateCombo() end
    end)
    ns:On("UNIT_DISPLAYPOWER", function(_, unit)
        if unit ~= "player" then return end
        UpdateTickShown()
        UpdateFormMana()
        UpdateCombo()
    end)
    ns:On("UNIT_MAXPOWER", function(_, unit) if unit == "player" then UpdateCombo() end end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        UpdateSoul()
        UpdatePet()
        UpdateShieldTrim()
        UpdateTickShown()
        UpdateFormMana()
        UpdateCombo()
        Replace()
        UpdateIdentity("player")
        UpdateIdentity("target")
        UpdateUnit("player")
        UpdateUnit("target")
        UpdateVisibility()
    end)

    -- (fn gets the event's cast GUID and spell ID)
    local function IfPlayer(fn) return function(_, unit, ...) if unit == "player" then fn(...) end end end
    ns:On("UNIT_SPELLCAST_START", IfPlayer(function(guid, id) StartCast(false, guid, id) end))
    ns:On("UNIT_SPELLCAST_DELAYED", IfPlayer(function(guid, id) StartCast(false, guid, id) end))
    ns:On("UNIT_SPELLCAST_CHANNEL_START", IfPlayer(function(guid, id) StartCast(true, guid, id) end))
    ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", IfPlayer(function(guid, id) StartCast(true, guid, id) end))
    for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        ns:On(event, IfPlayer(StopCast))
    end
    ns:On("UNIT_SPELLCAST_INTERRUPTED", IfPlayer(function(guid, id)
        ShowInterrupted(cast, INTERRUPTED or "Interrupted", guid, id)
    end))
    ns:On("UNIT_SPELLCAST_FAILED", IfPlayer(function(guid, id) ShowInterrupted(cast, FAILED or "Failed", guid, id) end))
    -- Your target's casts.
    local function IfTarget(fn) return function(_, unit, ...) if unit == "target" then fn(...) end end end
    ns:On("UNIT_SPELLCAST_START", IfTarget(function(guid, id) StartTargetCast(false, guid, id) end))
    ns:On("UNIT_SPELLCAST_DELAYED", IfTarget(function(guid, id) StartTargetCast(false, guid, id) end))
    ns:On("UNIT_SPELLCAST_CHANNEL_START", IfTarget(function(guid, id) StartTargetCast(true, guid, id) end))
    ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", IfTarget(function(guid, id) StartTargetCast(true, guid, id) end))
    ns:On("UNIT_SPELLCAST_INTERRUPTIBLE", IfTarget(CheckTargetCast))
    ns:On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", IfTarget(CheckTargetCast))
    for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        ns:On(event, IfTarget(StopTargetCast))
    end
    ns:On("UNIT_SPELLCAST_INTERRUPTED", IfTarget(function(guid, id)
        ShowInterrupted(tcast, INTERRUPTED or "Interrupted", guid, id)
    end))
    ns:On("UNIT_SPELLCAST_FAILED", IfTarget(function(guid, id) ShowInterrupted(tcast, FAILED or "Failed", guid, id) end))

    UpdateIdentity("player")
    UpdateIdentity("target")
    UpdateUnit("player")
    UpdateUnit("target")
    UpdateVisibility()
end
