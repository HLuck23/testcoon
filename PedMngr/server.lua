-- ============================================================
-- PedMngr Server v2.4 — Model-specific outfits & model memory
-- Saves outfits + last appearance per model hash
-- No database needed — uses FiveM server KVP (KVS)
-- ============================================================

local RESOURCE_NAME = GetCurrentResourceName()

-- Prefixes for KVP keys
local KVP_APPEARANCE = 'pedmngr:appearance:%s'
local KVP_OUTFIT = 'pedmngr:outfit:%s:%s:%s'
local KVP_MODEL_APPEARANCE = 'pedmngr:modelappearance:%s:%s'

-- ============================================================
-- HELPER: Get player DB ID from player-data
-- ============================================================

local function GetPlayerDbId(src)
    -- Try common resource folder names first (most likely)
    for _, resName in ipairs({'player-data', 'cfx-server-data.player-data'}) do
        local ok, dbId = pcall(function()
            return exports[resName].getPlayerId(src)
        end)
        if ok and dbId then return tonumber(dbId) end
    end

    -- Try the provider alias (newer server versions)
    local ok, dbId = pcall(function()
        return exports['cfx.re/playerData.v1alpha1'].getPlayerId(src)
    end)
    if ok and dbId then return tonumber(dbId) end

    -- Last resort: use primary identifier as pseudo-ID
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if id:find('license:') == 1 then
            -- Hash the license to a numeric ID
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
-- OUTFIT LISTING HELPER (model-specific)
-- ============================================================

