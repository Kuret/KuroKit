-- Unit frame skin: Blizzard's player, target and focus frames rebuilt from
-- Forever's own art, so they match the action bars and nameplates.
--   * portrait and bars as one block: a square portrait as tall as both bars
--     beside the health and mana bars, all in one plate framed like Forever's
--     nameplate bars and level box (black outline, bronze line, dark rim;
--     the cells split by the same lines), every line on a whole screen pixel;
--     the bronze turns gold for elites, silver for rares
--   * bars in Forever's nameplate fill: health in class colour for players,
--     reaction colour for NPCs, grey when tapped / offline; mana in its power
--     type's colour; an empty grey bar for units without a resource
--   * the level in the nameplates' level box at the block's bottom corner
--     (the skull for bosses too); no round level badge
--   * no frame ring / name banner art (the health bar shows the reaction colour)
--   * the target-of-target, pet and party frames in smaller versions of the
--     same look, the boss frames without a portrait; the target-of-target
--     beside the target's portrait, the target's auras and cast bar under its
--     block
--
-- How: Blizzard's frames, portraits and bars stay (Edit Mode, clicks, menus,
-- vehicle handling all keep working). Its frame art is faded to alpha 0, the
-- portrait and bar masks are plain squares, and own bars over Blizzard's show
-- the same values. Everything is laid out in whole screen pixels from the
-- frame's top-left, mirrored for target and focus: name above the bars.
-- Positions are applied out of combat (the frames are protected) and again
-- after Blizzard's own art updates.
-- Cost: nothing while nothing changes.
local _, ns = ...

local M = ns:NewModule("UnitFrameSkin", {
    title = "Unit Frame Skin",
    group = "Interface",
    desc = "Player, target, focus, pet, party and boss frames as one block: a square portrait and taller health and mana bars "
        .. "in a bronze-lined plate, with the level in a small box (Blizzard's frames underneath; Edit Mode as usual).",
})

-- Layout, in the frame's units (Edit Mode's frame size scales it all): edge
-- and top = the block's distance from the frame's side / top; width = the
-- bars'; health / mana = the bars' heights (the portrait is as tall as both,
-- with the line between them); nameGap = name to block.
local METRICS = {
    full = { edge = 24, top = 30, width = 124, health = 24, mana = 14, nameGap = 3 },
    small = { edge = 5, top = 14, width = 70, health = 14, mana = 7, nameGap = 2 },   -- target of target, pet
    party = { edge = 6, top = 14, width = 84, health = 16, mana = 8, nameGap = 2 },
    boss = { edge = 24, top = 30, width = 124, health = 20, mana = 10, nameGap = 3 }, -- no portrait
}
-- Blizzard anchors the target / focus auras to its frame art (here faded
-- out) at these offsets; the art is moved so the auras sit AURA_GAP clear
-- of the block (below it, or above with "buffs on top").
local AURA_START_X, AURA_START_Y, AURA_MIRRORED_START_Y = 5, 9, -6
local AURA_GAP = 4
-- Target / focus: the target-of-target frame beside the block (TOT_GAP right
-- of the portrait, its block level with this one), and the cast bar under the
-- block, or under the auras below it, as wide as the block.
local TOT_GAP = 8
local CAST_GAP = 6
-- The plate behind portrait and bars, as Forever frames its nameplate bars
-- and level box (sizes in screen pixels): a black outline, a bronze line
-- lighter at the top, and a dark rim round each cell, all with rounded
-- corners (stepped pixel by pixel); the cells (portrait, health, mana) split
-- by rim, bronze, rim.
local PLATE_RING = 3       -- outline + bronze + rim
local PLATE_DIVIDER = 3    -- rim + bronze + rim
local PLATE_RADIUS = 3     -- the outline's corner; the bronze's is one less, the rims' 1
local PLATE_OUTLINE = { 0, 0, 0, 0.9 }
local PLATE_RIM = { 0.06, 0.06, 0.06, 0.95 } -- also the empty part of a bar
local PLATE_BRONZE = {
    default = { top = { 1, 0.88, 0.74 }, bottom = { 0.6, 0.45, 0.28 } },
    elite = { top = { 1, 0.9, 0.45 }, bottom = { 0.75, 0.55, 0.12 } },
    rare = { top = { 0.92, 0.94, 1 }, bottom = { 0.5, 0.52, 0.58 } },
}
local CLASSIFICATION_PLATE = { elite = "elite", worldboss = "elite", rareelite = "elite", rare = "rare" }
-- The level in the nameplates' level box.
local LEVEL_BOX_ATLAS = "ui-hud-nameplates-levelindicator"
local LEVEL_SKULL_ATLAS = "ui-hud-nameplates-levelindicator-skull"
local LEVEL_BOX_HEIGHT = 16
local LEVEL_BOX_PAD = 10   -- px of box beside the number
local LEVEL_BOX_MIN = 22
local LEVEL_BOX_SECRET = 26 -- width for a level we can't measure (two digits)
local LEVEL_BOX_OUT = 4    -- px the box sticks out past the block's corner
local PVP_SCALE = 0.6      -- the PvP / faction icon, at the block's top corner
local SQUARE = "Interface\\Buttons\\WHITE8X8"
-- Bars in Forever's nameplate fill (the cooldown manager's bar art), tinted.
local BAR_FILL_ATLAS = "UI-HUD-CoolDownManager-Bar"
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8" -- replaced by the fill atlas
local GREY = { 0.5, 0.5, 0.5 }

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v) if type(v) == "number" and not Secret(v) then return v end end

