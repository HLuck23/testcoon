-- ============================================================
-- PVP SHOP (Layer 3: economy progression)
-- Server-authoritative weapon purchases and ownership.
-- Talks to pvp-economy (money) via exports, doesn't touch
-- pvp-turf's existing arsenal menu logic directly -- pvp-turf's
-- client.lua adds one small check before equipping (see notes
-- in pvp-turf/client.lua diff).
-- ============================================================

local KVP_OWNED = 'pvpshop:owned:%s'

-- Same webhook as pvp-economy. Set via server.cfg convar so the real
-- URL never lives in a file you might share/commit/zip up:
--   set turfwars_shop_webhook "https://discord.com/api/webhooks/..."
local SHOP_LOG_WEBHOOK = GetConvar('turfwars_shop_webhook', '')

-- ============================================================
-- IDENTITY (same fallback pattern as PedMngr / pvp-economy)
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

local function DiscordLog(message)
    print(("[PVP-SHOP LOG] %s"):format(message))
    if SHOP_LOG_WEBHOOK == "" then return end
    PerformHttpRequest(SHOP_LOG_WEBHOOK, function(statusCode, _, _)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(("[PVP-SHOP LOG] Discord webhook failed, status: %s"):format(tostring(statusCode)))
        end
    end, "POST", json.encode({ content = message }), { ["Content-Type"] = "application/json" })
end

-- ============================================================
-- OWNERSHIP: load / save (KVP, same pattern as PedMngr)
-- ============================================================

local OwnedCache = {} -- [src] = { [weaponHash] = true, ... }

