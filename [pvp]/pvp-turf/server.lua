-- ============================================================
-- TURF WARS SERVER
-- Central authority for map rotation, player state, and sync.
-- All players share the same map, timer, and radius.
-- ============================================================

local TURF_MAPS = {
    {
        name    = "Opium",
        center  = vector3(-227.6676, -2637.3149, 6.0003),
        heading = 15.9969,
        radius  = 48.0,
    },
    {
        name    = "Downtown",
        center  = vector3(418.3982, -1516.1631, 29.2915),
        heading = 211.6687,
        radius  = 65.0,
    },
    {
        name    = "Skate Park",
        center  = vector3(-3380.7390, 1201.8765, 1568.5350),
        heading = 14.5679,
        radius  = 34.0,
    },
    {
        name    = "Racetrack",
        center  = vector3(983.3310, 2343.9822, 52.3554),
        heading = 3.7594,
        radius  = 37.0,
    },
    {
        name    = "Junkyard",
        center  = vector3(5367.5483, -1103.1309, 355.2091),
        heading = 0.6554,
        radius  = 39.0,
    },
    {
        name    = "Nuketown",
        center  = vector3(-3250.5637, 7009.4507, 637.6183),
        heading = 14.5679,
        radius  = 38.0,
    },
}

local CONFIG = {
    defaultRadius = 50.0,
    minRadius     = 10.0,
    maxRadius     = 200.0,
    mapDuration   = 120,
}

local TURF = {
    active         = false,
    players        = {},
    currentMap     = 1,
    mapOrder       = {},
    mapOrderPos    = 0,
    radius         = CONFIG.defaultRadius,
    mapStartTime   = 0,
    timerThread    = nil,
    slomoTriggered = false,
}

-- ============================================================
-- MAP ORDER RANDOMISER
-- ============================================================

