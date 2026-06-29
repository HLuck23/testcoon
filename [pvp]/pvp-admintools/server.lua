-- ============================================================
-- PVP ADMIN TOOLS
-- Console + in-game commands for looking up and editing player
-- data, wrapping the exports already provided by pvp-economy,
-- pvp-shop, and pvp-playerlog. No direct KVP/file access here --
-- everything goes through those resources' own exports, so this
-- resource never duplicates or risks desyncing their logic.
--
-- LOGGING
-- Admin actions are logged to Discord via the turfwars_admintools_
-- webhook convar, NOT to in-game chat, so admin activity doesn't
-- clutter chat for everyone on the server. Set it in server.cfg:
--   set turfwars_admintools_webhook "https://discord.com/api/webhooks/..."
-- The admin who ran the command still gets a direct reply (console
-- print, or a chat whisper only they see) confirming the result.
-- If the webhook isn't set, actions fall back to a server console
-- print so nothing is silently lost -- but never to chat.
--
-- PERMISSIONS
-- All commands require the "pvpadmin" ACE permission. Grant it in
-- server.cfg, e.g. for a specific admin's license:
--   add_ace identifier.license:f75dc9b6... pvpadmin allow
-- or for a whole group:
--   add_principal identifier.license:f75dc9b6... group.admin
--   add_ace group.admin pvpadmin allow
-- Without this, NOBODY can run these commands -- including from
-- the server console unless you grant it to "group.console" too:
--   add_ace group.console pvpadmin allow   (usually already implied,
--   but add explicitly if console commands get refused)
-- ============================================================

local function IsAuthorized(src)
    -- src == 0 means server console, which IsPlayerAceAllowed always
    -- treats specially -- but we still require the ACE explicitly so
    -- console isn't silently exempt if you ever lock things down further.
    return IsPlayerAceAllowed(src, "pvpadmin")
end

local function Reply(src, msg)
    if src == 0 then
        print(msg)
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 200, 80},
            args  = {"[PVP-ADMIN]", msg}
        })
    end
end

local function DenyAndLog(src)
    Reply(src, "You don't have permission to use admin commands (missing 'pvpadmin' ACE).")
end

-- ------------------------------------------------------------
-- Webhook logging
-- Same pattern as pvp-playerlog/pvp-shop: a dedicated convar, set
-- in server.cfg, so the real URL never lives in a file you'd
-- share/commit/zip up:
--   set turfwars_admintools_webhook "https://discord.com/api/webhooks/..."
-- Every admin action gets logged HERE instead of printed to chat,
-- so admin activity doesn't clutter the in-game chat window for
-- everyone -- the admin who ran the command still gets a direct
-- Reply() telling them it worked, just not a chat broadcast.
-- ------------------------------------------------------------

local function GetWebhook()
    return GetConvar('turfwars_admintools_webhook', '')
end

local function ActorName(src)
    if src == 0 then return "console" end
    return ("%s (id:%d)"):format(GetPlayerName(src) or "?", src)
end

local function LogAction(src, message)
    local line = ("[PVP-ADMIN] %s: %s"):format(ActorName(src), message)
    local webhook = GetWebhook()
    if webhook == "" then
        -- No webhook configured -- fall back to server console so the
        -- action is still logged somewhere, but never to in-game chat.
        print(line .. " (warning: turfwars_admintools_webhook not set)")
        return
    end
    PerformHttpRequest(webhook, function(statusCode, _, _)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(("[PVP-ADMIN] Discord webhook failed, status: %s"):format(tostring(statusCode)))
        end
    end, "POST", json.encode({ content = line }), { ["Content-Type"] = "application/json" })
end

-- ------------------------------------------------------------
-- Identity helpers
-- ------------------------------------------------------------

-- Resolves a /command argument to a connected player's server id (src).
-- Accepts either a numeric src directly, or a player name to search for
-- (case-insensitive substring match against GetPlayerName).
local function ResolveOnlineSrc(arg)
    if not arg then return nil end
    if tonumber(arg) then
        local src = tonumber(arg)
        if GetPlayerName(src) then return src end
        return nil
    end
    local needle = arg:lower()
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        local name = GetPlayerName(pid)
        if name and name:lower():find(needle, 1, true) then
            return pid
        end
    end
    return nil
end

