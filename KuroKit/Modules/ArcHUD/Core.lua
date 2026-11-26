-- Arc HUD (ArcHUD / IceHUD inspired): curved bars around your character.
-- This file: the module, shared constants and helpers, the two side arcs
-- (values, portraits, names, levels), clicks, Blizzard's frames stepping
-- back, visibility and fades. The rest, each a part (A.AddPart) built,
-- updated and wired up from here: Cast.lua (your cast arc, your target's
-- cast bar), Trims.lua (class trims, shields, lockouts, target of target),
-- Cooldowns.lua (the Cooldown Manager on the curves, cooldown pulses),
-- Swing.lua (swing timer arcs), Threat.lua (the target arc's threat tint),
-- Debuffs.lua (your target's auras beside its arc, new debuffs on you).
--   left    your health (outer arc) and power (inner arc), bottom to top
--   right   your target's health (outer) and power (inner)
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
-- centred on your character. Two ways (option "popOut"):
--   pop out (default)  in combat or with a target you can attack, the arcs
--                      pop up (fade in, sliding up) and the frames step back
--                      (fade out, their target buffs / debuffs and your
--                      class resources stay); otherwise the frames are back
--                      (Frame Fading still fades yours)
--   always             the arcs replace the frames (which stay stepped back
--                      and take no clicks): yours shows in combat, with a
--                      target and while your health or mana isn't full
--                      (as Frame Fading does for the player frame), your
--                      target's with a target; your class resources step
--                      back with your frame
-- Edit Mode shows the frames and the arcs either way.
-- Clicks: the portraits and the arcs are unit buttons while they show (left:
-- target, right: the unit menu, the game's click casting as on any unit
-- frame); hovering shows the unit's tooltip.
--
-- How: on this client health and power are secret to addons, so nothing is
-- computed here. Each arc is a status bar whose fill is a curved image in the
-- cast bar's style (tools/make_arcs.py; a straight texture masked to the arc
-- shows its sheen as straight lines across the curve): the client crops it to
-- the value, so it fills along the curve; status bars accept secret values.
-- Percentages:
-- UnitHealthPercent / UnitPowerPercent scaled to 100, written with
-- SetFormattedText; your health colour: a colour curve the client evaluates.
-- Clicks: SecureUnitButtonTemplate buttons (type1 target, type2 togglemenu;
-- its OnClick runs the game's click bindings), a row of small ones along
-- each arc (the arcs' inside stays free for clicking the world), shown by a
-- secure state driver with the arcs' own conditions ([combat], [harm]).
-- Created at login, out of combat. They hang off a fixed anchor per side, not
-- the sliding arc (a frame protected frames hang off can't move in combat).
-- Blizzard's frames step back through their parts' alpha (Blizzard's own
-- alpha times ours, kept through a SetAlpha hook), never Show / Hide.
-- Files: one shared table (ns.ArcHUD, `A` in each file) carries the
-- constants and helpers the parts use; each file takes local copies of what
-- it needs at load (this file loads first).
-- Cost: a SetValue per health / power change; nothing per frame except the
-- short alpha fades.
local _, ns = ...

local M = ns:NewModule("ArcHUD", {
    title = "Arc HUD",
    group = "Interface",
    desc = "Curved health and power bars (you left, your target right) with portraits, names and levels, a cast "
        .. "arc below your character and swing timer arcs. The arcs line up with the player and target frames' outer "
        .. "edges (move those in Edit Mode); click them as you would those frames. Replaces the player cast bar and "
        .. "the swing timer bars.",
    defaults = { cooldowns = true, popOut = true },
    options = {
        { type = "checkbox", key = "popOut", name = "Pop out over the unit frames", reload = true,
          tooltip = "On: the arcs show in combat or with a target you can attack, popping up over the player and "
              .. "target frames, which step back meanwhile. Off: the arcs replace the frames, which stay hidden: "
              .. "yours shows in combat, with a target and while your health or mana isn't full, your target's "
              .. "with a target. Edit Mode shows the frames either way: move them to move the arcs." },
        { type = "checkbox", key = "cooldowns", name = "Cooldown Manager on the HUD", reload = true,
          tooltip = "The Cooldown Manager's icons along the HUD's curves (Essential outside your arc, tracked buffs "
              .. "inside it, Utility inside your target's), fading with the HUD, and the Essential cooldowns' flash "
              .. "and big icon pulse above your character as they come off cooldown. Off: the Cooldown Manager "
              .. "stays where Edit Mode puts it." },
    },
})

-- The parts' shared table (see the top).
local A = { M = M, parts = {} }
ns.ArcHUD = A

-- A part: { Build(), Enable() (events), Update(elapsed) (per frame) }, each
-- optional; built in file order after the side arcs.
function A.AddPart(part) A.parts[#A.parts + 1] = part end

local MEDIA = "Interface\\AddOns\\KuroKit\\Media\\"
local SCALE = 0.5            -- texture pixels -> UI units
local SIDE_W, SIDE_H = 256 * SCALE, 512 * SCALE
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
-- The Cooldown Manager rails' arc edges (texture px; Cooldowns.lua): just
-- inside the arcs' inner edge, just outside their outer edge (rings 347 to
-- 400, outline 8).
local ARC_INNER_EDGE, ARC_OUTER_EDGE = 339, 408
local T = {                    -- (shared with the parts as A.T)
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
    -- Your pet low: its arc pulsing red below this share of its health (the
    -- share may be secret: a clipping window gates it, see NewGate).
    PET_LOW = 0.3, PET_LOW_COLOR = { 1, 0.15, 0.1 }, PET_LOW_PULSE = 0.45,
    -- Your target's cast interrupted: a ring bursting round its portrait.
    KICK_COLOR = { 1, 0.9, 0.55 }, KICK_SIZE = 79, KICK_SCALE = 2.2,
    -- Your casts that put an absorb shield on you (rank 1's ID; found by
    -- name: every rank; your pet's casts count too): they set the shield
    -- arc's full size. Any other absorb shows against your max health.
    SHIELD_CASTS = {
        PRIEST = { 17 },                     -- Power Word: Shield
        MAGE = { 11426, 1463, 6143, 543 },   -- Ice Barrier, Mana Shield, Frost Ward, Fire Ward
        WARLOCK = { 6229, 7812 },            -- Shadow Ward, Sacrifice (the Voidwalker's)
    },
    -- Lockouts: a debuff on you after some of your casts, until which those
    -- can't go on you again. Countdown on your portrait, a blue ring and its
    -- icon when it ends; the blocked spells' cooldown pulses held back
    -- meanwhile. In combat (the aura hidden) timed from your cast: `absorb`
    -- once the shield lands on you (an absorb change), `self` ones only when
    -- cast on yourself, the others at once.
    LOCKOUTS = {
        PRIEST = { spell = 6788, duration = 15, triggers = { 17 }, absorb = true }, -- Weakened Soul
        PALADIN = { spell = 25771, duration = 60, triggers = { 642, 498, 1022 },    -- Forbearance: Divine Shield,
            self = { [1022] = true } },                                             -- Protection, Blessing of Protection
    },
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
    SHIELD_CAPTURE = 0.5,      -- seconds after your shield cast that absorb changes set its size
    LOCKOUT_GRACE = 1.5,       -- seconds after your clock starts a lockout that a new debuff on you may be it
    -- Your shield under this share of its size: its arc red and flashing
    -- (sharp: fully red from SHIELD_LOW - SHIELD_LOW_SHARP down; see Trims.lua).
    SHIELD_LOW = 1 / 3, SHIELD_LOW_SHARP = 0.02, SHIELD_LOW_COLOR = { 1, 0.2, 0.12 },
    SHIELD_LOW_PULSE = 0.3, SHIELD_LOW_DIM = 0.35,
    -- Target of target beside the target's portrait (inward).
    TOT_W = 90, TOT_BAR_H = 4, TOT_FONT_SIZE = 11, TOT_GAP = 6,
    TOT_INTERVAL = 0.2,
}
local HEALTH_FONT_SIZE = 16  -- health value / percentage (read at a glance: execute range)
local POWER_FONT_SIZE = 12
local NAME_FONT_SIZE = 13
local CENTER_Y = -20         -- the HUD's centre (the cast arc's), from the screen centre (your character)
local TEXT_X = 0.45          -- texts: under the arcs' lower tips, right (left side) / left (right side)
                             -- edge this far into the arc frame (the tip's middle)
local FADE_TIME = 0.25
local VISIBILITY_POLL = 0.25 -- seconds between visibility checks (always on: see OnUpdate)
local TEXT_GAP = 2
local TEXT_LIFT = 0.45       -- texts: the bar colour mixed toward white (pure blue / red are unreadable)

local HEALTH_RED = CreateColor(0.9, 0.15, 0.1)
local HEALTH_YELLOW = CreateColor(0.95, 0.8, 0.15)
local HEALTH_GREEN = CreateColor(0.25, 0.8, 0.25)

local hud
local sides = {}        -- .player, .target: { anchor, frame, health, power, healthText, powerText, portrait,
                        --   ring, name, level, faction, id, alpha, wanted }
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

-- What the parts share (constants and helpers; A.hud and A.healthCurve once
-- built).
A.MEDIA, A.SCALE, A.SIDE_W, A.SIDE_H = MEDIA, SCALE, SIDE_W, SIDE_H
A.ARC_CX, A.ARC_CY, A.ARC_R, A.ARC_HALF = ARC_CX, ARC_CY, ARC_R, ARC_HALF
A.SOCKET_ANGLE, A.PORTRAIT_SIZE, A.RING_SIZE = SOCKET_ANGLE, PORTRAIT_SIZE, RING_SIZE
A.BACK_ALPHA, A.FILL_ALPHA, A.NAME_FONT_SIZE, A.TEXT_GAP = BACK_ALPHA, FILL_ALPHA, NAME_FONT_SIZE, TEXT_GAP
A.ARC_INNER_EDGE, A.ARC_OUTER_EDGE = ARC_INNER_EDGE, ARC_OUTER_EDGE
A.HEALTH_GREEN, A.T, A.sides = HEALTH_GREEN, T, sides
A.Secret, A.SetBarValue, A.NewBar, A.NewText = Secret, SetBarValue, NewBar, NewText
A.ArcPoint, A.PortraitPoint = ArcPoint, PortraitPoint

local function Build()
    hud = CreateFrame("Frame", "KuroKitArcHUD", UIParent)
    hud:SetSize(1, 1)
    hud:SetPoint("CENTER", UIParent, "CENTER", 0, CENTER_Y)
    hud:SetFrameStrata("LOW")
    hud:EnableMouse(false)
    A.hud = hud
    NewSide("player", "Left")
    NewSide("target", "Right")
    PlaceSides()

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
    A.healthCurve = healthCurve
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

A.UnitRGB = UnitRGB

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

-- Always on (the frames stay back): your class resources step back too
-- (they'd float on their own where the frame was; combo points show on the
-- target arc). The target's auras never: they move to the target arc while
-- it shows (Debuffs.lua).
local function GatherParts()
    local popOut = M.db.popOut
    if PlayerFrame then
        local keep = { [popOut and PlayerFrame.classPowerBar or false] = true }
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
    local fighting = InCombatLockdown() or UnitAffectingCombat("player")
    local player, target
    if M.db.popOut then
        player = fighting or HostileTarget()
        target = player and UnitExists("target")
    else
        target = UnitExists("target")
        player = fighting or target or ns.PlayerSettling()
    end
    sides.player.wanted = (player or editing) and 1 or 0
    sides.target.wanted = (target or editing) and 1 or 0
end

-- Fades `item` ({ frame, alpha, wanted, holdUntil?, pop?, anchor? }) toward
-- its wanted alpha; `pop`: it slides up from below its anchor as it comes.
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

-- Always on: Blizzard's player and target frames take no clicks while they
-- are stepped back (the arcs' buttons do); Edit Mode selects them through
-- its own overlay. Out of combat only (they're protected).
local function MuteFrameClicks()
    for _, name in pairs(UNIT_FRAMES) do
        local frame = _G[name]
        if frame and frame.EnableMouse then frame:EnableMouse(false) end
    end
end

function M:OnEnable()
    Build()
    for _, part in ipairs(A.parts) do
        if part.Build then part.Build() end
    end
    local sinceVisibility = 0
    hud:SetScript("OnUpdate", function(_, elapsed)
        -- Always on: your arc stays while your health / power settles
        -- (ns.PlayerSettling, a time window): checked a few times a second.
        if not M.db.popOut then
            sinceVisibility = sinceVisibility + elapsed
            if sinceVisibility >= VISIBILITY_POLL then
                sinceVisibility = 0
                UpdateVisibility()
            end
        end
        Fade(sides.player, elapsed)
        Fade(sides.target, elapsed)
        -- The frames step back as the arcs come (always on: they stay back),
        -- fully back in Edit Mode.
        local editing = Editing()
        if editing then PlaceSides() end -- (frames being dragged)
        local popOut = M.db.popOut
        StepFrame("player", editing and 1 or popOut and 1 - sides.player.alpha or 0)
        StepFrame("target", editing and 1 or popOut and 1 - sides.target.alpha or 0)
        for _, part in ipairs(A.parts) do
            if part.Update then part.Update(elapsed) end
        end
    end)
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
    ns:OutOfCombat(function()
        if M.db.popOut then
            BuildClicks("player", "[combat] show; [@target,harm] show; hide")
            BuildClicks("target", "[@target,noexists] hide; [combat] show; [@target,harm] show; hide")
        else
            BuildClicks("player", "show")
            BuildClicks("target", "[@target,exists] show; hide")
            MuteFrameClicks()
        end
        PlaceSides()
        clicksBuilt = true
    end)

    local function OnHealth(_, unit)
        if unit == "player" or unit == "target" then UpdateHealth(unit) end
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
    ns:On("PLAYER_ENTERING_WORLD", function()
        Replace()
        UpdateIdentity("player")
        UpdateIdentity("target")
        UpdateUnit("player")
        UpdateUnit("target")
        UpdateVisibility()
    end)
    for _, part in ipairs(A.parts) do
        if part.Enable then part.Enable() end
    end

    UpdateIdentity("player")
    UpdateIdentity("target")
    UpdateUnit("player")
    UpdateUnit("target")
    UpdateVisibility()
end

A.Fade, A.Editing = Fade, Editing