local function LoadOwned(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return {} end

    local saved = GetResourceKvpString(KVP_OWNED:format(dbId))
    if saved then
        local ok, decoded = pcall(json.decode, saved)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return {}
end

local function SaveOwned(src, owned)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    SetResourceKvp(KVP_OWNED:format(dbId), json.encode(owned))
end

local function GetOwned(src)
    if not OwnedCache[src] then OwnedCache[src] = LoadOwned(src) end
    return OwnedCache[src]
end

-- ============================================================
-- STARTER WEAPON
-- Every player owns the Badged Eagle from their very first
-- connect, free, forever. It's intentionally a weak pistol so
-- new players have an immediate reason to save up for something
-- better. It is never added to OwnedCache via purchase, and
-- purchaseWeapon below refuses to sell/charge for it if anything
-- ever tries.
-- ============================================================

AddEventHandler('playerJoining', function()
    local src = source
    local owned = GetOwned(src)
    if not owned[STARTER_WEAPON] then
        owned[STARTER_WEAPON] = true
        OwnedCache[src] = owned
        SaveOwned(src, owned)
    end
end)

-- ============================================================
-- PURCHASE
-- Validates: weapon exists in price table, player doesn't
-- already own it, player has enough money. Money is deducted
-- via pvp-economy's own export so there's a single source of
-- truth for balances -- this resource never edits money KVPs
-- directly.
-- ============================================================

RegisterNetEvent('pvp-shop:purchaseWeapon')
AddEventHandler('pvp-shop:purchaseWeapon', function(weaponHash)
    local src = source
    if not weaponHash or type(weaponHash) ~= 'string' then return end

    if IsStarterWeapon(weaponHash) then
        -- Already owned for free, nothing to buy.
        TriggerClientEvent('pvp-shop:purchaseResult', src, false, "already owned", weaponHash)
        return
    end

    local price = GetWeaponPrice(weaponHash)
    if not price then
        DiscordLog(("⚠️ %s (id:%d) tried to buy unknown weapon hash: %s -- ignored")
            :format(GetPlayerName(src), src, tostring(weaponHash)))
        return
    end

    local owned = GetOwned(src)
    if owned[weaponHash] then
        TriggerClientEvent('pvp-shop:purchaseResult', src, false, "already owned", weaponHash)
        return
    end

    local balance = 0
    local ok = pcall(function()
        balance = exports['pvp-economy']:GetMoney(src)
    end)
    if not ok then
        DiscordLog("⚠️ pvp-economy export call failed -- is pvp-economy running?")
        return
    end

    if balance < price then
        TriggerClientEvent('pvp-shop:purchaseResult', src, false, "insufficient funds", weaponHash)
        return
    end

    -- Deduct via pvp-economy's own award export (negative amount = charge)
    exports['pvp-economy']:AwardMoney(src, -price, ("shop purchase: %s"):format(weaponHash))

    owned[weaponHash] = true
    OwnedCache[src] = owned
    SaveOwned(src, owned)

    TriggerClientEvent('pvp-shop:purchaseResult', src, true, "purchased", weaponHash)
    DiscordLog(("🔫 %s (id:%d) bought %s for $%d")
        :format(GetPlayerName(src), src, weaponHash, price))
end)

-- ============================================================
-- EQUIP CHECK
-- pvp-turf's client now asks this BEFORE equipping a weapon
-- from the arsenal menu (see pvp-turf/client.lua change).
-- This is the actual server-side gate -- if this denies it,
-- the weapon never gets given, regardless of what the client
-- UI shows.
-- ============================================================

RegisterNetEvent('pvp-shop:requestEquip')
AddEventHandler('pvp-shop:requestEquip', function(weaponHash)
    local src = source
    if not weaponHash or type(weaponHash) ~= 'string' then return end

    local owned = GetOwned(src)
    if owned[weaponHash] then
        TriggerClientEvent('pvp-shop:equipApproved', src, weaponHash)
    else
        TriggerClientEvent('pvp-shop:equipDenied', src, weaponHash)
        DiscordLog(("🚫 %s (id:%d) tried to equip unowned weapon: %s -- denied")
            :format(GetPlayerName(src), src, weaponHash))
    end
end)

RegisterNetEvent('pvp-shop:requestOwnedList')
AddEventHandler('pvp-shop:requestOwnedList', function()
    local src = source
    TriggerClientEvent('pvp-shop:ownedList', src, GetOwned(src))
end)

-- ============================================================
-- BALANCE
-- Used by pvp-turf's cash overlay (turf mode HUD) so players can
-- see what they can afford before opening the arsenal menu, and
-- by the purchase confirm dialog to show affordability live.
-- ============================================================

RegisterNetEvent('pvp-shop:requestBalance')
AddEventHandler('pvp-shop:requestBalance', function()
    local src = source
    local balance = 0
    local ok = pcall(function()
        balance = exports['pvp-economy']:GetMoney(src)
    end)
    if not ok then
        DiscordLog("⚠️ pvp-economy export call failed -- is pvp-economy running?")
        return
    end
    TriggerClientEvent('pvp-shop:balanceResult', src, balance)
end)

AddEventHandler('playerDropped', function()
    local src = source
    OwnedCache[src] = nil
end)

-- ============================================================
-- EXPORTS
-- ============================================================

exports('IsWeaponOwned', function(src, weaponHash)
    local owned = GetOwned(src)
    return owned[weaponHash] == true
end)

exports('GetOwnedWeapons', function(src)
    return GetOwned(src)
end)

-- ============================================================
-- ADMIN WIPE
-- Clears every owned weapon for a connected player, then
-- re-grants the starter weapon so the "everyone always owns the
-- Badged Eagle" invariant from playerJoining above still holds --
-- this never leaves a player with a totally empty loadout.
-- Online-only, same constraint as every other src-based export in
-- this pack: ownership lives on OwnedCache[src]/this player's KVP,
-- there's no offline edit path here.
-- ============================================================

exports('WipeOwnedWeapons', function(src)
    if not src or not GetPlayerName(src) then return false end

    local wiped = GetOwned(src)
    local wipedList = {}
    for weaponHash in pairs(wiped) do
        wipedList[#wipedList + 1] = weaponHash
    end

    local fresh = {}
    fresh[STARTER_WEAPON] = true
    OwnedCache[src] = fresh
    SaveOwned(src, fresh)

    DiscordLog(("🧹 %s (id:%d) had their owned weapons wiped by an admin (%d weapon(s) removed, starter weapon restored)")
        :format(GetPlayerName(src), src, #wipedList))

    return true, wipedList
end)
