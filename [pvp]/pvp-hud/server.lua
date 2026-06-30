-- ============================================================
-- SERVER-SIDE SCOREBOARD, STAT TRACKER & KILL STREAKS
-- Session-based: stats reset per redzone/turf session.
-- ============================================================

local PlayerStats = {}

AddEventHandler('playerJoining', function()
    local src = source
    PlayerStats[src] = { kills = 0, deaths = 0, streak = 0 }
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    PlayerStats[src] = nil
end)

-- Client reports a kill (only sent when in PvP mode)
RegisterNetEvent('pvp-hud:reportKill')
AddEventHandler('pvp-hud:reportKill', function(isNpc)
    local src = source
    if not PlayerStats[src] then PlayerStats[src] = { kills = 0, deaths = 0, streak = 0 } end

    PlayerStats[src].kills = (PlayerStats[src].kills or 0) + 1
    PlayerStats[src].streak = (PlayerStats[src].streak or 0) + 1

    -- Relay as a local server event so other resources (pvp-playerlog) can listen
    -- without hitting FiveM's cross-resource net event restriction
    TriggerEvent('pvp-hud:killRecorded', src, isNpc)

    local streak = PlayerStats[src].streak
    local medal = nil
    local label = nil

    if streak == 3 then
        medal = '3k.png'; label = 'Bloodthirsty'
    elseif streak == 5 then
        medal = '5k.webp'; label = 'Killing Spree'
    elseif streak == 7 then
        medal = '7k.png'; label = 'Merciless'
    elseif streak == 10 then
        medal = '10k.png'; label = 'Fury'
    elseif streak == 15 then
        medal = '15k.webp'; label = 'Unstoppable'
    end

    if medal then
        TriggerClientEvent('pvp-hud:showStreak', src, { medal = medal, label = label, streak = streak })
    end
end)

-- Client reports a death
RegisterNetEvent('pvp-hud:reportDeath')
AddEventHandler('pvp-hud:reportDeath', function()
    local src = source

    if not PlayerStats[src] then PlayerStats[src] = { kills = 0, deaths = 0, streak = 0 } end
    PlayerStats[src].deaths = (PlayerStats[src].deaths or 0) + 1
    PlayerStats[src].streak = 0

    -- Relay as a local server event so other resources (pvp-playerlog) can listen
    TriggerEvent('pvp-hud:deathRecorded', src)
end)

-- Client requests full scoreboard
RegisterNetEvent('pvp-hud:requestScoreboard')
AddEventHandler('pvp-hud:requestScoreboard', function()
    local src = source
    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local name = GetPlayerName(id)
        local ping = GetPlayerPing(id)
        local stats = PlayerStats[id] or { kills = 0, deaths = 0, streak = 0 }
        table.insert(players, {
            source = id,
            name = name,
            kills = stats.kills,
            deaths = stats.deaths,
            streak = stats.streak,
            ping = ping
        })
    end
    TriggerClientEvent('pvp-hud:updateScoreboard', src, players)
end)

-- RESET a single player's stats (called when leaving redzone/turf/hub)
RegisterNetEvent('pvp-hud:resetMyStats')
AddEventHandler('pvp-hud:resetMyStats', function()
    local src = source
    PlayerStats[src] = { kills = 0, deaths = 0, streak = 0 }
end)
