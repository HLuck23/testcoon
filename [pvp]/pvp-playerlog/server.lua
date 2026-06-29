-- ============================================================
-- PVP PLAYER LOG
-- Persistent per-player record: license, username, money,
-- weapons owned, turf kills, turf wins, global kills, global deaths.
-- K/D calculated on demand. Leaderboard exports are server-validated.
-- ============================================================

local KVP_RECORD = 'pvplog:player:%s'

local function GetWebhook()
    return GetConvar('turfwars_playerlog_webhook', '')
end

-- ============================================================
-- IDENTITY
-- ============================================================

local function GetPlayerDbId(src)
    for _, resName in ipairs({'player-data', 'cfx-server-data.player-data'}) do
        local ok, dbId = pcall(function()
            return exports[resName].getPlayerId(src)
        end)
        if ok and dbId then return tonumber(dbId) end
    end
    local ok, dbId = pcall(function()
        return exports['cfx.re/playerData.v1alpha1'].getPlayerId(src)
    end)
    if ok and dbId then return tonumber(dbId) end
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
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

local function GetPlayerDiscordId(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if id:find('discord:') == 1 then
            return id:sub(9) -- raw snowflake, no prefix
        end
    end
    return nil
end

local function GetPlayerLicense(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if id:find('license:') == 1 then return id end
    end
    return "unknown"
end

-- License-to-dbId hash (same logic as GetPlayerDbId fallback)
local function LicenseToDbId(licenseIdentifier)
    local full = licenseIdentifier
    if full:find('license:') ~= 1 then
        full = 'license:' .. full
    end
    local hash = 0
    for i = 1, #full do
        hash = ((hash << 5) - hash) + full:byte(i)
        hash = hash & 0xFFFFFFFF
    end
    return hash
end

exports('LicenseToDbId', LicenseToDbId)

local function DiscordLog(message)
    print(("[PVP-PLAYERLOG] %s"):format(message))
    local webhook = GetWebhook()
    if webhook == "" then return end
    PerformHttpRequest(webhook, function(statusCode, _, _)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(("[PVP-PLAYERLOG] Discord webhook failed, status: %s"):format(tostring(statusCode)))
        end
    end, "POST", json.encode({ content = message }), { ["Content-Type"] = "application/json" })
end

-- ============================================================
-- RECORD: load / save
-- ============================================================

local RecordCache = {}

local function DefaultRecord(license, username)
    return {
        license      = license,
        lastUsername = username,
        discordId    = nil,
        money        = 0,
        weaponsOwned = {},
        kills        = 0,
        wins         = 0,
        globalKills  = 0,
        globalDeaths = 0,
        lastUpdated  = nil,
    }
end

local function LoadRecord(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return DefaultRecord(GetPlayerLicense(src), GetPlayerName(src)) end
    local saved = GetResourceKvpString(KVP_RECORD:format(dbId))
    if saved then
        local ok, decoded = pcall(json.decode, saved)
        if ok and type(decoded) == 'table' then
            decoded.globalKills  = decoded.globalKills  or 0
            decoded.globalDeaths = decoded.globalDeaths or 0
            decoded.wins         = decoded.wins         or 0
            return decoded
        end
    end
    return DefaultRecord(GetPlayerLicense(src), GetPlayerName(src))
end

local function SaveRecord(src, record)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    record.lastUpdated = os.date('!%Y-%m-%dT%H:%M:%SZ')
    SetResourceKvp(KVP_RECORD:format(dbId), json.encode(record))
end

local function GetRecord(src)
    if not RecordCache[src] then RecordCache[src] = LoadRecord(src) end
    return RecordCache[src]
end

local function CalcKD(record)
    local d = record.globalDeaths or 0
    local k = record.globalKills  or 0
    if d == 0 then return k > 0 and k or 0.0 end
    return math.floor((k / d) * 100) / 100
end

-- ============================================================
-- SYNC + LOG
-- ============================================================

local function SyncAndLog(src, reason)
    local record = GetRecord(src)
    record.lastUsername = GetPlayerName(src)
    record.license      = GetPlayerLicense(src)

    -- Always update Discord ID if available (may not have been set on first load)
    local discordId = GetPlayerDiscordId(src)
    if discordId then record.discordId = discordId end

    local ok1, money = pcall(function() return exports['pvp-economy']:GetMoney(src) end)
    if ok1 and money then record.money = money end

    local ok2, owned = pcall(function() return exports['pvp-shop']:GetOwnedWeapons(src) end)
    if ok2 and owned then
        local list = {}
        for weaponHash, isOwned in pairs(owned) do
            if isOwned then list[#list + 1] = weaponHash end
        end
        record.weaponsOwned = list
    end

    RecordCache[src] = record
    SaveRecord(src, record)

    DiscordLog(("📋 **%s** (%s)\n> Money: $%s | Turf Kills: %d | Wins: %d | Weapons: %d\n> Reason: %s")
        :format(record.lastUsername, record.license, tostring(record.money),
                record.kills, record.wins, #record.weaponsOwned, reason))
end

-- ============================================================
-- GLOBAL KILL / DEATH TRACKING
-- ============================================================
-- IMPORTANT: globalKills/globalDeaths are now written ONLY from
-- pvp-core's internalKillRecorded/internalDeathRecorded events
-- (gated by pvp-core's own PlayerState ~= "hub", the same check
-- that gates pvp-core's Discord kill-feed webhook -- proven
-- reliable since that webhook fires correctly).
--
-- Previously these were written from pvp-hud:killRecorded /
-- deathRecorded instead, which is gated by a SEPARATE local flag
-- (ShowHUD) in pvp-hud, toggled via its own copy of the
-- pvp-core:stateChanged listener. The two gates usually line up,
-- but pvp-core's kill-feed firing was never actual proof that
-- pvp-hud's independent pipeline had also fired and updated this
-- data -- they're two different systems reading/writing the same
-- field. That's the root cause of the leaderboard / /pvptop /
-- appearance staleness despite the webhook looking correct: the
-- webhook reads globalKills right after a different, unrelated
-- event whose own handler (below, in TURF KILLS) only ever
-- touched the separate round-based `kills` counter -- never this
-- one. pvp-hud's PlayerStats (session scoreboard, streaks) is
-- untouched by this change and keeps working exactly as before.
-- ============================================================

AddEventHandler('pvp-core:internalDeathRecorded', function(src)
    if not src or not GetPlayerName(src) then return end
    local record = GetRecord(src)
    record.globalDeaths = (record.globalDeaths or 0) + 1
    RecordCache[src] = record
    SaveRecord(src, record)
end)

-- ============================================================
-- TURF KILLS
-- ============================================================

local RoundKills = {}

AddEventHandler('pvp-core:internalKillRecorded', function(src, killerName, victimName, weaponCategory, isHeadshot)
    if not src or not GetPlayerName(src) then return end
    local record = GetRecord(src)
    record.kills       = (record.kills or 0) + 1
    record.globalKills = (record.globalKills or 0) + 1
    RecordCache[src] = record
    SaveRecord(src, record)
    RoundKills[src] = (RoundKills[src] or 0) + 1
end)

-- ============================================================
-- TURF WINS
-- ============================================================

AddEventHandler('pvp-turf:internalRoundEnded', function(roundPlayerIds, mapName)
    if not roundPlayerIds or #roundPlayerIds == 0 then return end

    local scoreboard = {}
    for _, src in ipairs(roundPlayerIds) do
        if GetPlayerName(src) then
            scoreboard[#scoreboard + 1] = { src = src, kills = RoundKills[src] or 0 }
        end
    end

    table.sort(scoreboard, function(a, b) return a.kills > b.kills end)

    if #scoreboard > 0 and scoreboard[1].kills > 0 then
        local winnerSrc = scoreboard[1].src
        local record = GetRecord(winnerSrc)
        record.wins = (record.wins or 0) + 1
        RecordCache[winnerSrc] = record
        SaveRecord(winnerSrc, record)
    end

    for _, src in ipairs(roundPlayerIds) do
        RoundKills[src] = nil
    end

    for _, src in ipairs(roundPlayerIds) do
        if GetPlayerName(src) then
            SyncAndLog(src, ("round ended on %s (%d players)"):format(tostring(mapName), #roundPlayerIds))
        end
    end
end)

-- ============================================================
-- SHOP PURCHASE SYNC
-- ============================================================

AddEventHandler('pvp-shop:purchaseWeapon', function(weaponHash)
    local src = source
    if not src or not GetPlayerName(src) then return end
    SetTimeout(500, function()
        if GetPlayerName(src) then
            SyncAndLog(src, ("purchased weapon %s"):format(tostring(weaponHash)))
        end
    end)
end)

-- ============================================================
-- CONNECT / DISCONNECT
-- ============================================================

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    CreateThread(function()
        Wait(1000)
        if not GetPlayerName(src) then return end

        local newLicense = GetPlayerLicense(src)
        -- FIX (stats "frozen" until reconnect): GetPlayerLicense() returns the
        -- literal placeholder "unknown" when no license identifier has resolved
        -- yet — it is NOT a real, unique identity. Treating it as one meant that
        -- if a newly-connecting player (or anyone already cached) hadn't had
        -- their license resolve yet, this cleanup would match "unknown" ==
        -- "unknown" and wipe out a COMPLETELY DIFFERENT, already-connected
        -- player's live RecordCache entry. That player's kills/deaths kept
        -- incrementing in memory afterward, but GetLeaderboardKills/Deaths below
        -- stopped seeing them (record gone from RecordCache) until a reconnect
        -- forced a clean reload from KVP — exactly the "kills don't update until
        -- I leave/rejoin" symptom. Only run the cleanup with a real license.
        if newLicense:find('license:') == 1 then
            for staleSrc, record in pairs(RecordCache) do
                if staleSrc ~= src and record.license == newLicense then
                    RecordCache[staleSrc] = nil
                end
            end
        end

        SyncAndLog(src, "player connected")
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if RecordCache[src] then
        SyncAndLog(src, "player disconnected")
    end
    RecordCache[src] = nil
end)

RegisterNetEvent('pvp-playerlog:requestSync')
AddEventHandler('pvp-playerlog:requestSync', function(reason)
    local src = source
    SyncAndLog(src, reason or "manual sync")
end)

-- ============================================================
-- LEADERBOARD EXPORTS (ONLINE + OFFLINE, DEDUPED BY DBID + LICENSE)
-- ============================================================

local function BuildLeaderboardResults(seenDbIds, seenLicenses, results, src, record, dbId)
    if not dbId then return end
    if seenDbIds[dbId] then return end
    if record.license and seenLicenses[record.license] then return end

    seenDbIds[dbId] = true
    if record.license then seenLicenses[record.license] = true end
    results[#results + 1] = {
        src          = src,
        dbId         = dbId,
        name         = record.lastUsername,
        license      = record.license,
        globalKills  = record.globalKills or 0,
        globalDeaths = record.globalDeaths or 0,
        kd           = CalcKD(record),
    }
end

exports('GetLeaderboardKills', function(limit)
    limit = limit or 10
    local seenDbIds = {}
    local seenLicenses = {}
    local results = {}

    -- Online players from RecordCache
    -- CRITICAL: skip stale entries where GetPlayerName returns nil
    for src, record in pairs(RecordCache) do
        if not GetPlayerName(src) then goto continue end
        local dbId = GetPlayerDbId(src)
        if not dbId and record.license then
            dbId = LicenseToDbId(record.license)
        end
        BuildLeaderboardResults(seenDbIds, seenLicenses, results, src, record, dbId)
        ::continue::
    end

    -- Offline players from KVP
    local prefix = KVP_RECORD:format('')
    local handle = StartFindKvp(prefix)
    if handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not key then break end
            local dbIdStr = key:sub(#prefix + 1)
            local dbId = tonumber(dbIdStr)
            if dbId and not seenDbIds[dbId] then
                local saved = GetResourceKvpString(key)
                if saved then
                    local ok, record = pcall(json.decode, saved)
                    if ok and type(record) == 'table' then
                        if record.license and seenLicenses[record.license] then goto skip end
                        BuildLeaderboardResults(seenDbIds, seenLicenses, results, nil, record, dbId)
                    end
                end
            end
            ::skip::
        end
        EndFindKvp(handle)
    end

    table.sort(results, function(a, b) return a.globalKills > b.globalKills end)
    local out = {}
    for i = 1, math.min(limit, #results) do out[i] = results[i] end
    return out
end)

exports('GetLeaderboardDeaths', function(limit)
    limit = limit or 10
    local seenDbIds = {}
    local seenLicenses = {}
    local results = {}

    for src, record in pairs(RecordCache) do
        if not GetPlayerName(src) then goto continue end
        local dbId = GetPlayerDbId(src)
        if not dbId and record.license then
            dbId = LicenseToDbId(record.license)
        end
        BuildLeaderboardResults(seenDbIds, seenLicenses, results, src, record, dbId)
        ::continue::
    end

    local prefix = KVP_RECORD:format('')
    local handle = StartFindKvp(prefix)
    if handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not key then break end
            local dbIdStr = key:sub(#prefix + 1)
            local dbId = tonumber(dbIdStr)
            if dbId and not seenDbIds[dbId] then
                local saved = GetResourceKvpString(key)
                if saved then
                    local ok, record = pcall(json.decode, saved)
                    if ok and type(record) == 'table' then
                        if record.license and seenLicenses[record.license] then goto skip end
                        BuildLeaderboardResults(seenDbIds, seenLicenses, results, nil, record, dbId)
                    end
                end
            end
            ::skip::
        end
        EndFindKvp(handle)
    end

    table.sort(results, function(a, b) return a.globalDeaths > b.globalDeaths end)
    local out = {}
    for i = 1, math.min(limit, #results) do out[i] = results[i] end
    return out
end)

exports('GetPlayerRecord', function(src)
    local record = GetRecord(src)
    record.kd = CalcKD(record)
    return record
end)

-- ============================================================
-- OFFLINE LOOKUP
-- ============================================================

exports('GetRecordByDbId', function(dbId)
    local saved = GetResourceKvpString(KVP_RECORD:format(dbId))
    if not saved then return nil end
    local ok, decoded = pcall(json.decode, saved)
    if not ok or type(decoded) ~= 'table' then return nil end
    decoded.globalKills  = decoded.globalKills  or 0
    decoded.globalDeaths = decoded.globalDeaths or 0
    decoded.wins         = decoded.wins         or 0
    decoded.kd = CalcKD(decoded)
    return decoded
end)

-- ============================================================
-- ADMIN STAT RESET
-- ============================================================

AddEventHandler('pvp-playerlog:adminResetField', function(src, field)
    if not src or not GetPlayerName(src) then return end
    local record = GetRecord(src)

    if field == "kills" or field == "all" then
        record.globalKills = 0
    end
    if field == "deaths" or field == "all" then
        record.globalDeaths = 0
    end
    if field == "wins" or field == "all" then
        record.wins = 0
    end

    RecordCache[src] = record
    SaveRecord(src, record)
end)

-- ============================================================
-- HTTP ENDPOINT — used by the Discord bot to fetch stats
-- GET /stats?discord=DISCORD_ID  or  GET /stats?name=USERNAME
-- Returns JSON: { found, name, globalKills, globalDeaths, kd, wins }
-- ============================================================

local HTTP_SECRET = GetConvar('pvp_stats_secret', '')

local function MakeStatsResponse(record)
    local kd = CalcKD(record)
    return json.encode({
        found        = true,
        name         = record.lastUsername or 'Unknown',
        globalKills  = record.globalKills  or 0,
        globalDeaths = record.globalDeaths or 0,
        kd           = kd,
        wins         = record.wins         or 0,
    })
end

SetHttpHandler(function(req, res)
    res.writeHead(200, { ['Content-Type'] = 'application/json' })

    -- Optional secret check
    local secret = HTTP_SECRET
    if secret ~= '' then
        local auth = req.headers and req.headers['x-stats-secret'] or ''
        if auth ~= secret then
            res.send(json.encode({ found = false, error = 'unauthorized' }))
            return
        end
    end

    local params = {}
    if req.path then
        local query = req.path:match('%?(.+)$')
        if query then
            for k, v in query:gmatch('([^&=]+)=([^&=]+)') do
                params[k] = v
            end
        end
    end

    local discordQuery = params['discord']
    local nameQuery    = params['name']

    -- ---- Lookup by Discord ID ----
    if discordQuery and discordQuery ~= '' then
        -- Search online first
        for src, record in pairs(RecordCache) do
            if GetPlayerName(src) and record.discordId == discordQuery then
                res.send(MakeStatsResponse(record))
                return
            end
        end
        -- Search KVP
        local prefix = KVP_RECORD:format('')
        local handle = StartFindKvp(prefix)
        if handle ~= -1 then
            while true do
                local key = FindKvp(handle)
                if not key then break end
                local saved = GetResourceKvpString(key)
                if saved then
                    local ok, record = pcall(json.decode, saved)
                    if ok and type(record) == 'table' and record.discordId == discordQuery then
                        EndFindKvp(handle)
                        res.send(MakeStatsResponse(record))
                        return
                    end
                end
            end
            EndFindKvp(handle)
        end
        res.send(json.encode({ found = false, error = 'no_record' }))
        return
    end

    -- ---- Lookup by name (case-insensitive, partial match) ----
    if nameQuery and nameQuery ~= '' then
        local lowerQuery = nameQuery:lower()
        local best = nil
        local bestExact = false

        local function CheckRecord(record)
            if not record or not record.lastUsername then return end
            local lowerName = record.lastUsername:lower()
            local isExact = lowerName == lowerQuery
            local isPartial = lowerName:find(lowerQuery, 1, true) ~= nil
            if isExact and not bestExact then
                best = record
                bestExact = true
            elseif isPartial and not best then
                best = record
            end
        end

        for src, record in pairs(RecordCache) do
            if GetPlayerName(src) then CheckRecord(record) end
        end

        if not bestExact then
            local prefix = KVP_RECORD:format('')
            local handle = StartFindKvp(prefix)
            if handle ~= -1 then
                while true do
                    local key = FindKvp(handle)
                    if not key then break end
                    local saved = GetResourceKvpString(key)
                    if saved then
                        local ok, record = pcall(json.decode, saved)
                        if ok and type(record) == 'table' then CheckRecord(record) end
                    end
                end
                EndFindKvp(handle)
            end
        end

        if best then
            res.send(MakeStatsResponse(best))
        else
            res.send(json.encode({ found = false, error = 'not_found' }))
        end
        return
    end

    res.send(json.encode({ found = false, error = 'missing_param' }))
end)

-- ============================================================
-- EXTRA EXPORTS: Discord ID + name lookup (used by bot / other resources)
-- ============================================================

exports('GetRecordByDiscordId', function(discordId)
    for src, record in pairs(RecordCache) do
        if GetPlayerName(src) and record.discordId == discordId then
            record.kd = CalcKD(record)
            return record
        end
    end
    local prefix = KVP_RECORD:format('')
    local handle = StartFindKvp(prefix)
    if handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not key then break end
            local saved = GetResourceKvpString(key)
            if saved then
                local ok, record = pcall(json.decode, saved)
                if ok and type(record) == 'table' and record.discordId == discordId then
                    EndFindKvp(handle)
                    record.kd = CalcKD(record)
                    return record
                end
            end
        end
        EndFindKvp(handle)
    end
    return nil
end)

exports('SearchRecordByName', function(nameQuery)
    local lowerQuery = nameQuery:lower()
    local best = nil
    local bestExact = false
    local function Check(record)
        if not record or not record.lastUsername then return end
        local lowerName = record.lastUsername:lower()
        if lowerName == lowerQuery and not bestExact then
            best = record; bestExact = true
        elseif lowerName:find(lowerQuery, 1, true) and not best then
            best = record
        end
    end
    for src, record in pairs(RecordCache) do
        if GetPlayerName(src) then Check(record) end
    end
    if not bestExact then
        local prefix = KVP_RECORD:format('')
        local handle = StartFindKvp(prefix)
        if handle ~= -1 then
            while true do
                local key = FindKvp(handle)
                if not key then break end
                local saved = GetResourceKvpString(key)
                if saved then
                    local ok, r = pcall(json.decode, saved)
                    if ok and type(r) == 'table' then Check(r) end
                end
            end
            EndFindKvp(handle)
        end
    end
    if best then best.kd = CalcKD(best) end
    return best
end)

-- ============================================================
-- STARTUP CHECK
-- ============================================================

CreateThread(function()
    Wait(2000)
    local wh = GetWebhook()
    if wh == "" then
        print("[PVP-PLAYERLOG] WARNING: turfwars_playerlog_webhook not set — Discord logging disabled.")
    else
        print("[PVP-PLAYERLOG] Webhook OK. Player log active.")
    end
end)