local function ListOutfits(dbId, modelHash)
    local names = {}
    local prefix = KVP_OUTFIT:format(dbId, modelHash, '')
    local handle = StartFindKvp(prefix)
    if handle ~= -1 then
        while true do
            local key = FindKvp(handle)
            if not key then break end
            local name = key:sub(#prefix + 1)
            if name and name ~= '' then
                table.insert(names, name)
            end
        end
        EndFindKvp(handle)
    end
    return names
end

-- ============================================================
-- PLAYER READY — First join check + appearance restore
-- ============================================================

RegisterNetEvent('pedmngr:playerReady')
AddEventHandler('pedmngr:playerReady', function()
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId then
        return
    end

    local saved = GetResourceKvpString(KVP_APPEARANCE:format(dbId))
    if saved then
        TriggerClientEvent('pedmngr:applyAppearance', src, json.decode(saved))
    else
        TriggerClientEvent('pedmngr:openEditor', src)
    end
end)

-- ============================================================
-- SAVE CHARACTER APPEARANCE
-- ============================================================

RegisterNetEvent('pedmngr:saveAppearance')
AddEventHandler('pedmngr:saveAppearance', function(data)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not data then return end

    SetResourceKvp(KVP_APPEARANCE:format(dbId), json.encode(data))
    TriggerClientEvent('pedmngr:appearanceSaved', src)

    -- FIX (pvp-wars team UI outfit lag): tell every client that this player's
    -- appearance just changed so modes like pvp-wars can immediately invalidate
    -- and re-capture that player's headshot portrait instead of waiting for the
    -- round-robin refresh loop (which can take 6s × n_players to cycle back).
    TriggerClientEvent('pedmngr:playerAppearanceUpdated', -1, src)
end)

-- ============================================================
-- MODEL-SPECIFIC APPEARANCE MEMORY
-- ============================================================

RegisterNetEvent('pedmngr:saveModelAppearance')
AddEventHandler('pedmngr:saveModelAppearance', function(modelHash, data)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not data then return end
    modelHash = tonumber(modelHash) or 0
    SetResourceKvp(KVP_MODEL_APPEARANCE:format(dbId, modelHash), json.encode(data))
end)

RegisterNetEvent('pedmngr:loadModelAppearance')
AddEventHandler('pedmngr:loadModelAppearance', function(modelHash)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    modelHash = tonumber(modelHash) or 0
    local saved = GetResourceKvpString(KVP_MODEL_APPEARANCE:format(dbId, modelHash))
    if saved then
        TriggerClientEvent('pedmngr:applyData', src, json.decode(saved))
    end
end)

-- ============================================================
-- OUTFIT MANAGEMENT (Server KVP, model-specific)
-- ============================================================

RegisterNetEvent('pedmngr:saveOutfit')
AddEventHandler('pedmngr:saveOutfit', function(name, modelHash, data)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not name or name == '' then return end
    modelHash = tonumber(modelHash) or 0

    SetResourceKvp(KVP_OUTFIT:format(dbId, modelHash, name), json.encode(data))
    TriggerClientEvent('pedmngr:outfitList', src, ListOutfits(dbId, modelHash))
end)

RegisterNetEvent('pedmngr:updateOutfit')
AddEventHandler('pedmngr:updateOutfit', function(name, modelHash, data)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not name or name == '' then return end
    modelHash = tonumber(modelHash) or 0

    -- Verify outfit exists before updating
    local existing = GetResourceKvpString(KVP_OUTFIT:format(dbId, modelHash, name))
    if not existing then return end

    SetResourceKvp(KVP_OUTFIT:format(dbId, modelHash, name), json.encode(data))
    TriggerClientEvent('pedmngr:outfitList', src, ListOutfits(dbId, modelHash))
end)

RegisterNetEvent('pedmngr:loadOutfit')
AddEventHandler('pedmngr:loadOutfit', function(name, modelHash)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not name then return end
    modelHash = tonumber(modelHash) or 0

    local saved = GetResourceKvpString(KVP_OUTFIT:format(dbId, modelHash, name))
    if saved then
        TriggerClientEvent('pedmngr:applyData', src, json.decode(saved))
    end
end)

RegisterNetEvent('pedmngr:deleteOutfit')
AddEventHandler('pedmngr:deleteOutfit', function(name, modelHash)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId or not name then return end
    modelHash = tonumber(modelHash) or 0

    DeleteResourceKvp(KVP_OUTFIT:format(dbId, modelHash, name))
    TriggerClientEvent('pedmngr:outfitList', src, ListOutfits(dbId, modelHash))
end)

RegisterNetEvent('pedmngr:listOutfits')
AddEventHandler('pedmngr:listOutfits', function(modelHash)
    local src = source
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    TriggerClientEvent('pedmngr:outfitList', src, ListOutfits(dbId, tonumber(modelHash) or 0))
end)

-- ============================================================
-- EXPORT / IMPORT CODE STORAGE
-- Short "PVP-XXXXXXXX" codes are just a lookup key -- the actual
-- outfit JSON lives here, keyed by the short code, server-wide (not
-- per-player), so anyone on this server can import a code someone
-- else exported. Codes never expire on their own; they're small and
-- there's no per-player cap on outfits already, so no real reason to.
-- ============================================================

local KVP_EXPORT_CODE = 'pedmngr:exportcode:%s'

RegisterNetEvent('pedmngr:storeExportCode')
AddEventHandler('pedmngr:storeExportCode', function(shortCode, jsonStr)
    -- Never trust client input going straight into a KVP key/value pair.
    if type(shortCode) ~= 'string' or not shortCode:match('^[A-Z0-9]+$') or #shortCode > 16 then
        return
    end
    if type(jsonStr) ~= 'string' or jsonStr == '' or #jsonStr > 50000 then
        return
    end
    SetResourceKvp(KVP_EXPORT_CODE:format(shortCode), jsonStr)
end)

RegisterNetEvent('pedmngr:requestImportCode')
AddEventHandler('pedmngr:requestImportCode', function(shortCode)
    local src = source
    if type(shortCode) ~= 'string' or not shortCode:match('^[A-Z0-9]+$') then
        TriggerClientEvent('pedmngr:importCodeResult', src, false, 'Invalid code format.')
        return
    end

    local stored = GetResourceKvpString(KVP_EXPORT_CODE:format(shortCode))
    if not stored then
        TriggerClientEvent('pedmngr:importCodeResult', src, false, 'Code not found on this server.')
        return
    end

    TriggerClientEvent('pedmngr:importCodeResult', src, true, stored)
end)

-- ============================================================
-- EXPORT: GetAppearanceByDbId
-- Allows external resources (e.g. leaderboard) to read saved appearance
-- ============================================================

exports('GetAppearanceByDbId', function(dbId)
    if not dbId then return nil end
    local saved = GetResourceKvpString(KVP_APPEARANCE:format(dbId))
    if not saved then return nil end
    local ok, decoded = pcall(json.decode, saved)
    if ok and type(decoded) == 'table' then return decoded end
    return nil
end)
