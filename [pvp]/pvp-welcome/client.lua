-- ============================================================
-- PVP WELCOME — CLIENT
-- First-load welcome screen + command reference.
-- Auto-shows ONCE per session, the first time you land in the
-- hub. Reopen any time with /welcome or /info.
--
-- ============================================================
-- EDIT THIS BLOCK WITH YOUR OWN SERVER INFO
-- ============================================================

local CONFIG = {
    serverName    = "Smerkish PvP",
    tagline       = "Fast-paced arena PvP. New modes always in the works.",
    discordUrl    = "https://discord.gg/QFku2sVvR",
    discordLabel  = "discord.gg/SmerkishPvP",

    modes = {
        {
            title = "Turf Wars",
            desc  = "Fight Players in the zone n Earn Money to Gear up. Map rotation is still being tuned during beta.",
        },
        {
            title = "Redzone",
            desc  = "Straight deathmatch, Fight untill your death...",
        },
    },

    -- Shown in the commands grid. Keep these in sync if you add more.
    -- Entries with `key` render as a keycap (for real keybinds, via
    -- RegisterKeyMapping). Entries with `cmd` render as a typed command.
    commands = {
        { cmd = "/register",      desc = "Open character customization & clothing menu" },
        { cmd = "/hub",           desc = "Return to the Hub from anywhere" },
        { cmd = "/streaks",       desc = "Toggle kill streak medal popups" },
        { cmd = "/hitmark",       desc = "Toggle hit markers (red = body, gold = headshot)" },
        { cmd = "/death",         desc = "Respawn if you ever get stuck" },
    },
}

-- ============================================================
-- STATE
-- ============================================================

local hasShownThisSession = false
local isOpen = false

-- ============================================================
-- OPEN / CLOSE
-- ============================================================

local function OpenWelcome()
    if isOpen then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "open",
        config = CONFIG
    })
end

local function CloseWelcome()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
end

-- ============================================================
-- BLOCK THE NATIVE PAUSE MENU WHILE WE HAVE FOCUS
-- (same pattern pvp-turf uses for its arsenal menu, so ESC
-- closes OUR panel instead of also popping the game's own
-- pause menu underneath it)
-- ============================================================

CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 200, true)  -- INPUT_FRONTEND_PAUSE
            DisableControlAction(0, 322, true)  -- INPUT_FRONTEND_PAUSE_ALTERNATE
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- ============================================================
-- NUI CALLBACKS
-- ============================================================

RegisterNUICallback("closeWelcome", function(_, cb)
    CloseWelcome()
    cb({})
end)

-- ============================================================
-- AUTO-SHOW ONCE PER SESSION, ON FIRST HUB SPAWN
-- ============================================================

AddEventHandler("pvp-core:stateChanged", function(newState)
    if newState == "hub" and not hasShownThisSession then
        hasShownThisSession = true
        Wait(800) -- let the hub fade-in finish first, don't slam it on top
        OpenWelcome()
    end
end)

-- ============================================================
-- MANUAL REOPEN
-- ============================================================

RegisterCommand("welcome", function()
    OpenWelcome()
end, false)

RegisterCommand("info", function()
    OpenWelcome()
end, false)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then
        SetNuiFocus(false, false)
    end
end)