local function Path(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        if type(node) ~= "table" then return nil end
        node = node[select(i, ...)]
    end
    return node
end

local concealed = {}
local function Conceal(region)
    if not region or concealed[region] or not region.SetAlpha then return end
    concealed[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then self:SetAlpha(0) end
    end)
end

-- The name band is recoloured on every update: keep its colour transparent too.
local function ConcealColor(region)
    if not region or not region.SetVertexColor then return end
    Conceal(region)
    local r, g, b = region:GetVertexColor()
    region:SetVertexColor(r, g, b, 0)
    hooksecurefunc(region, "SetVertexColor", function(self, nr, ng, nb, na)
        if na ~= 0 then self:SetVertexColor(nr, ng, nb, 0) end
    end)
end

-- The plate (see PLATE_*), on a frame below the portrait and the bars.
-- A rounded rectangle of corner radius r is r + 1 stacked rectangles, each
-- one pixel narrower and taller than the last.
local function RoundRect(plate, sublevel, color, radius)
    local shape = { radius = radius }
    for k = 0, radius do
        local texture = plate:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        shape[k + 1] = texture
    end
    return shape
end

local function BuildPlate(skin, level)
    local plate = CreateFrame("Frame", nil, skin.parts.frame)
    plate:SetFrameLevel(level)
    plate.outline = RoundRect(plate, -8, PLATE_OUTLINE, PLATE_RADIUS)
    plate.bronze = RoundRect(plate, -7, { 1, 1, 1, 1 }, PLATE_RADIUS - 1)
    -- Rims: portrait, health, mana.
    plate.rims = {}
    for i = 1, 3 do plate.rims[i] = RoundRect(plate, -6, PLATE_RIM, 1) end
    skin.plate = plate
end

-- The bronze, lighter at the top: each of its rectangles shaded for where it
-- sits in the plate (kept from the last layout).
local function ShadeBronze(skin)
    local plate = skin.plate
    local c = PLATE_BRONZE[skin.plateKey or "default"]
    local height = plate.pixelHeight
    if not height then return end
    local function At(y) -- colour at y pixels from the plate's top
        local t = 1 - y / height
        return CreateColor(c.bottom[1] + (c.top[1] - c.bottom[1]) * t, c.bottom[2] + (c.top[2] - c.bottom[2]) * t,
            c.bottom[3] + (c.top[3] - c.bottom[3]) * t, 1)
    end
    for _, texture in ipairs(plate.bronze) do
        if texture.spanTop then
            texture:SetGradient("VERTICAL", At(texture.spanTop + texture.spanHeight), At(texture.spanTop))
        end
    end
end

-- The frames and their parts.
local function Parts(kind)
    if kind == "player" then
        local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
        local main = Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain")
        local health = PlayerFrame_GetHealthBarContainer and PlayerFrame_GetHealthBarContainer() or (main and main.HealthBarsContainer)
        local mana = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar() or Path(main, "ManaBarArea", "ManaBar")
        return {
            frame = PlayerFrame, unit = "player", side = "LEFT",
            portrait = container and container.PlayerPortrait, mask = container and container.PlayerPortraitMask,
            art = { container and container.FrameTexture, container and container.AlternatePowerFrameTexture,
                container and container.FrameFlash, main and main.StatusTexture },
            health = health, healthBar = health and health.HealthBar, healthMask = health and health.HealthBarMask,
            mana = mana, manaMask = mana and mana.ManaBarMask,
            level = PlayerLevelText, badge = main and main.LevelBackgroundCircle, name = PlayerName,
            nameBand = main and main.ReputationColor,
            pvp = Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentContextual", "PVPIcon"),
        }
    end
    if kind == "targettot" or kind == "focustot" then
        local tot = kind == "targettot" and TargetFrameToT or FocusFrameToT
        return {
            frame = tot, unit = kind == "targettot" and "targettarget" or "focustarget", side = "LEFT", small = true,
            portrait = tot and tot.Portrait, mask = tot and tot.PortraitMask,
            art = { tot and tot.FrameTexture, tot and tot.Background },
            health = tot and tot.HealthBar, healthBar = tot and tot.HealthBar,
            healthMask = tot and tot.HealthBar and tot.HealthBar.HealthBarMask,
            mana = tot and tot.ManaBar, manaMask = tot and tot.ManaBar and tot.ManaBar.ManaBarMask,
            name = tot and tot.Name,
        }
    end
    if kind == "pet" then
        return {
            frame = PetFrame, unit = "pet", side = "LEFT", small = true, fitHitRect = true,
            portrait = PetPortrait, mask = PetFrame and PetFrame.PortraitMask,
            art = { PetFrameTexture, PetFrameFlash, PetAttackModeTexture },
            health = PetFrameHealthBar, healthBar = PetFrameHealthBar, healthMask = PetFrameHealthBarMask,
            mana = PetFrameManaBar, manaMask = PetFrameManaBarMask, name = PetName,
        }
    end
    local partyIndex = kind:match("^party(%d)$")
    if partyIndex then
        local member = PartyFrame and PartyFrame["MemberFrame" .. partyIndex]
        local health = member and member.HealthBarContainer
        local overlay = member and member.PartyMemberOverlay
        return {
            frame = member, unit = kind, side = "LEFT", metrics = "party", fitHitRect = true,
            portrait = member and member.Portrait, mask = member and member.PortraitMask,
            art = { member and member.Texture, member and member.VehicleTexture, member and member.Flash,
                overlay and overlay.Status },
            health = health, healthBar = health and health.HealthBar,
            healthMask = health and health.HealthBar and health.HealthBar.HealthBarMask,
            mana = member and member.ManaBar, manaMask = member and member.ManaBar and member.ManaBar.ManaBarMask,
            name = member and member.Name,
        }
    end
    local bossIndex = kind:match("^boss(%d)$")
    local frame = bossIndex and _G["Boss" .. bossIndex .. "TargetFrame"] or (kind == "target" and TargetFrame or FocusFrame)
    local container = frame and frame.TargetFrameContainer
    local main = Path(frame, "TargetFrameContent", "TargetFrameContentMain")
    local contextual = Path(frame, "TargetFrameContent", "TargetFrameContentContextual")
    local health = main and main.HealthBarsContainer
    local mana = main and main.ManaBar
    local parts = {
        frame = frame, unit = kind, side = "RIGHT",
        portrait = container and container.Portrait, mask = container and container.PortraitMask,
        art = { container and container.FrameTexture, container and container.Flash },
        auraAnchor = container and container.FrameTexture,
        nameBand = main and main.ReputationColor, pvp = contextual and contextual.PvpIcon,
        health = health, healthBar = health and health.HealthBar,
        -- Blizzard's shaped bar masks: on the container or on the bar itself.
        healthMask = health and (health.HealthBarMask or (health.HealthBar and health.HealthBar.HealthBarMask)),
        mana = mana, manaMask = mana and mana.ManaBarMask,
        level = main and main.LevelText, badge = main and main.LevelBackgroundCircle,
        skull = contextual and contextual.HighLevelTexture, name = main and main.Name,
        tot = frame and frame.totFrame, totKind = kind .. "tot", spellbar = frame and frame.spellbar,
    }
    if bossIndex then
        -- Boss frames: no portrait (Blizzard hides it), no auras, no ToT.
        parts.noPortrait, parts.metrics, parts.tot, parts.auraAnchor = true, "boss", nil, nil
        parts.art.threat = frame and frame.threatIndicator
    end
    return parts
end

local skins = {}    -- [kind] = { parts, portraitBorder, ... }
local placing = false

-- Portrait, bars, name and level (protected frames: out of combat).
local LayoutNow
local function Layout(skin)
    if InCombatLockdown() and (skin.parts.health:IsProtected() or skin.parts.portrait:IsProtected()) then
        if not skin.queued then
            skin.queued = true
            ns:OutOfCombat(function() skin.queued = false; Layout(skin) end)
        end
        return
    end
    placing = true
    local ok, err = pcall(LayoutNow, skin)
    placing = false
    if not ok then error(err, 0) end
    local totSkin = skin.parts.totKind and skins[skin.parts.totKind]
    if totSkin and totSkin.built then Layout(totSkin) end
end

-- The target / focus cast bar under the block, or under the auras when they
-- hang below it (as Blizzard anchors it to them), as wide as the block.
local function PlaceCastBar(skin)
    local p, plate = skin.parts, skin.plate
    local bar = p.spellbar
    if not (bar and plate and plate:GetNumPoints() > 0) then return end
    local frame = p.frame
    local container = frame.GetAuraContainer and frame:GetAuraContainer()
    local below = false
    if container and not frame.buffsOnTop then
        local ok, rows = pcall(container.GetNumVisibleFlowLayoutLines, container)
        below = ok and Plain(rows) and rows > 0
    end
    bar:ClearAllPoints()
    if bar.castBarOnSide then
        -- Boss frames, Edit Mode's "cast bar on the side": left of the block.
        bar:SetPoint("RIGHT", plate, "LEFT", -CAST_GAP * 2, 0)
        return
    end
    if below then
        -- As Blizzard does before anchoring the bar to the auras.
        if bar.AddForbiddenAspects and container.GetInheritableForbiddenAspects and Enum.ScriptObjectPropagationPath then
            pcall(bar.AddForbiddenAspects, bar,
                container:GetInheritableForbiddenAspects(Enum.ScriptObjectPropagationPath.Layout))
        end
        bar:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -CAST_GAP)
    else
        bar:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, -CAST_GAP)
    end
    local width = Plain(plate:GetWidth())
    if width and width > 0 then bar:SetWidth(width / bar:GetScale()) end