-- Resolves a /command argument to a dbId for OFFLINE-capable lookups.
-- Accepts: a raw numeric dbId, a bare hex license, a "license:hex" string,
-- or (if it matches a connected player's name/src) that player's dbId via
-- pvp-playerlog's own export.
local function ResolveDbId(arg)
    if not arg then return nil end

    -- Raw dbId, if it's numeric AND not also resolvable as an online src
    -- with a matching pvp-playerlog record -- numeric is ambiguous between
    -- "this is a dbId" and "this is a src", so we try src first since
    -- that's almost always what a short number like "3" means in practice.
    local onlineSrc = ResolveOnlineSrc(arg)
    if onlineSrc then
        local ok, record = pcall(function()
            return exports['pvp-playerlog']:GetPlayerRecord(onlineSrc)
        end)
        if ok and record and record.license then
            local ok2, dbId = pcall(function()
                return exports['pvp-playerlog']:LicenseToDbId(record.license)
            end)
            if ok2 and dbId then return dbId, record.lastUsername end
        end
    end

    -- Looks like a license string (with or without prefix) or a long
    -- hex/numeric dbId -- hash it via pvp-playerlog's exported helper.
    local ok, dbId = pcall(function()
        return exports['pvp-playerlog']:LicenseToDbId(arg)
    end)
    if ok and dbId then return dbId, nil end

    return nil
end

-- ============================================================
-- LOOKUP -- works online or offline.
-- /pvplookup <name|src|license|dbId>
-- ============================================================

RegisterCommand("pvplookup", function(source, args, rawCommand)
    if not IsAuthorized(source) then return DenyAndLog(source) end
    if not args[1] then
        Reply(source, "Usage: /pvplookup <player name | src id | license | dbId>")
        return
    end

    local dbId, hintName = ResolveDbId(args[1])
    if not dbId then
        Reply(source, ("Could not resolve '%s' to a player."):format(args[1]))
        return
    end

    local ok, record = pcall(function()
        return exports['pvp-playerlog']:GetRecordByDbId(dbId)
    end)

    if not ok or not record then
        Reply(source, ("No pvp-playerlog record found for dbId %s%s")
            :format(tostring(dbId), hintName and (" (" .. hintName .. ")") or ""))
        return
    end

    Reply(source, ("--- %s (dbId %s) ---"):format(record.lastUsername or "?", tostring(dbId)))
    Reply(source, ("Money: $%s | KD: %s"):format(tostring(record.money or 0), tostring(record.kd or 0)))
    Reply(source, ("Turf Kills: %d | Wins: %d"):format(record.kills or 0, record.wins or 0))
    Reply(source, ("Global Kills: %d | Global Deaths: %d"):format(record.globalKills or 0, record.globalDeaths or 0))
    Reply(source, ("Weapons owned: %d"):format(record.weaponsOwned and #record.weaponsOwned or 0))
    Reply(source, ("License: %s"):format(record.license or "?"))
    Reply(source, ("Last updated: %s"):format(record.lastUpdated or "?"))
end, false)

-- ============================================================
-- GIVE / SET MONEY -- online players only (see README for why).
-- /pvpmoney <name|src> <amount>          -- ADDS amount (use negative to deduct)
-- /pvpmoney <name|src> <amount> set      -- SETS balance to exactly amount
-- ============================================================

RegisterCommand("pvpmoney", function(source, args, rawCommand)
    if not IsAuthorized(source) then return DenyAndLog(source) end
    if not args[1] or not args[2] then
        Reply(source, "Usage: /pvpmoney <player name|src> <amount> [set]")
        return
    end

    local targetSrc = ResolveOnlineSrc(args[1])
    if not targetSrc then
        Reply(source, ("Player '%s' is not online. Editing money requires the player to be connected.")
            :format(args[1]))
        return
    end

    local amount = tonumber(args[2])
    if not amount then
        Reply(source, "Amount must be a number.")
        return
    end

    local mode = args[3]
    if mode == "set" then
        local ok, current = pcall(function() return exports['pvp-economy']:GetMoney(targetSrc) end)
        if not ok then
            Reply(source, "pvp-economy export call failed -- is pvp-economy running?")
            return
        end
        local delta = amount - (current or 0)
        exports['pvp-economy']:AwardMoney(targetSrc, delta, ("admin set by %s"):format(GetPlayerName(source) or "console"))
        Reply(source, ("Set %s's balance to $%d."):format(GetPlayerName(targetSrc), amount))
        LogAction(source, ("set %s's balance to $%d"):format(GetPlayerName(targetSrc), amount))
    else
        exports['pvp-economy']:AwardMoney(targetSrc, amount, ("admin adjust by %s"):format(GetPlayerName(source) or "console"))
        local ok, newBalance = pcall(function() return exports['pvp-economy']:GetMoney(targetSrc) end)
        Reply(source, ("Adjusted %s's balance by $%d. New balance: $%s")
            :format(GetPlayerName(targetSrc), amount, ok and tostring(newBalance) or "?"))
        LogAction(source, ("adjusted %s's balance by $%d (new balance: $%s)")
            :format(GetPlayerName(targetSrc), amount, ok and tostring(newBalance) or "?"))
    end
end, false)

-- ============================================================
-- RESET STATS -- online players only.
-- /pvpresetstats <name|src> <kills|deaths|wins|all>
-- ============================================================

RegisterCommand("pvpresetstats", function(source, args, rawCommand)
    if not IsAuthorized(source) then return DenyAndLog(source) end
    if not args[1] or not args[2] then
        Reply(source, "Usage: /pvpresetstats <player name|src> <kills|deaths|wins|all>")
        return
    end

    local targetSrc = ResolveOnlineSrc(args[1])
    if not targetSrc then
        Reply(source, ("Player '%s' is not online. Resetting stats requires the player to be connected.")
            :format(args[1]))
        return
    end

    local field = args[2]:lower()
    local ok, record = pcall(function() return exports['pvp-playerlog']:GetPlayerRecord(targetSrc) end)
    if not ok or not record then
        Reply(source, "pvp-playerlog export call failed -- is pvp-playerlog running?")
        return
    end

    -- pvp-playerlog doesn't expose a direct "set field" export, so we go
    -- through GetRecordByDbId + the same KVP key it owns -- but since we
    -- promised not to touch KVP files directly, and pvp-playerlog has no
    -- public "SetField" export yet, we ask the resource to do it via a
    -- dedicated internal event instead. See pvp-playerlog's new handler
    -- for 'pvp-playerlog:adminResetField' added alongside this resource.
    if field ~= "kills" and field ~= "deaths" and field ~= "wins" and field ~= "all" then
        Reply(source, "Field must be one of: kills, deaths, wins, all")
        return
    end

    TriggerEvent('pvp-playerlog:adminResetField', targetSrc, field)
    Reply(source, ("Reset '%s' stat(s) for %s."):format(field, GetPlayerName(targetSrc)))
    LogAction(source, ("reset '%s' stat(s) for %s"):format(field, GetPlayerName(targetSrc)))
end, false)

-- ============================================================
-- LEADERBOARD -- read-only convenience wrapper, online-derived data only
-- (pvp-playerlog's leaderboard exports only know about currently-cached
-- records, same limitation that already existed before this resource).
-- /pvptop kills|deaths [limit]
-- ============================================================

RegisterCommand("pvptop", function(source, args, rawCommand)
    if not IsAuthorized(source) then return DenyAndLog(source) end
    local kind = (args[1] or "kills"):lower()
    local limit = tonumber(args[2]) or 10

    local ok, results
    if kind == "deaths" then
        ok, results = pcall(function() return exports['pvp-playerlog']:GetLeaderboardDeaths(limit) end)
    else
        ok, results = pcall(function() return exports['pvp-playerlog']:GetLeaderboardKills(limit) end)
    end

    if not ok or not results then
        Reply(source, "pvp-playerlog export call failed -- is pvp-playerlog running?")
        return
    end

    Reply(source, ("--- Top %d by %s ---"):format(#results, kind))
    for i, entry in ipairs(results) do
        Reply(source, ("%d. %s -- Kills: %d, Deaths: %d, K/D: %s")
            :format(i, entry.name or "?", entry.globalKills or 0, entry.globalDeaths or 0, tostring(entry.kd or 0)))
    end
end, false)

-- ============================================================
-- WIPE OWNED WEAPONS -- online players only (ownership lives in
-- pvp-shop's OwnedCache/KVP, keyed by src, same constraint as
-- /pvpmoney and /pvpresetstats above).
-- Re-grants the starter weapon automatically (see pvp-shop's
-- WipeOwnedWeapons export) so this is a clean "back to turf-mode
-- default loadout" reset, not a total disarm.
-- /pvpwipeweapons <name|src>
-- ============================================================

RegisterCommand("pvpwipeweapons", function(source, args, rawCommand)
    if not IsAuthorized(source) then return DenyAndLog(source) end
    if not args[1] then
        Reply(source, "Usage: /pvpwipeweapons <player name|src>")
        return
    end

    local targetSrc = ResolveOnlineSrc(args[1])
    if not targetSrc then
        Reply(source, ("Player '%s' is not online. Wiping owned weapons requires the player to be connected.")
            :format(args[1]))
        return
    end

    local targetName = GetPlayerName(targetSrc)
    local ok, wiped, wipedList = pcall(function() return exports['pvp-shop']:WipeOwnedWeapons(targetSrc) end)
    if not ok or not wiped then
        Reply(source, "pvp-shop export call failed -- is pvp-shop running?")
        return
    end

    local count = wipedList and #wipedList or 0
    Reply(source, ("Wiped %d owned weapon(s) for %s. Starter weapon restored.")
        :format(count, targetName))
    LogAction(source, ("wiped %d owned weapon(s) for %s"):format(count, targetName))
end, false)
