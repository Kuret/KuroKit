-- Arc HUD part: thin rings along your arc, per class, and the class
-- alerts round your character.
-- Inside the power ring: the five-second rule (mana users: drains over the
-- 5 s after you spend mana, then fills to each 2 s mana tick) or the energy
-- tick (fills to each 2 s tick), faded out at full power; your pet's health
-- (Hunters, Warlocks; pulsing red while it's low); druids' mana while
-- shapeshifted. Combo points: gems along your target's arc.
-- Shields (any class: any absorb on you): a short arc beside your character
-- (full when it goes up, draining as it soaks damage; sized from your own
-- shield casts, T.SHIELD_CASTS; red and flashing under a third of it), a
-- blue glow round your portrait while you
-- have one, a red ring bursting round your character when it breaks or runs
-- out. Lockouts (T.LOCKOUTS: Weakened Soul, Forbearance): a red countdown
-- sweep with its seconds over your portrait, a blue ring round your
-- character and its icon pulsing above you when it ends (the blocked
-- spells' own cooldown pulses held back meanwhile); from the aura, or in
-- combat, where the HUD can't see it, from your own cast: your clock. Your
-- target's interrupted casts burst a ring round its portrait. Ticks are timed
-- from when your power changes without a cast of yours spending it (values
-- stay secret; only the events count).
-- Target of target beside your target's portrait (inward): its name and a
-- small health bar; click it to target it (Core.lua's click buttons).
local _, ns = ...
local A = ns.ArcHUD
local M, T, sides = A.M, A.T, A.sides
local MEDIA, SCALE, SIDE_W = A.MEDIA, A.SCALE, A.SIDE_W
local ARC_CX, ARC_CY, ARC_R, ARC_HALF = A.ARC_CX, A.ARC_CY, A.ARC_R, A.ARC_HALF
local SOCKET_ANGLE, PORTRAIT_SIZE, RING_SIZE, FILL_ALPHA = A.SOCKET_ANGLE, A.PORTRAIT_SIZE, A.RING_SIZE, A.FILL_ALPHA
local ARC_INNER_EDGE, ARC_OUTER_EDGE, HEALTH_GREEN = A.ARC_INNER_EDGE, A.ARC_OUTER_EDGE, A.HEALTH_GREEN
local Secret, SetBarValue, NewBar, NewText, UnitRGB = A.Secret, A.SetBarValue, A.NewBar, A.NewText, A.UnitRGB

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
}

-- (defined further down)
local BuildTrims, BuildToT, UpdateTrims, UpdateToT, UpdatePet, UpdateShieldTrim, UpdateSoul
local UpdateFormMana, UpdateCombo
local OnSpent, OnSent, OnPowerChanged, UpdateTickShown

local trims = {}   -- [key] = { frame, bar, track } for this class's trims
local lock         -- this class's lockout (T.LOCKOUTS), if any
local X = { nameSets = {} } -- .lastSent: your last UNIT_SPELLCAST_SENT { spellID, target }
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
        gate.bar:SetPoint("CENTER", A.hud, "CENTER", 0, T.BURST_Y)
        burst.gates = { gate }
        burst.gated = ok
        parent = gate.clip
    end
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(T.BURST_SIZE, T.BURST_SIZE)
    ring:SetPoint("CENTER", A.hud, "CENTER", 0, T.BURST_Y)
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
    frame:SetPoint("CENTER", A.hud, "CENTER", T.MINI_X, T.MINI_Y)
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
    X.BuildShieldLow(trims.shield, rows)
end

-- The shield almost gone (under T.SHIELD_LOW of its size): its fill turns
-- red and the mini arc flashes red. The amount and size may be secret, so
-- the share is never computed: a hidden bar `gate` with the fill's own
-- range and value, 1 / SHIELD_LOW_SHARP times the fill's height, placed so
-- its fill's top crosses the fill rows from
-- top to bottom while the share goes from SHIELD_LOW down to SHIELD_LOW -
-- SHIELD_LOW_SHARP. The red sits in a clipping window that is the gate's
-- empty part (above its fill), so it shows over the whole arc below the
-- threshold and not at all above it; and inside a second window, the back
-- bar's fill (full with any shield, empty without), so no shield: no red.
function X.BuildShieldLow(t, rows)
    local height = rows:GetHeight() / T.SHIELD_LOW_SHARP
    local gate = CreateFrame("StatusBar", nil, t.frame)
    gate:SetOrientation("VERTICAL")
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gate:GetStatusBarTexture():SetAlpha(0)
    gate:SetSize(rows:GetWidth(), height)
    gate:SetPoint("BOTTOMLEFT", rows, "TOPLEFT", 0, -height * T.SHIELD_LOW)
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(1)
    local any = CreateFrame("Frame", nil, t.frame) -- (window 1: any shield)
    any:SetClipsChildren(true)
    any:SetAllPoints(t.back:GetStatusBarTexture())
    any:SetFrameLevel(t.bar:GetFrameLevel() + 1)
    local low = CreateFrame("Frame", nil, any)     -- (window 2: under the threshold)
    low:SetClipsChildren(true)
    low:SetPoint("BOTTOMLEFT", gate:GetStatusBarTexture(), "TOPLEFT")
    low:SetPoint("TOPRIGHT", gate, "TOPRIGHT")
    local warn = CreateFrame("Frame", nil, low)
    warn:SetAllPoints(t.frame)
    local edge = warn:CreateTexture(nil, "ARTWORK")
    edge:SetAllPoints(t.frame)
    edge:SetTexture(MEDIA .. "ArcMiniBack")
    edge:SetBlendMode("ADD")
    edge:SetVertexColor(T.SHIELD_LOW_COLOR[1], T.SHIELD_LOW_COLOR[2], T.SHIELD_LOW_COLOR[3])
    local fill = NewBar(warn, MEDIA .. "ArcMiniFill", "VERTICAL")
    fill:ClearAllPoints()
    fill:SetAllPoints(rows)
    fill:SetStatusBarColor(T.SHIELD_LOW_COLOR[1], T.SHIELD_LOW_COLOR[2], T.SHIELD_LOW_COLOR[3])
    local group = warn:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local flash = group:CreateAnimation("Alpha")
    flash:SetFromAlpha(1)
    flash:SetToAlpha(T.SHIELD_LOW_DIM)
    flash:SetDuration(T.SHIELD_LOW_PULSE)
    group:Play()
    t.lowGate, t.lowFill = gate, fill
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
        PlayBurst(t.burst) -- (blue round your character: it can go on you again)
        -- and the lockout's icon pulsing above your character, blue
        local ok, icon = pcall(C_Spell.GetSpellTexture, lock.spell)
        if ok and icon then A.QueuePulse(icon, T.READY_COLOR) end
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
    NewShield() -- (every class: any absorb on you)
    BuildCombo()
    if trims.mana then
        local c = PowerBarColor and PowerBarColor.MANA
        if c then trims.mana.bar:SetStatusBarColor(c.r, c.g, c.b) end
    end
    if trims.pet then X.BuildPetLow() end
    lock = T.LOCKOUTS[class]
    if lock then NewSoul() end
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        fullCurve = C_CurveUtil.CreateCurve()
        if fullCurve.SetType and Enum.LuaCurveType then fullCurve:SetType(Enum.LuaCurveType.Step) end
        fullCurve:AddPoint(0, 1)
        fullCurve:AddPoint(1, 0)
    end
end

-- The Cooldown Manager rails' arc edge (texture px): past this class's trims.
function A.RailEdge(layout)
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
-- The lockout by your own clock (combat hides the aura from the HUD): see
-- T.LOCKOUTS. (`soul`: named after the first, Weakened Soul.)
local soulCastAt          -- your trigger cast, waiting for an absorb change on you
local soulStart           -- the lockout on you since (your clock)
local soulDuration        -- its seconds (T.LOCKOUTS; read from the aura out of combat)

-- name -> rank 1's ID for a list of rank 1 IDs (names: every rank).
function X.NameSet(ids)
    if not ids then return nil end
    if X.nameSets[ids] then return X.nameSets[ids] end
    local set = {}
    for _, id in ipairs(ids) do
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and type(name) == "string" and not Secret(name) then set[name] = id end
    end
    X.nameSets[ids] = set
    return set
end

function X.SpellNameOf(spellID)
    if type(spellID) ~= "number" or Secret(spellID) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and type(name) == "string" and not Secret(name) then return name end
end

-- Your last cast of `spellID` went to yourself (its target readable: none,
-- or your name).
function X.SentToSelf(spellID)
    local sent = X.lastSent
    if not (sent and sent.spellID == spellID) then return false end
    local target = sent.target
    if target == nil or Secret(target) then return target == nil end
    return target == "" or target == UnitName("player")
end

function OnSent(target, spellID)
    if type(spellID) ~= "number" or Secret(spellID) then return end
    X.lastSent = { spellID = spellID, target = target }
end
local lastAbsorbChange = -100

-- `fromPet`: your pet's cast (only for shields: the Voidwalker's Sacrifice).
function OnSpent(spellID, fromPet)
    local now = GetTime()
    local name = X.SpellNameOf(spellID)
    local _, class = UnitClass("player")
    -- A shield of yours (any rank, by name): its size comes next.
    if name and trims.shield and X.NameSet(T.SHIELD_CASTS[class]) and X.NameSet(T.SHIELD_CASTS[class])[name] then
        captureUntil = now + T.SHIELD_CAPTURE
        UpdateShieldTrim()
    end
    -- A lockout's trigger.
    local trigger = name and not fromPet and lock and X.NameSet(lock.triggers)[name]
    if trigger then
        if lock.absorb then
            -- (the absorb change may come first)
            if now - lastAbsorbChange <= T.SHIELD_CAPTURE then soulStart = now else soulCastAt = now end
        elseif not (lock.self and lock.self[trigger]) or X.SentToSelf(spellID) then
            soulStart = now
        end
    end
    if fromPet then return end
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
-- Your pet low: a red copy of its arc pulsing in a clipping window that is
-- the empty part of a bar over PET_LOW..(PET_LOW + 0.01) whose value is the
-- pet's health share: above that it's full (window shut), below it empty
-- (window open). The share may be secret: only handed to the bar.
function X.BuildPetLow()
    local t = trims.pet
    local gate = NewGate(t.frame, t.bar:GetFrameLevel() + 2)
    gate.bar:SetAllPoints(t.frame)
    gate.bar:SetMinMaxValues(T.PET_LOW, T.PET_LOW + 0.01)
    gate.bar:SetValue(1)
    local warn = gate.clip:CreateTexture(nil, "OVERLAY")
    warn:SetAllPoints(t.frame)
    warn:SetTexture(MEDIA .. "ArcTrimPet")
    warn:SetBlendMode("ADD")
    warn:SetVertexColor(T.PET_LOW_COLOR[1], T.PET_LOW_COLOR[2], T.PET_LOW_COLOR[3])
    local group = warn:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local pulse = group:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.25)
    pulse:SetDuration(T.PET_LOW_PULSE)
    group:Play()
    t.low = gate
