-- ============================================================
-- PVP LEADERBOARD — SERVER
-- Polls pvp-playerlog every 10 seconds and broadcasts the
-- top-3 global-kill leaders + their FULL saved PedMngr
-- appearance data to all clients. Clothing is ALWAYS shown
-- regardless of whether the player is currently online.
-- ============================================================

local REFRESH_INTERVAL = 10000
local PEDMNGR_RESOURCE = 'PedMngr'

-- ============================================================
-- HELPERS
-- ============================================================

local function GetPlayerDbId(src)
    for _, resName in ipairs({'player-data', 'cfx-server-data.player-data'}) do
        local ok, dbId = pcall(function() return exports[resName].getPlayerId(src) end)
        if ok and dbId then return tonumber(dbId) end
    end
    local ok, dbId = pcall(function()
        return exports['cfx.re/playerData.v1alpha1'].getPlayerId(src)
    end)
    if ok and dbId then return tonumber(dbId) end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:') == 1 then
            local hash = 0
            for i = 1, #id do
                hash = ((hash << 5) - hash) + id:byte(i)
                hash = hash & 0xFFFFFFFF
            end
            return hash
        end
    end
    return nil
end

local function GetAppearanceByDbId(dbId)
    if not dbId then return nil end
    local ok, appearance = pcall(function()
        return exports[PEDMNGR_RESOURCE]:GetAppearanceByDbId(dbId)
    end)
    if ok and appearance then return appearance end
    return nil
end

-- Build the enriched top-3 payload by attaching appearance data.
-- DEDUP: if the same player appears twice, keep only the first.
local function BuildTop3()
    local ok, rawTop3 = pcall(function()
        return exports['pvp-playerlog']:GetLeaderboardKills(3)
    end)
    if not ok or not rawTop3 then return nil end

    local seenDbIds = {}
    local top3 = {}
    for _, entry in ipairs(rawTop3) do
        local dbId = entry.dbId and tonumber(entry.dbId) or nil
        if not dbId and entry.src and GetPlayerName(entry.src) then
            dbId = GetPlayerDbId(entry.src)
        elseif not dbId and entry.license then
            local licOk, lid = pcall(function()
                return exports['pvp-playerlog']:LicenseToDbId(entry.license)
            end)
            if licOk and lid then dbId = lid end
        end
        entry.dbId = dbId
        entry.appearance = GetAppearanceByDbId(dbId)

        if dbId and not seenDbIds[dbId] then
            seenDbIds[dbId] = true
            table.insert(top3, entry)
        end
    end

    for i = 1, math.min(3, #top3) do
        top3[i].rank = i
    end

    return top3
end

-- ============================================================
-- BROADCAST LOOP
-- ============================================================

CreateThread(function()
    Wait(5000)
    while true do
        -- IMPORTANT: this whole body is pcall-wrapped on purpose. In FiveM,
        -- an uncaught error inside a 'while true ... Wait() ... end' thread
        -- permanently kills that thread -- the loop just stops forever,
        -- silently, until the resource is restarted. Everything else in
        -- the resource keeps running fine, which is exactly the kind of
        -- "leaderboard stopped updating but nothing else looks broken"
        -- symptom this is meant to catch. If this ever fires, the print
        -- below will tell you exactly what broke instead of just going dark.
        local ok, err = pcall(function()
            local top3 = BuildTop3()
            if top3 then
                TriggerClientEvent('pvp-leaderboard:update', -1, top3)
            else
                print('[PVP-LEADERBOARD] Could not fetch leaderboard from pvp-playerlog')
            end
        end)
        if not ok then
            print('[PVP-LEADERBOARD] Broadcast loop error (recovered, will retry): ' .. tostring(err))
        end
        Wait(REFRESH_INTERVAL)
    end
end)

-- Immediate refresh on client request
RegisterNetEvent('pvp-leaderboard:requestRefresh')
AddEventHandler('pvp-leaderboard:requestRefresh', function()
    local ok, err = pcall(function()
        local top3 = BuildTop3()
        if top3 then
            TriggerClientEvent('pvp-leaderboard:update', -1, top3)
        end
    end)
    if not ok then
        print('[PVP-LEADERBOARD] requestRefresh error: ' .. tostring(err))
    end
end)
