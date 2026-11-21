-- Dev: small helpers for working on KuroKit itself.
--   /rl                      reload the UI
--   /kk dev spikes [sec]     frame spike finder (also a button in the settings)
local _, ns = ...

-- Declared first: the button's onClick below refers to M, and a local isn't in
-- scope inside its own initializer.
local M
M = ns:NewModule("Dev", {
    title = "Developer Tools",
    group = "Developer",
    desc = "/rl reloads the UI; Lua error popups; a frame spike finder.",
    options = {
        { type = "checkbox", name = "Show Lua error popups", default = false,
          tooltip = "Show a popup when an addon causes a Lua error (game setting scriptErrors).",
          get = function() return GetCVarBool("scriptErrors") end,
          set = function(value) SetCVar("scriptErrors", value and "1" or "0") end },
        { type = "button", name = "Frame spike finder", text = "Run 20 s",
          tooltip = "Watches every frame for 20 seconds, then prints in chat which addons were busiest "
              .. "during the slowest frames and whether those lined up with Lua garbage collection.",
          onClick = function() M:FindSpikes(20) end },
    },
})

function M:OnEnable()
    SLASH_KUROKIT_RELOAD1 = "/rl"
    SlashCmdList.KUROKIT_RELOAD = ReloadUI
end

---------------------------------------------------------------------------
-- Frame spike finder. Uses Blizzard's addon profiler (C_AddOnProfiler):
-- per-addon time in the last frame, and counters of frames over 5/10 ms.
-- Sampling ~100 addons every frame costs a little, so KuroKit's own numbers
-- are inflated while it runs; it's excluded from the "busiest" columns.
---------------------------------------------------------------------------
local scanner

local function Num(v) -- 12.x secret values can't be compared; treat as 0
    if issecretvalue and issecretvalue(v) then return 0 end
    return v or 0
end

local SLOW_MS = 25          -- a "slow frame" for the GC correlation
local GC_DROP_KB = 32       -- net memory fall in one frame that means collection is running
local GC_GAP_FRAMES = 60    -- collecting frames closer than this belong to one cycle