end

function LayoutNow(skin)
    local p = skin.parts
    local m = METRICS[p.metrics or (p.small and "small" or "full")]
    local frame = p.frame
    local px = PixelUtil and PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1) or 1
    if not px or px <= 0 then px = 1 end
    local function Pixels(v) return math.max(1, math.floor(v / px + 0.5)) end
    -- Sizes in whole screen pixels; x counts from the block's portrait side.
    local R, D = PLATE_RING, PLATE_DIVIDER
    local healthHeight, manaHeight, barWidth = Pixels(m.health), Pixels(m.mana), Pixels(m.width)
    local size = healthHeight + D + manaHeight
    local portraitRoom = p.noPortrait and 0 or size + D
    local plateWidth, plateHeight = R + portraitRoom + barWidth + R, R + size + R
    local barsX, manaY = R + portraitRoom, R + healthHeight + D
    -- The block's top-left on a whole screen pixel (from the frame's).
    local frameWidth = Plain(frame:GetWidth()) or 232
    local left = p.side == "LEFT" and m.edge or frameWidth - m.edge - plateWidth * px
    local frameLeft, frameTop = Plain(frame:GetLeft()), Plain(frame:GetTop())
    local ox, oy
    if frameLeft and frameTop then
        ox = math.floor((frameLeft + left) / px + 0.5) * px - frameLeft
        oy = frameTop - math.floor((frameTop - m.top) / px + 0.5) * px
    else
        ox, oy = math.floor(left / px + 0.5) * px, math.floor(m.top / px + 0.5) * px
    end
    local function Mirror(x, w)
        if p.side ~= "LEFT" then return plateWidth - x - w end
        return x
    end
    -- Regions on the frame (protected bars can't anchor to textures).
    local function Place(region, x, y, w, h)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", frame, "TOPLEFT", ox + Mirror(x, w) * px, -(oy + y * px))
        region:SetSize(w * px, h * px)
    end
    -- The plate's own textures, each shape a stack of rectangles (RoundRect).
    local plate = skin.plate
    local function Draw(shape, x, y, w, h)
        local r = shape.radius
        for k = 0, r do
            local texture = shape[k + 1]
            local tx, ty, tw, th = x + r - k, y + k, w - 2 * (r - k), h - 2 * k
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", plate, "TOPLEFT", Mirror(tx, tw) * px, -ty * px)
            texture:SetSize(tw * px, th * px)
            texture.spanTop, texture.spanHeight = ty, th
        end
    end
    Place(plate, 0, 0, plateWidth, plateHeight)
    plate.pixelHeight = plateHeight
    Draw(plate.outline, 0, 0, plateWidth, plateHeight)
    Draw(plate.bronze, 1, 1, plateWidth - 2, plateHeight - 2)
    for k = 1, #plate.rims[1] do plate.rims[1][k]:SetShown(not p.noPortrait) end
    if not p.noPortrait then Draw(plate.rims[1], R - 1, R - 1, size + 2, size + 2) end
    Draw(plate.rims[2], barsX - 1, R - 1, barWidth + 2, healthHeight + 2)
    Draw(plate.rims[3], barsX - 1, manaY - 1, barWidth + 2, manaHeight + 2)
    ShadeBronze(skin)
    -- Portrait and bars in their cells.
    if not p.noPortrait then Place(p.portrait, R, R, size, size) end
    if p.mask and not p.noPortrait then
        p.mask:SetTexture(SQUARE)
        p.mask:ClearAllPoints()
        p.mask:SetAllPoints(p.portrait)
    end
    Place(p.health, barsX, R, barWidth, healthHeight)
    Place(p.mana, barsX, manaY, barWidth, manaHeight)
    if skin.healthBar then Place(skin.healthBar, barsX, R, barWidth, healthHeight) end
    if skin.manaBar then Place(skin.manaBar, barsX, manaY, barWidth, manaHeight) end
    -- No resource bar (most NPCs): an empty grey bar in the mana cell.
    if skin.emptyMana then
        Place(skin.emptyMana, barsX, manaY, barWidth, manaHeight)
        skin.emptyMana:SetShown(not p.mana:IsShown())
    end
    if p.healthBar and p.healthBar ~= p.health then
        p.healthBar:ClearAllPoints()
        p.healthBar:SetAllPoints(p.health)
    end
    if p.healthMask then
        p.healthMask:SetTexture(SQUARE)
        p.healthMask:ClearAllPoints()
        p.healthMask:SetAllPoints(p.health)
    end
    if p.manaMask then
        p.manaMask:SetTexture(SQUARE)
        p.manaMask:ClearAllPoints()
        p.manaMask:SetAllPoints(p.mana)
    end
    local side = p.side == "LEFT" and "LEFT" or "RIGHT"
    if p.name then
        p.name:ClearAllPoints()
        p.name:SetPoint("BOTTOM" .. side, p.health, "TOP" .. side, 0, R * px + m.nameGap)
        p.name:SetWidth(barWidth * px)
        p.name:SetJustifyH(side)
    end
    if skin.levelBox then
        local box = skin.levelBox
        box:ClearAllPoints()
        box:SetPoint("BOTTOM" .. side, plate, "BOTTOM" .. side,
            side == "LEFT" and -LEVEL_BOX_OUT or LEVEL_BOX_OUT, -LEVEL_BOX_OUT)
    end
    -- Blizzard's aura container hangs off the (faded) frame art: move the art
    -- so the auras clear the block, starting at its bars-side edge.
    local anchor = p.auraAnchor
    if anchor then
        local auraLeft = ox + (p.side == "LEFT" and barsX * px or 0)
        local auraTop = oy - AURA_GAP + AURA_MIRRORED_START_Y
        local auraBottom = oy + plateHeight * px + AURA_GAP + AURA_START_Y
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", frame, "TOPLEFT", auraLeft - AURA_START_X, -auraTop)
        anchor:SetSize((barWidth + R) * px + AURA_START_X, auraBottom - auraTop)
    end
    if p.pvp then
        if p.pvp.SetScale then p.pvp:SetScale(PVP_SCALE) end
        p.pvp:ClearAllPoints()
        p.pvp:SetPoint("CENTER", plate, "TOP" .. side, 0, 0)
    end
    -- The target of target beside the portrait (its own block level with
    -- this one); offsets in its own scale.
    if p.tot and p.side ~= "LEFT" then
        local small = METRICS.small
        local k = frame:GetEffectiveScale() / p.tot:GetEffectiveScale()
        p.tot:ClearAllPoints()
        p.tot:SetPoint("TOPLEFT", frame, "TOPLEFT", (ox + plateWidth * px + TOT_GAP) * k - small.edge,
            -(oy * k - small.top))
    end
    PlaceCastBar(skin)
    -- Small frames click where the block is (Blizzard's click area fits its
    -- own art).
    if p.fitHitRect and not InCombatLockdown() then
        local frameHeight = Plain(frame:GetHeight())
        if frameHeight then
            frame:SetHitRectInsets(math.max(0, ox), math.max(0, frameWidth - ox - plateWidth * px),
                math.max(0, oy - m.health), math.max(0, frameHeight - oy - plateHeight * px))
        end
    end
end

-- The plate's bronze: gold for elites and bosses, silver for rares.
local function UpdateClassification(skin)
    if not skin.plate then return end
    local unit = skin.parts.unit
    local class = unit ~= "player" and UnitExists(unit) and UnitClassification(unit)
    local key = type(class) == "string" and not Secret(class) and CLASSIFICATION_PLATE[class] or "default"
    if skin.plateKey == key then return end
    skin.plateKey = key
    ShadeBronze(skin)
end

-- NPC names in their reaction colour (the name banner that showed it is gone).
---------------------------------------------------------------------------
-- Bar fill and colours (kept after Blizzard / other code sets them)
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Our own bars over Blizzard's. Blizzard keeps its bars (values, events,
-- clicks), but places and shades its fill its own way per frame; so its fill
-- and texts are faded out and an own StatusBar on top shows the same values
-- (copied from every SetValue / SetMinMaxValues; secret values pass through)
-- in the nameplates' art, with its own texts (percentage left, value right).
---------------------------------------------------------------------------
-- Blizzard's bar texts (all hidden: the bars write their own).
local TEXT_KEYS = { "LeftText", "RightText", "TextString", "HealthBarText", "ManaBarText" }
local BAR_TEXT_FONT = "TextStatusBarText" -- Blizzard's bar text font
local BAR_TEXT_INSET = 4