end

function UpdatePet()
    local t = trims.pet
    if not t then return end
    if not UnitExists("pet") then t.frame:Hide() return end
    t.frame:Show()
    local ok, value = pcall(UnitHealthPercent, "pet", true)
    if ok and type(value) ~= "nil" then
        SetBarValue(t.bar, value)
        if t.low then pcall(t.low.bar.SetValue, t.low.bar, value) end
    end
    local colored = false
    if A.healthCurve then
        local okColor, color = pcall(UnitHealthPercent, "pet", true, A.healthCurve)
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
    pcall(t.lowGate.SetMinMaxValues, t.lowGate, 0, max)
    pcall(t.lowGate.SetValue, t.lowGate, amount)
    pcall(t.lowFill.SetMinMaxValues, t.lowFill, 0, max)
    pcall(SetBarValue, t.lowFill, amount)
    pcall(t.track.SetValue, t.track, amount) -- (0..1: full with any shield, empty without)
    pcall(t.back.SetValue, t.back, amount)
    if absorbChanged then ShieldBurst(amount) end
end

-- Weakened Soul: found by name (every rank), else by ID. Lookups return
-- nothing for an aura the client keeps secret; a shown one then runs on
-- while the client still has a duration for its instance.
local soul = { filter = "HARMFUL" } -- (its spell: the class's lockout, set when first needed)

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
    soul.spell = soul.spell or lock.spell
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
-- While the lockout is on you, its triggers can't go on you: their cooldown
-- pulses (the Cooldown Manager's) are held back. Their icons, compared by
-- texture (readable; anything else: not held back).
function A.LockedOut(texture)
    if not (trims.soul and (soul.id or soulStart)) or Secret(texture) then return false end
    for _, id in ipairs(lock.triggers) do
        local ok, icon = pcall(C_Spell.GetSpellTexture, id)
        if ok and icon ~= nil and not Secret(icon) and icon == texture then return true end
    end
    return false
end

-- For the debuff alert (Debuffs.lua), which skips your own lockout:
-- whether a (readable) icon is its icon, and when your clock last started it
-- (in combat, where the icon is secret: the debuff that just landed with it).
function A.IsLockoutIcon(texture)
    if not lock or texture == nil or Secret(texture) then return false end
    local ok, icon = pcall(C_Spell.GetSpellTexture, lock.spell)
    return ok and icon ~= nil and not Secret(icon) and icon == texture
end

function A.LockoutStartedAt() return soulStart end

local function UpdateSoulClock()
    local t = trims.soul
    if not t then return end
    soulDuration = soulDuration or lock.duration
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

-- Your target's cast interrupted: a ring bursting round its portrait
-- (built when first needed).
function A.KickBurst()
    local s = sides.target
    if not X.kick then
        local ring = CreateFrame("Frame", nil, s.id)
        ring:SetSize(T.KICK_SIZE, T.KICK_SIZE)
        ring:SetPoint("CENTER", s.id, "CENTER")
        ring:SetFrameLevel(s.id:GetFrameLevel() + 5)
        local tex = ring:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(MEDIA .. "ArcGlow")
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(T.KICK_COLOR[1], T.KICK_COLOR[2], T.KICK_COLOR[3])
        ring:SetAlpha(0)
        local group = s.frame:CreateAnimationGroup()
        for i = 1, T.BURST_PULSES do AddPulse(group, ring, i, 1, T.KICK_SCALE) end
        X.kick = group
    end
    X.kick:Stop()
    X.kick:Play()
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
    soul.spell = soul.spell or (lock and lock.spell)
    if not soul.spell then return end
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

A.AddPart({
    Build = function()
        BuildTrims()
        BuildToT()
    end,
    Update = function(elapsed)
        UpdateTrims(elapsed)
        UpdateToT(elapsed)
    end,
    Enable = function()
        ns:On("UNIT_HEALTH", function(_, unit)
            if unit == "pet" then UpdatePet() elseif unit == "player" then UpdateShieldTrim() end
        end)
        ns:On("UNIT_MAXHEALTH", function(_, unit)
            if unit == "pet" then UpdatePet() elseif unit == "player" then UpdateShieldTrim() end
        end)
        ns:On("PLAYER_TARGET_CHANGED", UpdateCombo)
        ns:On("UNIT_AURA", function(_, unit) if unit == "player" then UpdateSoul() end end)
        ns:On("UNIT_ABSORB_AMOUNT_CHANGED", function(_, unit) if unit == "player" then UpdateShieldTrim(true) end end)
        ns:On("UNIT_PET", function(_, unit) if unit == "player" then UpdatePet() end end)
        ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
            if unit == "player" then OnSpent(spellID) elseif unit == "pet" then OnSpent(spellID, true) end
        end)
        ns:On("UNIT_SPELLCAST_SENT", function(_, unit, target, _, spellID)
            if unit == "player" then OnSent(target, spellID) end
        end)
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
        end)
    end,
})
