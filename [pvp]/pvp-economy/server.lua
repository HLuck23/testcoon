-- ============================================================
-- PVP ECONOMY (Layer 2: session rewards)
-- Listens to existing kill events WITHOUT modifying them.
-- Validates kill claims before paying out money.
-- Persists money via server KVP, same pattern as PedMngr.
-- ============================================================

local KVP_MONEY = 'pvpeco:money:%s'

local CONFIG = {
    startingMoney   = 15000,
    killReward      = 750,
    headshotBonus   = 250,

    -- Round-end bonuses (one "round" = one map rotation in pvp-turf)
    soloWinBonus      = 2500,  -- paid to the single winner when 3 or fewer players were in the round
    top3MinPlayers    = 4,     -- need 4+ players in the round for tiered top-3 payouts
    top3Bonuses       = { 5000, 2500, 1000 }, -- 1st, 2nd, 3rd

    -- Anti-spoof: max kills we'll pay out per player per window
    maxKillsPerWindow = 4,
    windowMs           = 3000,   -- 3 seconds
}

-- Discord webhook for economy logging. Set via server.cfg convar:
--   set turfwars_shop_webhook "https://discord.com/api/webhooks/..."
-- (Same convar as pvp-shop, since they share one webhook channel.)
local ECONOMY_LOG_WEBHOOK = GetConvar('turfwars_shop_webhook', '')

-- ============================================================
-- IDENTITY (same fallback pattern as PedMngr, for consistency)
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

-- ============================================================
-- MONEY: load / save / award (all server-side, all logged)
-- ============================================================

local MoneyCache = {} -- [src] = amount, loaded on join, saved on change

