-- AudioDevice: game sound follows Windows' default output device. Normally the
-- game keeps the device it started with until you pick another one in the
-- sound settings.
--
-- How: the game's output device is set to "System Default" (index 0), and when
-- Windows reports a device change (VOICE_CHAT_OUTPUT_DEVICES_UPDATED, which fires
-- even with voice chat off) we restart the game's sound system so it re-picks the
-- default. Bursts of events become one restart. Never during a cinematic or
-- movie: the restart waits until it ends.
--
-- Note: we don't try to skip restarts by checking whether the default really
-- changed. With voice chat off, C_VoiceChat's device list (isSystemDefault) is
-- missing or stale, so that check silently blocked real switches.
--
-- Cost: nothing runs except on device-change events.
local _, ns = ...

local M = ns:NewModule("AudioDevice", {
    title = "Follow Default Audio Device",
    group = "General",
    desc = "Game sound switches to Windows' default output device when it changes (headset on/off, etc.), "
        .. "instead of staying on the device the game started with. Sets the game's output device to System Default.",
    defaults = { announce = true },
    options = {
        { type = "checkbox", key = "announce", name = "Message in chat when switching",
          tooltip = "Print a short line in chat each time game sound moves to the new default device." },
    },
})

local pendingRestart = false
local scheduled = false
local warnedMissing = false

local function InCinematic()
    return (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown())
end

local function RestartSound(announce)
    if InCinematic() then
        pendingRestart = true
        return
    end
    pendingRestart = false
    SetCVar("Sound_OutputDriverIndex", "0")
    if Sound_GameSystem_RestartSoundSystem then
        Sound_GameSystem_RestartSoundSystem()
        if announce and M.db.announce then
            ns:Print("game sound switched to the default output device.")
        end
    elseif not warnedMissing then
        warnedMissing = true
        ns:Print("Follow Default Audio Device: this client can't restart its sound system; switch devices in the sound settings.")
    end
end

-- Device events tend to arrive in bursts; restart once things have settled.
local function OnDevicesChanged()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.5, function()
        scheduled = false
        RestartSound(true)
    end)
end

local function OnCinematicEnded()
    if pendingRestart then RestartSound(true) end
end

function M:OnEnable()
    -- Pinned to a specific device? Switch to System Default once.
    if GetCVar("Sound_OutputDriverIndex") ~= "0" then RestartSound(false) end

    ns:On("VOICE_CHAT_OUTPUT_DEVICES_UPDATED", OnDevicesChanged)
    ns:On("CINEMATIC_STOP", OnCinematicEnded)
    ns:On("STOP_MOVIE", OnCinematicEnded)
end