-- An own bar in the nameplates' fill. It is placed in its cell by the layout
-- (not on Blizzard's bar, which Blizzard moves again at times) and shown
-- along with Blizzard's `source`, whose values it copies. `small` bars (the
-- target of target) have no texts; the others show the percentage on the left
-- and the value on the right, written by `onValue` after every value change.
local function OwnBar(source, parent, textOwner, small)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetFrameLevel(source:GetFrameLevel() + 2)
    bar:SetShown(source:IsShown())
    source:HookScript("OnShow", function() bar:Show() end)
    source:HookScript("OnHide", function() bar:Hide() end)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:GetStatusBarTexture():SetAtlas(BAR_FILL_ATLAS)
    if not small then
        -- Texts above the fill.
        bar.texts = CreateFrame("Frame", nil, bar)
        bar.texts:SetAllPoints(bar)
        bar.texts:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.left = bar.texts:CreateFontString(nil, "OVERLAY", BAR_TEXT_FONT)
        bar.left:SetPoint("LEFT", bar, "LEFT", BAR_TEXT_INSET, 0)
        bar.left:SetJustifyH("LEFT")
        bar.right = bar.texts:CreateFontString(nil, "OVERLAY", BAR_TEXT_FONT)
        bar.right:SetPoint("RIGHT", bar, "RIGHT", -BAR_TEXT_INSET, 0)
        bar.right:SetJustifyH("RIGHT")
    end
    local function Changed() if bar.onValue then bar.onValue() end end
    -- Same values as Blizzard's bar.
    bar:SetMinMaxValues(source:GetMinMaxValues())
    bar:SetValue(source:GetValue())
    hooksecurefunc(source, "SetMinMaxValues", function(_, low, high) bar:SetMinMaxValues(low, high); Changed() end)
    hooksecurefunc(source, "SetValue", function(_, value) bar:SetValue(value); Changed() end)
    -- Blizzard's fill and texts out of sight.
    local fill = source:GetStatusBarTexture()
    if fill then Conceal(fill) end
    hooksecurefunc(source, "SetStatusBarTexture", function(self)
        local newFill = self:GetStatusBarTexture()
        if newFill then Conceal(newFill) end
    end)
    for _, owner in ipairs({ textOwner, source }) do
        for _, key in ipairs(TEXT_KEYS) do
            if type(owner[key]) == "table" then Conceal(owner[key]) end
        end
    end
    return bar