local function ShuffleMaps(avoidFirst)
    local indices = {}
    for i = 1, #TURF_MAPS do indices[i] = i end
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end
    if avoidFirst and #indices > 1 and indices[1] == avoidFirst then
        local swapWith = math.random(2, #indices)
        indices[1], indices[swapWith] = indices[swapWith], indices[1]
    end
    return indices
end

local function AdvanceMapOrder()
    TURF.mapOrderPos = TURF.mapOrderPos + 1
    if TURF.mapOrderPos > #TURF.mapOrder then
        local lastPlayed = TURF.mapOrder[#TURF.mapOrder]
        TURF.mapOrder    = ShuffleMaps(lastPlayed)
        TURF.mapOrderPos = 1
    end
    return TURF.mapOrder[TURF.mapOrderPos]
end

-- ============================================================
-- HELPERS
-- ============================================================

local function GetCurrentMapData()
    local map = TURF_MAPS[TURF.currentMap]
    return {
        index      = TURF.currentMap,
        name       = map.name,
        center     = map.center,
        heading    = map.heading,
        radius     = TURF.radius,
        baseRadius = map.radius or CONFIG.defaultRadius,
    }
end

local function BroadcastToPlayers(event, ...)
    for src, _ in pairs(TURF.players) do
        TriggerClientEvent(event, src, ...)
    end
end

local function Notify(src, msg)
    TriggerClientEvent('chat:addMessage', src, {
        color = {255, 200, 50},
        args  = {"[TURF]", msg}
    })
end

-- ============================================================
-- MAP TIMER
-- ============================================================

local function StartMapTimer()
    if TURF.timerThread then return end
    TURF.timerThread = Citizen.CreateThread(function()
        TURF.slomoTriggered = false
        while TURF.active do
            Citizen.Wait(1000)
            if not TURF.active then break end

            local elapsed   = (GetGameTimer() - TURF.mapStartTime) / 1000
            local remaining = CONFIG.mapDuration - elapsed

            if remaining <= 30 and remaining > 29 then
                BroadcastToPlayers('turfwars:notify', "~r~30 seconds ~w~until next map!")
            end

            if remaining <= 3 and not TURF.slomoTriggered then
                TURF.slomoTriggered = true
                BroadcastToPlayers('turfwars:slomoStart')
            end

            if elapsed >= CONFIG.mapDuration then
                TURF.slomoTriggered = false

                -- NEW: fire round-end signal BEFORE rotating, so listeners
                -- (e.g. pvp-economy) see the player list for the round that
                -- just finished, not the new one.
                local roundPlayers = {}
                for src, _ in pairs(TURF.players) do
                    table.insert(roundPlayers, src)
                end
                TriggerEvent('pvp-turf:internalRoundEnded', roundPlayers, TURF_MAPS[TURF.currentMap].name)

                local nextIndex = AdvanceMapOrder()
                TURF.currentMap   = nextIndex
                TURF.mapStartTime = GetGameTimer()
                TURF.radius       = TURF_MAPS[nextIndex].radius or CONFIG.defaultRadius

                BroadcastToPlayers('turfwars:mapChanged', GetCurrentMapData())
                Citizen.Wait(2000)
                BroadcastToPlayers('turfwars:loadMap', GetCurrentMapData())
            end

            BroadcastToPlayers('turfwars:timerSync', math.max(0, remaining), TURF_MAPS[TURF.currentMap].name)
        end
        TURF.timerThread = nil
    end)
end

local function StopTurfWars()
    TURF.active         = false
    TURF.players        = {}
    TURF.mapOrderPos    = 0
    TURF.mapOrder       = {}
    TURF.slomoTriggered = false
    TURF.timerThread    = nil
end

-- ============================================================
-- EVENTS
-- ============================================================

RegisterNetEvent('turfwars:requestJoin')
AddEventHandler('turfwars:requestJoin', function()
    local src = source
    if TURF.players[src] then return end

    if not TURF.active then
        TURF.active       = true
        TURF.mapOrder     = ShuffleMaps(nil)
        TURF.mapOrderPos  = 1
        TURF.currentMap   = TURF.mapOrder[1]
        TURF.radius       = TURF_MAPS[TURF.currentMap].radius or CONFIG.defaultRadius
        TURF.mapStartTime = GetGameTimer()
    end

    TURF.players[src] = true
    TriggerClientEvent('turfwars:enterConfirmed', src, GetCurrentMapData())

    if not TURF.timerThread then
        StartMapTimer()
    end
end)

RegisterNetEvent('turfwars:requestLeave')
AddEventHandler('turfwars:requestLeave', function()
    local src = source
    if not TURF.players[src] then
        -- Still tell client to clean up in case client thinks it's active
        TriggerClientEvent('turfwars:leaveConfirmed', src)
        return
    end

    TURF.players[src] = nil
    TriggerClientEvent('turfwars:leaveConfirmed', src)

    local count = 0
    for _, _ in pairs(TURF.players) do count = count + 1 end
    if count == 0 then
        StopTurfWars()
    end
end)

RegisterNetEvent('turfwars:requestRespawn')
AddEventHandler('turfwars:requestRespawn', function()
    local src = source
    if not TURF.players[src] then return end
    TriggerClientEvent('turfwars:respawnApproved', src, GetCurrentMapData())
end)

-- ============================================================
-- COMMANDS
-- ============================================================

-- Same "pvpadmin" ACE permission used by pvp-admintools. Round-control
-- commands (force-end, radius override) affect everyone in the session,
-- so they're admin-gated rather than open to any player in turf wars.
-- Grant in server.cfg, e.g.:
--   add_ace identifier.license:f75dc9b6... pvpadmin allow
--   add_principal identifier.license:f75dc9b6... group.admin
--   add_ace group.admin pvpadmin allow
local function IsAuthorized(src)
    return IsPlayerAceAllowed(src, "pvpadmin")
end

RegisterCommand("endturf", function(source, args, rawCommand)
    if not IsAuthorized(source) then
        Notify(source, "You don't have permission to use this command (missing 'pvpadmin' ACE).")
        return
    end
    if not TURF.active then
        Notify(source, "Not in Turf Wars.")
        return
    end
    if not TURF.players[source] then
        Notify(source, "You are not in Turf Wars.")
        return
    end

    Notify(source, "Ending current turf...")

    Citizen.CreateThread(function()
        Citizen.Wait(1500)

        -- NEW: same round-end signal as the natural timer rotation
        local roundPlayers = {}
        for src, _ in pairs(TURF.players) do
            table.insert(roundPlayers, src)
        end
        TriggerEvent('pvp-turf:internalRoundEnded', roundPlayers, TURF_MAPS[TURF.currentMap].name)

        local nextIndex = AdvanceMapOrder()
        TURF.currentMap     = nextIndex
        TURF.mapStartTime   = GetGameTimer()
        TURF.radius         = TURF_MAPS[nextIndex].radius or CONFIG.defaultRadius
        TURF.slomoTriggered = false

        BroadcastToPlayers('turfwars:mapChanged', GetCurrentMapData())
        Citizen.Wait(2000)
        BroadcastToPlayers('turfwars:loadMap', GetCurrentMapData())
    end)
end, false)

RegisterCommand("turfradius", function(source, args, rawCommand)
    if not IsAuthorized(source) then
        Notify(source, "You don't have permission to use this command (missing 'pvpadmin' ACE).")
        return
    end
    if not TURF.active then
        Notify(source, "Not in Turf Wars.")
        return
    end
    if not TURF.players[source] then
        Notify(source, "You are not in Turf Wars.")
        return
    end

    local n = tonumber(args[1])
    if not n then
        Notify(source, "Usage: /turfradius <number>   e.g. /turfradius 50")
        return
    end

    n = math.max(CONFIG.minRadius, math.min(CONFIG.maxRadius, n))
    TURF.radius = n
    BroadcastToPlayers('turfwars:radiusChanged', n)
    Notify(source, string.format("Turf radius set to ~y~%.0fm", n))
end, false)

RegisterCommand("leaveturfwars", function(source, args, rawCommand)
    if not TURF.players[source] then
        Notify(source, "You are not in Turf Wars.")
        return
    end
    TURF.players[source] = nil
    TriggerClientEvent('turfwars:leaveConfirmed', source)
    TriggerClientEvent('chat:addMessage', source, {
        color = {100, 200, 255},
        args  = {"[TURF]", "Use /hub to return to the Hub."}
    })

    local count = 0
    for _, _ in pairs(TURF.players) do count = count + 1 end
    if count == 0 then
        StopTurfWars()
    end
end, false)

-- ============================================================
-- EXPORTS (for other resources, e.g. pvp-economy, to verify
-- real server-side state instead of trusting client claims)
-- ============================================================

exports('IsPlayerInTurf', function(src)
    return TURF.players[src] == true
end)

exports('IsTurfActive', function()
    return TURF.active
end)

exports('GetTurfPlayerCount', function()
    local count = 0
    for _, _ in pairs(TURF.players) do count = count + 1 end
    return count
end)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function(reason)
    local src = source
    if TURF.players[src] then
        TURF.players[src] = nil
        local count = 0
        for _, _ in pairs(TURF.players) do count = count + 1 end
        if count == 0 then
            StopTurfWars()
        end
    end
end)