local function LoadMoney(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return CONFIG.startingMoney end

    local saved = GetResourceKvpString(KVP_MONEY:format(dbId))
    if saved then
        return tonumber(saved) or CONFIG.startingMoney
    else
        SetResourceKvp(KVP_MONEY:format(dbId), tostring(CONFIG.startingMoney))
        return CONFIG.startingMoney
    end
end

local function SaveMoney(src, amount)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    SetResourceKvp(KVP_MONEY:format(dbId), tostring(amount))
end

local function DiscordLog(message)
    print(("[PVP-ECONOMY LOG] %s"):format(message))
    if ECONOMY_LOG_WEBHOOK == "" then return end
    PerformHttpRequest(ECONOMY_LOG_WEBHOOK, function(statusCode, _, _)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(("[PVP-ECONOMY LOG] Discord webhook failed, status: %s"):format(tostring(statusCode)))
        end
    end, "POST", json.encode({ content = message }), { ["Content-Type"] = "application/json" })
end

local function AwardMoney(src, amount, reason)
    if not MoneyCache[src] then MoneyCache[src] = LoadMoney(src) end
    MoneyCache[src] = math.max(0, MoneyCache[src] + amount)
    SaveMoney(src, MoneyCache[src])

    TriggerClientEvent('pvp-economy:moneyUpdated', src, MoneyCache[src])
    local sign = amount >= 0 and "+" or "-"
    DiscordLog(("💰 %s (id:%d) %s$%d [%s] -> balance: $%d")
        :format(GetPlayerName(src), src, sign, math.abs(amount), reason, MoneyCache[src]))
end

-- ============================================================
-- ANTI-SPOOF GATE
-- Rejects kill claims that look impossible, without touching
-- the original kill feed / hud systems at all.
-- ============================================================

local KillWindow = {} -- [src] = { count = n, windowStart = ms }
local RoundKills  = {} -- [src] = kills this round only, reset at round end

local function PassesRateCheck(src)
    local now = GetGameTimer()
    local w = KillWindow[src]

    if not w or (now - w.windowStart) > CONFIG.windowMs then
        KillWindow[src] = { count = 1, windowStart = now }
        return true
    end

    w.count = w.count + 1
    if w.count > CONFIG.maxKillsPerWindow then
        return false
    end
    return true
end

-- ============================================================
-- HOOK: listens to the new internal event from pvp-core.
-- Does NOT touch pvp-core's own broadcast/logging in any way --
-- this is a second, independent listener on the same moment.
-- ============================================================

AddEventHandler('pvp-core:internalKillRecorded', function(src, killerName, victimName, weaponCategory, isHeadshot)
    if not src or not GetPlayerName(src) then return end -- player disconnected mid-event

    -- FIX: pvp-economy is the TURF / GLOBAL money pot only. pvp-wars has its
    -- own completely separate economy (warsmoney:<dbId>, its own AwardMoney,
    -- paid directly from pvp-wars/server.lua's killReport handler).
    -- pvp-core:internalKillRecorded fires for EVERY kill in EVERY mode
    -- (turf, wars, redzone) because pvp-core's client-side kill detection
    -- has no mode check. The old code here paid out to this (turf) pot
    -- whenever the killer was in turf OR wars -- so every wars kill was
    -- being paid TWICE: once correctly into wars money by pvp-wars itself,
    -- and once incorrectly into turf money by this handler. That's why
    -- turf money kept climbing during wars kills while wars money looked
    -- like it "wasn't updating" (it was updating fine, just not where the
    -- player was looking, and the totals didn't match expectations).
    -- Only pay turf money if this kill (player or NPC) happened in TURF.
    local isNpcKill = (victimName == "NPC")

    local inTurf = false
    pcall(function() inTurf = exports['pvp-turf']:IsPlayerInTurf(src) end)
    if not inTurf then
        -- Not a turf kill -- either wars (which pays itself) or redzone
        -- (not wired to this economy at all). Don't pay turf money for it.
        return
    end

    if not PassesRateCheck(src) then
        DiscordLog(("🚩 %s (id:%d) exceeded kill rate limit (%d in %dms) -- payout BLOCKED, claim NOT paid")
            :format(killerName, src, CONFIG.maxKillsPerWindow + 1, CONFIG.windowMs))
        return
    end

    local reward = CONFIG.killReward
    local reason = "kill"
    if isHeadshot then
        reward = reward + CONFIG.headshotBonus
        reason = "kill+headshot"
    end
    if victimName == "NPC" then
        reason = reason .. " (npc)"
    end

    AwardMoney(src, reward, reason)

    -- NEW: track this kill toward the current round's scoreboard,
    -- separate from the lifetime money award above.
    RoundKills[src] = (RoundKills[src] or 0) + 1
end)

-- ============================================================
-- PLAYER CONNECT / DISCONNECT -- load and release cache
-- ============================================================

RegisterNetEvent('pvp-economy:requestBalance')
AddEventHandler('pvp-economy:requestBalance', function()
    local src = source
    if not MoneyCache[src] then MoneyCache[src] = LoadMoney(src) end
    TriggerClientEvent('pvp-economy:moneyUpdated', src, MoneyCache[src])
end)

-- NEW: proactive push on join. Previously balance was ONLY ever sent
-- to a client in response to requestBalance, which nothing called
-- until the player happened to open a shop UI (pvp-turf's arsenal
-- menu, pvp-wars's loadout shop). That left money looking desynced
-- / blank / stuck at 0 for anyone who hadn't opened a shop yet.
-- This pushes the real balance the moment the client's pvp-economy
-- resource comes up, same trigger pvp-core/pvp-hud already use for
-- their own initial state sync.
RegisterNetEvent('pvp-economy:clientReady')
AddEventHandler('pvp-economy:clientReady', function()
    local src = source
    if not MoneyCache[src] then MoneyCache[src] = LoadMoney(src) end
    TriggerClientEvent('pvp-economy:moneyUpdated', src, MoneyCache[src])
end)

AddEventHandler('playerDropped', function()
    local src = source
    MoneyCache[src] = nil
    KillWindow[src] = nil
    RoundKills[src] = nil
end)

-- ============================================================
-- LAYER 2 (cont.): ROUND-END BONUSES
-- Listens to pvp-turf's round-end signal. Ranks players by
-- kills THIS ROUND ONLY (RoundKills), pays top 3 if 4+ players
-- were in the round, otherwise pays just the single winner.
-- Resets RoundKills for everyone after paying out, either way.
-- ============================================================

AddEventHandler('pvp-turf:internalRoundEnded', function(roundPlayerIds, mapName)
    -- Build a ranked list of {src, kills} only for players who were
    -- actually in the round (covers players with 0 kills too).
    local scoreboard = {}
    for _, src in ipairs(roundPlayerIds) do
        if GetPlayerName(src) then -- still connected
            scoreboard[#scoreboard + 1] = { src = src, kills = RoundKills[src] or 0 }
        end
    end

    table.sort(scoreboard, function(a, b) return a.kills > b.kills end)

    local playerCount = #scoreboard

    if playerCount == 0 then
        -- Round ended with nobody in it (shouldn't normally happen) -- nothing to pay.
    elseif playerCount < CONFIG.top3MinPlayers then
        -- 3 or fewer players: only the single winner (most kills) gets the solo bonus.
        local winner = scoreboard[1]
        if winner and winner.kills > 0 then
            AwardMoney(winner.src, CONFIG.soloWinBonus, ("round win (%s, %d players)"):format(mapName, playerCount))
        else
            DiscordLog(("🏁 Round on %s ended with %d player(s), no kills -- no win bonus paid")
                :format(mapName, playerCount))
        end
    else
        -- 4+ players: pay tiered bonuses to top 3 by kills.
        for place = 1, math.min(3, #scoreboard) do
            local entry = scoreboard[place]
            if entry.kills > 0 then
                AwardMoney(entry.src, CONFIG.top3Bonuses[place],
                    ("round #%d place (%s, %d players)"):format(place, mapName, playerCount))
            end
        end
    end

    -- Reset round kills for everyone, win or not, so next round starts clean.
    for _, src in ipairs(roundPlayerIds) do
        RoundKills[src] = nil
    end
end)

-- ============================================================
-- EXPORTS (for Layer 3 / shop resource, later)
-- ============================================================

exports('GetMoney', function(src)
    if not MoneyCache[src] then MoneyCache[src] = LoadMoney(src) end
    return MoneyCache[src]
end)

exports('AwardMoney', function(src, amount, reason)
    AwardMoney(src, amount, reason or "manual")
end)