end

-- A health / power value: with thousands separators as Blizzard writes it; a
-- secret one abbreviated, or plain.
local function ValueText(fs, value)
    if not Secret(value) then
        fs:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value))
    elseif not (AbbreviateNumbers and pcall(function() fs:SetText(AbbreviateNumbers(value)) end)) then
        fs:SetFormattedText("%d", value)
    end
end

local function PercentText(fs, percent, value, max)
    if percent ~= nil then
        fs:SetFormattedText("%.0f%%", percent)
    elseif Plain(value) and Plain(max) and max > 0 then
        fs:SetFormattedText("%.0f%%", value / max * 100)
    else
        fs:SetText("")
    end
end

local function Scale100()
    return CurveConstants and CurveConstants.ScaleTo100
end

local function HealthText(skin)
    local bar, unit = skin.healthBar, skin.parts.unit
    if not (bar and bar.left) then return end
    if not UnitExists(unit) then bar.left:SetText(""); bar.right:SetText("") return end
    local percent = UnitHealthPercent and Scale100() and UnitHealthPercent(unit, nil, Scale100())
    PercentText(bar.left, percent, UnitHealth(unit), UnitHealthMax(unit))
    ValueText(bar.right, UnitHealth(unit))
end

local function PowerText(skin)
    local bar, unit = skin.manaBar, skin.parts.unit
    if not (bar and bar.left) then return end
    if not UnitExists(unit) then bar.left:SetText(""); bar.right:SetText("") return end
    -- (UnitPowerPercent's arguments differ between clients: read in a pcall.)
    local ok, percent = false, nil
    if UnitPowerPercent and Scale100() then ok, percent = pcall(UnitPowerPercent, unit, nil, false, Scale100()) end
    if not ok then percent = nil end
    PercentText(bar.left, percent, UnitPower(unit), UnitPowerMax(unit))
    ValueText(bar.right, UnitPower(unit))
end

local function HealthColor(skin)
    local p = skin.parts
    local bar, unit = skin.healthBar, p.unit
    if not (bar and UnitExists(unit)) then return end
    local isPlayer = UnitIsPlayer(unit)
    if Secret(isPlayer) then return end
    local connected, tapped = UnitIsConnected(unit), UnitIsTapDenied(unit)
    if (not Secret(connected) and not connected) or (not Secret(tapped) and tapped) then
        bar:SetStatusBarColor(GREY[1], GREY[2], GREY[3])
    elseif isPlayer then
        local _, class = UnitClass(unit)
        local color = class and C_ClassColor.GetClassColor(class)
        if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
    else
        -- Reaction colour. The game's is dim (hostile red at half strength):
        -- at full strength, as the nameplates show it, when it can be read;
        -- a secret one goes to the bar as it is.
        local r, g, b = UnitSelectionColor(unit)
        if Plain(r) and Plain(g) and Plain(b) then
            local brightest = math.max(r, g, b)
            if brightest > 0 then r, g, b = r / brightest, g / brightest, b / brightest end
        end
        bar:SetStatusBarColor(r, g, b)
    end
end

local function ManaColor(skin)
    local p = skin.parts
    local bar = skin.manaBar
    if not (bar and UnitExists(p.unit)) then return end
    local powerType, token = UnitPowerType(p.unit)
    local color = PowerBarColor and ((not Secret(token) and token and PowerBarColor[token])
        or (not Secret(powerType) and PowerBarColor[powerType]))
    if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
end

-- Target and focus portraits come from the game already round (Blizzard
-- relies on that instead of a mask): ask for the square one after each update.
local function SquarePortrait(frame)
    for kind, skin in pairs(skins) do
        local p = skin.parts
        if kind ~= "player" and not p.noPortrait and p.frame == frame and p.portrait and UnitExists(p.unit) then
            SetPortraitTexture(p.portrait, p.unit, true)
        end
    end
end

local function Refresh(skin)
    UpdateClassification(skin)
    HealthColor(skin)
    ManaColor(skin)
    HealthText(skin)
    PowerText(skin)
    if skin.parts.unit ~= "player" then SquarePortrait(skin.parts.frame) end
    if skin.mirrorLevel then skin.mirrorLevel() end
end

local function Build(skin)
    local p = skin.parts
    for _, region in pairs(p.art) do Conceal(region) end -- (pairs: some may be missing)
    Conceal(p.badge)
    ConcealColor(p.nameBand)
    -- Mana bar shown / hidden (NPCs without mana): the empty track takes its place.
    p.mana:HookScript("OnShow", function() if skin.emptyMana then skin.emptyMana:Hide() end end)
    p.mana:HookScript("OnHide", function() if skin.emptyMana then skin.emptyMana:Show() end end)
    if p.pvp then
        hooksecurefunc(p.pvp, "SetPoint", function()
            if not placing then Layout(skin) end
        end)
    end
    -- Blizzard re-anchors the ToT (focus size) and the cast bar (each cast,
    -- aura changes): put them back.
    if p.tot then
        hooksecurefunc(p.tot, "SetPoint", function()
            if not placing then Layout(skin) end
        end)
    end
    if p.spellbar and type(p.spellbar.AdjustPosition) == "function" then
        hooksecurefunc(p.spellbar, "AdjustPosition", function() PlaceCastBar(skin) end)
    end
    -- The plate below the portrait and the bars.
    local container = p.frame.TargetFrameContainer or p.frame.PlayerFrameContainer or p.frame
    local level = container:GetFrameLevel()
    BuildPlate(skin, math.max(0, math.min(level, p.health:GetFrameLevel(), p.mana:GetFrameLevel()) - 1))
    -- The level in a nameplate level box, mirroring Blizzard's level text
    -- (its colour too: difficulty, resting blue) and boss skull.
    if p.level then
        local box = CreateFrame("Frame", nil, p.frame)
        box:SetFrameLevel(level + 4)
        box:SetHeight(LEVEL_BOX_HEIGHT)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas(LEVEL_BOX_ATLAS)
        bg:SetAllPoints()
        if bg.SetTextureSliceMargins then
            bg:SetTextureSliceMargins(6, 6, 6, 6)
            bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
        box.text = box:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateLevel")
        box.text:SetPoint("CENTER")
        box.skull = box:CreateTexture(nil, "OVERLAY")
        box.skull:SetAtlas(LEVEL_SKULL_ATLAS)
        box.skull:SetSize(LEVEL_BOX_HEIGHT - 4, LEVEL_BOX_HEIGHT - 4)
        box.skull:SetPoint("CENTER")
        skin.levelBox = box
        -- The unit's level from the game (Blizzard's level text on the
        -- target frame isn't dependable to copy): your own in Blizzard's
        -- level colour (resting blue), others in the game's difficulty
        -- colour, the skull for "??" levels. A secret level goes straight to
        -- the text call (which takes it) with a two-digit width.
        local function Mirror()
            local unit = p.unit
            if not UnitExists(unit) then box:Hide() return end
            local level = UnitLevel(unit)
            if Secret(level) then
                box.text:SetFormattedText("%d", level)
                box.text:SetTextColor(p.level:GetTextColor())
                box.skull:Hide()
                box:SetWidth(LEVEL_BOX_SECRET)
                box:Show()
                return
            end
            if type(level) ~= "number" or level <= 0 then
                box.text:SetText("")
                box.skull:Show()
                box:SetWidth(LEVEL_BOX_MIN)
                box:Show()
                return
            end
            box.skull:Hide()
            box.text:SetText(level)
            if unit == "player" or not GetCreatureDifficultyColor then
                box.text:SetTextColor(p.level:GetTextColor())
            else
                local color = GetCreatureDifficultyColor(level)
                box.text:SetTextColor(color.r, color.g, color.b)
            end
            box:SetWidth(math.max(LEVEL_BOX_MIN, box.text:GetStringWidth() + LEVEL_BOX_PAD))
            box:Show()
        end
        for _, method in ipairs({ "SetText", "SetFormattedText", "SetTextColor" }) do
            hooksecurefunc(p.level, method, Mirror)
        end
        if p.skull then Conceal(p.skull) end
        Conceal(p.level)
        Mirror()
        skin.mirrorLevel = Mirror
    end
    -- Own bars over Blizzard's (see OwnBar), recoloured whenever Blizzard
    -- colours its own.
    if p.healthBar then
        skin.healthBar = OwnBar(p.healthBar, p.frame, p.health, p.small)
        skin.healthBar.onValue = function() HealthText(skin) end
        hooksecurefunc(p.healthBar, "SetStatusBarColor", function() HealthColor(skin) end)
    end
    if p.mana then
        skin.manaBar = OwnBar(p.mana, p.frame, p.mana, p.small)
        skin.manaBar.onValue = function() PowerText(skin) end
        hooksecurefunc(p.mana, "SetStatusBarColor", function() ManaColor(skin) end)
    end
    -- Shown instead of the mana bar when the unit has none: an empty bar,
    -- the fill art in dark grey.
    skin.emptyMana = CreateFrame("Frame", nil, p.frame)
    skin.emptyMana:SetFrameLevel(p.mana:GetFrameLevel() + 2)
    local emptyFill = skin.emptyMana:CreateTexture(nil, "ARTWORK")
    emptyFill:SetAtlas(BAR_FILL_ATLAS)
    emptyFill:SetDesaturated(true)
    emptyFill:SetVertexColor(0.22, 0.22, 0.22)
    emptyFill:SetAllPoints()
    skin.emptyMana:Hide()
    if p.name then
        ns.OutlineText(p.name)
        hooksecurefunc(p.name, "SetPoint", function()
            if not placing then Layout(skin) end
        end)
    end
end

local function Skin(kind)
    local skin = skins[kind]
    if not skin then
        local parts = Parts(kind)
        if not (parts.frame and parts.portrait and parts.health and parts.mana) then return end
        skin = { parts = parts }
        skins[kind] = skin
    end
    if skin.built then
        Layout(skin)
        Refresh(skin)
        return
    end
    skin.built = true
    Build(skin)
    Layout(skin)
    Refresh(skin)
end

---------------------------------------------------------------------------
-- /kk unitframeskin art: the art Forever's action buttons and an enemy
-- nameplate are built from (atlas, layer, size, anchors), to build from.
---------------------------------------------------------------------------
local function KeyOf(owner, region)
    for key, value in pairs(owner) do
        if value == region then return tostring(key) end
    end
    return region:GetDebugName():match("[^%.]+$") or "?"
end

local function Num(v) return Plain(v) and ("%.1f"):format(v) or "?" end

-- Art names only, each read in a pcall: nameplates are restricted regions
-- (measuring them is refused), so nothing is measured there.
local function Try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function DumpRegions(label, frame, owner, measure)
    if not frame then ns:Print(label .. ": missing") return end
    ns:Print(("%s %s"):format(label, frame:GetObjectType()))
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") or region:IsObjectType("MaskTexture") then
            local layer, sub = Try(region.GetDrawLayer, region)
            local art = Try(region.GetAtlas, region) or Try(region.GetTexture, region) or "-"
            local size = ""
            if measure then
                local w, h = Try(region.GetSize, region)
                size = (" %sx%s"):format(Num(w), Num(h))
            end
            local slice = ""
            if region.GetTextureSliceMargins then
                local l, t, r, b = Try(region.GetTextureSliceMargins, region)
                if l then slice = (" slice=%s,%s,%s,%s"):format(Num(l), Num(t), Num(r), Num(b)) end
            end
            ns:Print(("  %s [%s %s] %s%s%s shown=%s"):format(KeyOf(owner or frame, region), tostring(layer),
                tostring(sub), tostring(art), size, slice, tostring(Try(region.IsShown, region))))
        end
    end
end

-- /kk unitframeskin sizes: the bars' real sizes on the player and target frames.
local function DumpSizes()
    for _, kind in ipairs({ "player", "target" }) do
        local skin = skins[kind]
        if not skin then
            ns:Print(kind .. ": not skinned")
        else
            local p = skin.parts
            local function Size(label, region)
                if not region then return label .. "=nil" end
                local w, h = region:GetSize()
                local scale = region:GetEffectiveScale()
                return ("%s=%sx%s (scale %.2f, %d points, shown %s)"):format(label, Num(w), Num(h), scale,
                    region:GetNumPoints(), tostring(region:IsShown()))
            end
            ns:Print(kind .. ": " .. Size("frame", p.frame) .. " " .. Size("portrait", p.portrait))
            ns:Print("  " .. Size("health", p.health) .. " " .. Size("healthBar", p.healthBar ~= p.health and p.healthBar or nil))
            local fill = p.healthBar and p.healthBar:GetStatusBarTexture()
            ns:Print("  " .. Size("healthFill", fill) .. " " .. Size("mana", p.mana))
            for i = 1, fill and fill:GetNumPoints() or 0 do
                local ok, point, relativeTo, relativePoint, x, y = pcall(fill.GetPoint, fill, i)
                if ok then
                    ns:Print(("  fill point %d: %s to %s %s %s,%s"):format(i, tostring(point),
                        relativeTo and (relativeTo.GetDebugName and relativeTo:GetDebugName() or "?") or "nil",
                        tostring(relativePoint), Num(x), Num(y)))
                else
                    ns:Print(("  fill point %d: not readable"):format(i))
                end
            end
            for i = 1, p.healthBar and p.healthBar:GetNumPoints() or 0 do
                local point, relativeTo, relativePoint, x, y = p.healthBar:GetPoint(i)
                ns:Print(("  healthBar point %d: %s to %s %s %s,%s"):format(i, point,
                    relativeTo and (relativeTo.GetDebugName and relativeTo:GetDebugName() or "?") or "nil",
                    tostring(relativePoint), Num(x), Num(y)))
            end
        end
    end
end

function M:OnSlash(args)
    if (args or ""):lower():match("^size") then DumpSizes() return end
    if not (args or ""):lower():match("^art") then
        ns:Print("/kk unitframeskin art: list the art of an action button and your target's nameplate")
        return
    end
    DumpRegions("ActionButton1", ActionButton1, nil, true)
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local unitFrame = plate and plate.UnitFrame
    if not unitFrame then ns:Print("no nameplate for your target: target an enemy with its nameplate showing") return end
    local container = unitFrame.HealthBarsContainer
    DumpRegions("HealthBarsContainer", container, container)
    local bar = container and container.healthBar
    DumpRegions("healthBar", bar, container)
    local fill = bar and Try(bar.GetStatusBarTexture, bar)
    if fill then ns:Print("  fill: " .. tostring(Try(fill.GetAtlas, fill) or Try(fill.GetTexture, fill))) end
    for _, child in ipairs({ container and container:GetChildren() }) do
        if child ~= bar then
            DumpRegions("child " .. KeyOf(container, child), child, container)
            for _, grandchild in ipairs({ child:GetChildren() }) do DumpRegions("  sub", grandchild, child) end
        end
    end
    for _, child in ipairs({ bar and bar:GetChildren() }) do DumpRegions("bar child " .. KeyOf(bar, child), child, bar) end
end

function M:OnEnable()
    local KINDS = { "player", "target", "focus", "targettot", "focustot", "pet" }
    for i = 1, 4 do KINDS[#KINDS + 1] = "party" .. i end
    for i = 1, 5 do KINDS[#KINDS + 1] = "boss" .. i end
    for _, kind in ipairs(KINDS) do
        ns.safecall(Skin, kind)
        local frame = Parts(kind).frame
        if frame then frame:HookScript("OnShow", function() ns.safecall(Skin, kind) end) end
    end
    ns:On("UNIT_PET", function(_, unit)
        if unit == "player" then ns.safecall(Skin, "pet") end
    end)
    ns:On("GROUP_ROSTER_UPDATE", function()
        for i = 1, 4 do ns.safecall(Skin, "party" .. i) end
    end)
    ns:On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
        for i = 1, 5 do ns.safecall(Skin, "boss" .. i) end
    end)
    -- Blizzard's own art updates put the bars back: lay them out again.
    for _, name in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_UpdateHealthBarVisuals", "PlayerFrame_UpdateManaBarVisuals" }) do
        if _G[name] then hooksecurefunc(name, function() ns.safecall(Skin, "player") end) end
    end
    for _, kind in ipairs({ "target", "focus" }) do
        local frame = kind == "target" and TargetFrame or FocusFrame
        if frame and type(frame.UpdateHealthBarVisuals) == "function" then
            hooksecurefunc(frame, "UpdateHealthBarVisuals", function() ns.safecall(Skin, kind) end)
        end
        for _, method in ipairs({ "CheckClassification", "CheckFaction" }) do
            if frame and type(frame[method]) == "function" then
                hooksecurefunc(frame, method, function() if skins[kind] then Refresh(skins[kind]) end end)
            end
        end
    end
    if UnitFramePortrait_Update then
        hooksecurefunc("UnitFramePortrait_Update", function(frame) ns.safecall(SquarePortrait, frame) end)
    end
    ns:On("PLAYER_TARGET_CHANGED", function()
        ns.safecall(Skin, "target")
        ns.safecall(Skin, "targettot")
    end)
    ns:On("PLAYER_FOCUS_CHANGED", function()
        ns.safecall(Skin, "focus")
        ns.safecall(Skin, "focustot")
    end)
    ns:On("UNIT_TARGET", function(_, unit)
        if unit == "target" then ns.safecall(Skin, "targettot") elseif unit == "focus" then ns.safecall(Skin, "focustot") end
    end)
    for _, event in ipairs({ "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_FLAGS" }) do
        ns:On(event, function(_, unit)
            if skins[unit] then Refresh(skins[unit]) end
        end)
    end
    ns:On("UNIT_FACTION", function(_, unit)
        if skins[unit] then Refresh(skins[unit]) end
    end)
    ns:On("UNIT_LEVEL", function(_, unit)
        if skins[unit] then Refresh(skins[unit]) end
    end)
    ns:On("UNIT_CLASSIFICATION_CHANGED", function(_, unit)
        if skins[unit] then Refresh(skins[unit]) end
    end)
    -- Pixel positions follow the frame's position and the UI scale.
    for _, event in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        ns:On(event, function()
            for kind in pairs(skins) do ns.safecall(Skin, kind) end
        end)
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", function()
            for kind in pairs(skins) do ns.safecall(Skin, kind) end
        end)
    end
end