local function Report(addons, worst, s)
    local P, Metric = C_AddOnProfiler, Enum.AddOnProfilerMetric
    local seconds = math.max(s.elapsed, 0.001)
    ns:Print(("Spike finder: %d frames in %.0f s, average %.1f ms."):format(s.frames, seconds, s.totalMs / math.max(s.frames, 1)))
    print(("  Lua memory %.0f -> %.0f MB; allocating at least %.1f MB/s; %d garbage collection cycle(s)."):format(
        s.memStart / 1024, s.memEnd / 1024, s.allocated / 1024 / seconds, s.gcCycles))
    if s.slow > 0 then
        print(("  %d frame(s) over %d ms; %d of them during garbage collection (vs %.0f%% of all frames)."):format(
            s.slow, SLOW_MS, s.slowInGC, 100 * s.gcFrames / math.max(s.frames, 1)))
    end

    print("  Slowest frames:  at s | frame ms | all addons ms | busiest addon")
    for _, w in ipairs(worst) do
        print(("    %5.1f | %5.1f | %5.1f | %s %.1f%s"):format(w.at, w.ms, w.addons, w.top or "-", w.topMs,
            w.gc and "  (during garbage collection)" or ""))
    end

    for _, a in ipairs(addons) do
        a.slow5 = Num(P.GetAddOnMetric(a.name, Metric.CountTimeOver5Ms)) - a.over5
        a.slow10 = Num(P.GetAddOnMetric(a.name, Metric.CountTimeOver10Ms)) - a.over10
    end
    table.sort(addons, function(x, y) return x.slow5 > y.slow5 or (x.slow5 == y.slow5 and x.max > y.max) end)
    print("  Addons with slow frames (>5 ms / >10 ms) and their worst single frame:")
    local shown = 0
    for _, a in ipairs(addons) do
        if shown < 6 and (a.slow5 > 0 or a.max >= 2) and a.name ~= ns.name then
            print(("    %s: %d / %d, worst %.1f ms"):format(a.name, a.slow5, a.slow10, a.max))
            shown = shown + 1
        end
    end
    if shown == 0 then print("    none: no addon went over 5 ms or 2 ms peak") end

    -- Memory per addon (one-off; UpdateAddOnMemoryUsage itself causes a short hitch).
    UpdateAddOnMemoryUsage()
    for _, a in ipairs(addons) do a.mem = Num(GetAddOnMemoryUsage(a.name)) end
    table.sort(addons, function(x, y) return x.mem > y.mem end)
    local parts = {}
    for i = 1, math.min(6, #addons) do
        parts[#parts + 1] = ("%s %.0f MB"):format(addons[i].name, addons[i].mem / 1024)
    end
    print("  Most Lua memory: " .. table.concat(parts, ", "))

    local w = worst[1]
    if w and w.addons < w.ms * 0.25 then
        local gcShare = s.slow > 0 and s.slowInGC / s.slow or 0
        local baseShare = s.gcFrames / math.max(s.frames, 1)
        if s.slow >= 3 and gcShare >= 0.6 and gcShare > baseShare * 2 then
            print("  -> The slow frames line up with Lua garbage collection. Big data addons (see memory) make each collection expensive.")
        else
            print("  -> Addon code used little of the slowest frames, and they don't line up with garbage collection: "
                .. "most likely the game itself (streaming, shaders, rendering).")
        end
    end
end

function M:FindSpikes(seconds)
    local P, Metric = C_AddOnProfiler, Enum.AddOnProfilerMetric
    if scanner then ns:Print("The spike finder is already running.") return end
    if not (P and P.IsEnabled and P.IsEnabled()) then
        ns:Print("Blizzard's addon profiler isn't available, so the spike finder can't run.")
        return
    end
    seconds = tonumber(seconds) or 20

    local addons = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(i) then
            local name = C_AddOns.GetAddOnInfo(i)
            addons[#addons + 1] = {
                name = name, max = 0,
                over5 = Num(P.GetAddOnMetric(name, Metric.CountTimeOver5Ms)),
                over10 = Num(P.GetAddOnMetric(name, Metric.CountTimeOver10Ms)),
            }
        end
    end
    local n, self_ = #addons, ns.name
    local worst = {} -- the 5 slowest frames, slowest first
    local s = {
        elapsed = 0, frames = 0, totalMs = 0, allocated = 0,
        gcCycles = 0, gcFrames = 0, lastCollect = -math.huge, slow = 0, slowInGC = 0,
        memStart = collectgarbage("count"),
    }
    local lastMem = s.memStart

    ns:Print(("Spike finder: watching for %d seconds, play normally..."):format(seconds))
    scanner = CreateFrame("Frame")
    local function Step(frame, dt)
        s.elapsed = s.elapsed + dt
        s.frames = s.frames + 1
        local ms = dt * 1000
        s.totalMs = s.totalMs + ms

        -- Memory: rises = allocation; a net fall = the collector is sweeping.
        local mem = collectgarbage("count")
        local delta = mem - lastMem
        lastMem = mem
        if delta > 0 then s.allocated = s.allocated + delta end
        if delta < -GC_DROP_KB then
            if s.frames - s.lastCollect > GC_GAP_FRAMES then s.gcCycles = s.gcCycles + 1 end
            s.lastCollect = s.frames
        end
        local inGC = s.frames - s.lastCollect <= 3
        if inGC then s.gcFrames = s.gcFrames + 1 end
        if ms >= SLOW_MS then
            s.slow = s.slow + 1
            if inGC then s.slowInGC = s.slowInGC + 1 end
        end

        local top, topMs = nil, 0
        for i = 1, n do
            local a = addons[i]
            local t = Num(P.GetAddOnMetric(a.name, Metric.LastTime))
            if t > a.max then a.max = t end
            if t > topMs and a.name ~= self_ then top, topMs = a.name, t end
        end

        if #worst < 5 or ms > worst[#worst].ms then
            local entry = { at = s.elapsed, ms = ms, addons = Num(P.GetOverallMetric(Metric.LastTime)),
                            top = top, topMs = topMs, gc = inGC }
            local pos = #worst + 1
            for i = 1, #worst do
                if ms > worst[i].ms then pos = i; break end
            end
            table.insert(worst, pos, entry)
            if #worst > 5 then worst[6] = nil end
        end

        if s.elapsed >= seconds then
            frame:SetScript("OnUpdate", nil)
            scanner = nil
            s.memEnd = collectgarbage("count")
            Report(addons, worst, s)
        end
    end
    scanner:SetScript("OnUpdate", function(frame, dt)
        if not ns.safecall(Step, frame, dt) then -- stop on error instead of repeating it every frame
            frame:SetScript("OnUpdate", nil)
            scanner = nil
        end
    end)
end

function M:OnSlash(args)
    local cmd, arg = args:match("^(%S*)%s*(.-)$")
    if cmd == "spikes" then
        self:FindSpikes(arg)
    else
        ns:Print("/kk dev spikes [seconds] - frame spike finder")
    end
end
