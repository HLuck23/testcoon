-- ============================================================
-- SERVER-SIDE PvP ENFORCER
-- Ensures friendly fire is enabled for every connecting player.
-- Also broadcasts kill feed to all players.
-- ============================================================

AddEventHandler("onResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    -- Apply to all currently connected players
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent("pvp-core:enableFriendlyFire", tonumber(playerId))
    end
end)

AddEventHandler("playerSpawned", function()
    -- Re-enable PvP every spawn just in case
    TriggerClientEvent("pvp-core:enableFriendlyFire", source)
end)

-- ============================================================
-- KILL FEED BROADCASTER
-- Receives kill events from any client and broadcasts to all.
-- ============================================================

-- Discord webhook for kill logging. Set via server.cfg convar:
--   set turfwars_killfeed_webhook "https://discord.com/api/webhooks/..."
local KILL_LOG_WEBHOOK = GetConvar('turfwars_killfeed_webhook', '')

local function DiscordLogKill(message)
    if KILL_LOG_WEBHOOK == "" then return end
    PerformHttpRequest(KILL_LOG_WEBHOOK, function(statusCode, _, _)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(("[PVP-CORE LOG] Discord webhook failed, status: %s"):format(tostring(statusCode)))
        end
    end, "POST", json.encode({ content = message }),
        { ["Content-Type"] = "application/json" })
end

-- ============================================================
-- KILL VALIDATION
-- The client decides locally when a kill happens (it's the only
-- side with the GTA damage events), so we can't independently
-- re-prove every kill server-side. What we CAN do cheaply:
--   1. Reject victim names that aren't a real connected player
--      (or the literal "NPC" the client already uses for non-players).
--   2. If the killer is in a tracked turf-wars session, the victim
--      must be in that same session too (uses the existing
--      pvp-turf IsPlayerInTurf export -- same pattern pvp-economy
--      already uses to gate money payouts).
--   3. Per-victim cooldown so the same "kill" can't be replayed/
--      spammed by a forged event call.
-- This raises the bar against cheat-menu event spam without
-- touching headshot detection, the kill feed UI, or payouts --
-- those are unchanged. Note: redzone has no server-side session
-- tracking at all (it's client-only), so kills made there only get
-- checks #1 and #3, not the session cross-check. Worth building
-- out if redzone gets its own server-side tracking later.
-- ============================================================

local RecentVictimKillTimes = {}
local VICTIM_KILL_COOLDOWN_MS = 3000

local function FindPlayerIdByName(name)
    for _, playerId in ipairs(GetPlayers()) do
        if GetPlayerName(playerId) == name then
            return tonumber(playerId)
        end
    end
    return nil
end

local function ValidateKillClaim(src, victimName)
    -- NPC kills: nothing to cross-check against, always allowed through.
    if victimName == "NPC" then
        return true
    end

    -- Player kills: victim name must resolve to an actual connected player.
    local victimId = FindPlayerIdByName(victimName)
    if not victimId then
        return false, "victim is not a currently connected player"
    end

    if victimId == src then
        return false, "killer and victim are the same player"
    end

    -- Per-victim cooldown -- guards against the same kill being replayed.
    local now = GetGameTimer()
    local lastKillTime = RecentVictimKillTimes[victimId]
    if lastKillTime and (now - lastKillTime) < VICTIM_KILL_COOLDOWN_MS then
        return false, "victim was already credited as killed moments ago"
    end

    -- If killer is in a tracked turf-wars session, victim must be too.
    local killerInTurf, victimInTurf = false, false
    pcall(function() killerInTurf = exports['pvp-turf']:IsPlayerInTurf(src) end)
    if killerInTurf then
        pcall(function() victimInTurf = exports['pvp-turf']:IsPlayerInTurf(victimId) end)
        if not victimInTurf then
            return false, "killer is in Turf Wars but victim is not"
        end
    end

    RecentVictimKillTimes[victimId] = now
    return true
end

RegisterNetEvent("pvp-core:sendKillFeed")
AddEventHandler("pvp-core:sendKillFeed", function(victimName, weaponCategory, isHeadshot)
    local src = source
    local killerName = GetPlayerName(src)

    local valid, rejectReason = ValidateKillClaim(src, victimName)
    if not valid then
        print(("[PVP-CORE LOG] REJECTED kill claim from %s (id:%d) -> %s | reason: %s")
            :format(killerName, src, victimName, rejectReason))
        DiscordLogKill(("🚩 **Rejected kill claim** — %s (id:%d) → %s | reason: %s")
            :format(killerName, src, victimName, rejectReason))
        return
    end

    -- ============================================================
    -- LOGGING ONLY — does not block or alter the broadcast below.
    -- Covers both player and NPC kills, since the client already
    -- sends victimName = "NPC" for non-player victims.
    -- ============================================================
    -- Broadcast to every client (including sender)
    TriggerClientEvent("pvp-core:addKillFeed", -1, killerName, victimName, weaponCategory, isHeadshot)

    -- Fire internal event — playerlog listens to this and updates globalKills synchronously
    TriggerEvent("pvp-core:internalKillRecorded", src, killerName, victimName, weaponCategory, isHeadshot)

    -- Read AFTER TriggerEvent so playerlog has already incremented the record
    local record = exports['pvp-playerlog']:GetPlayerRecord(src)
    local gk = record and record.globalKills  or 0
    local gd = record and record.globalDeaths or 0

    print(("[PVP-CORE LOG] %s (id:%d) killed %s | weapon:%s | headshot:%s | Kills: %d | Deaths: %d")
        :format(killerName, src, victimName, weaponCategory, tostring(isHeadshot), gk, gd))

    DiscordLogKill(("**%s** (id:%d) → %s | weapon: %s | headshot: %s | Kills: %d | Deaths: %d")
        :format(killerName, src, victimName, weaponCategory, tostring(isHeadshot), gk, gd))
end)

-- ============================================================
-- DEATH REPORT -- mirrors sendKillFeed. This is the missing
-- server-side counterpart: previously pvp-core only ever told
-- the server about kills, never about the killer's own deaths,
-- so globalDeaths had no reliable writer at all.
-- ============================================================

RegisterNetEvent("pvp-core:sendDeathReport")
AddEventHandler("pvp-core:sendDeathReport", function()
    local src = source
    TriggerEvent("pvp-core:internalDeathRecorded", src)
end)

AddEventHandler("playerDropped", function()
    RecentVictimKillTimes[source] = nil
end)