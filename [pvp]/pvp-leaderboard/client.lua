-- ============================================================
-- PVP LEADERBOARD — CLIENT
-- NUCLEAR BULLETPROOF: no race conditions, no orphaned peds,
-- no duplicates. EVER.
-- ============================================================

-- ============================================================
-- CONFIG
-- ============================================================

local LEADERBOARD_BASE = {
    x = -2987.7258,
    y = -1448.4520,
    z = 741.4402,
    w = 269.3641,
}

local SLOT_OFFSETS = {
    { dist = -1.5, rank = 1 },
    { dist =  0.0, rank = 2 },
    { dist =  1.5, rank = 3 },
}
local FIRST_PLACE_RAISE = 0.10

local DEFAULT_MODEL = `mp_m_freemode_01`
local DRAW_DIST     = 25.0

-- Purple/white server theme, matching the chat UI palette exactly:
-- #a03cff (accent purple), #f8fafc (white), #e2e8f0 (slate-white),
-- #94a3b8 (muted slate). Rank is conveyed by brightness instead of
-- the old gold/silver/bronze scheme.
local MEDAL = {
    [1] = {186, 130, 255},  -- bright purple highlight (1st)
    [2] = {160,  60, 255},  -- core brand purple (2nd)
    [3] = {100, 116, 139},  -- muted slate (3rd)
}

local THEME = {
    white       = {248, 250, 252},  -- #f8fafc
    slateWhite  = {226, 232, 240},  -- #e2e8f0
    mutedSlate  = {148, 163, 184},  -- #94a3b8
    purple      = {160,  60, 255},  -- #a03cff
}

-- ============================================================
-- STATE
-- ============================================================

local peds        = {}
local leaderData  = {}
local initialized = false
local currentOccupants = {}   -- slot -> "dbId|model" key
local lastAppearanceHash = {} -- slot -> hash string
local allSpawnedPeds = {}     -- ALL peds ever created by this resource

-- ============================================================
-- UTILITY
-- ============================================================

local function OffsetByHeading(baseX, baseY, headingDeg, rightOffset)
    local h = math.rad(headingDeg)
    return baseX + math.cos(h) * rightOffset,
           baseY - math.sin(h) * rightOffset
end

local function Draw3DText(x, y, z, text, scale, r, g, b, alpha)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r or 255, g or 255, b or 255, alpha or 255)
    SetTextOutline()
    SetTextDropShadow()
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(sx, sy)
end

-- ============================================================
-- APPLY APPEARANCE
-- ============================================================

local function ApplyAppearanceToPed(ped, data)
    if not data or not DoesEntityExist(ped) then return end

    if data.components then
        for id, vals in pairs(data.components) do
            SetPedComponentVariation(ped, tonumber(id), vals.drawable or 0, vals.texture or 0, 0)
        end
    end

    if data.props then
        for id, vals in pairs(data.props) do
            if (vals.drawable or -1) == -1 then
                ClearPedProp(ped, tonumber(id))
            else
                SetPedPropIndex(ped, tonumber(id), vals.drawable or 0, vals.texture or 0, true)
            end
        end
    end

    if data.headBlend then
        local hb = data.headBlend
        SetPedHeadBlendData(ped,
            hb.shapeFirst or 0, hb.shapeSecond or 0, 0,
            hb.skinFirst  or 0, hb.skinSecond  or 0, 0,
            hb.shapeMix or 0.5, hb.skinMix or 0.5, 0.0, false)
    end

    if data.faceFeatures then
        for id, scale in pairs(data.faceFeatures) do
            SetPedFaceFeature(ped, tonumber(id), scale or 0.0)
        end
    end

    if data.overlays then
        for id, vals in pairs(data.overlays) do
            local oid = tonumber(id)
            SetPedHeadOverlay(ped, oid, vals.value or 255, vals.opacity or 0.0)
            if vals.colorType and vals.color and (vals.value or 255) ~= 255 then
                SetPedHeadOverlayColor(ped, oid, vals.colorType, vals.color, vals.color2 or vals.color)
            end
        end
    end

    if data.eyeColor then
        SetPedEyeColor(ped, data.eyeColor)
    end

    if data.hairColor or data.hairHighlight then
        SetPedHairColor(ped, data.hairColor or 0, data.hairHighlight or 0)
    end
end

local function ResetPedToBase(ped, model)
    if not DoesEntityExist(ped) then return end
    if model == GetHashKey("mp_m_freemode_01") or model == GetHashKey("mp_f_freemode_01") then
        SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
    end
    SetPedDefaultComponentVariation(ped)
end

-- ============================================================
-- PED MANAGEMENT
-- ============================================================

local function DeletePedByHandle(ped)
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
end

local function DeletePedSlot(slot)
    if peds[slot] then
        DeletePedByHandle(peds[slot])
    end
    peds[slot] = nil
    currentOccupants[slot] = nil
    lastAppearanceHash[slot] = nil
end

local function DeleteAllPeds()
    for i = 1, 3 do
        DeletePedSlot(i)
    end
    -- Also nuke any tracked peds that might have escaped
    for _, ped in ipairs(allSpawnedPeds) do
        DeletePedByHandle(ped)
    end
    allSpawnedPeds = {}
    initialized = false
end

-- NUCLEAR: find and delete ANY peds near our slots that we don't own
local function NukeOrphanedPeds()
    -- FIX: this used to do `for i = 0, 255 do if DoesEntityExist(i) ...`,
    -- treating raw integers 0-255 as if they were entity handles. Real
    -- FiveM/GTA entity handles are NOT small sequential integers, and
    -- calling natives like DoesEntityExist on fake ones is exactly what
    -- was crashing the native (DOES_ENTITY_EXIST, hash 7239b21a38f536ba)
    -- every single refresh -- silently, since it happened before any of
    -- the appearance-update code below it in DoRefreshPeds ever got a
    -- chance to run. GetGamePool('CPed') returns the real list of every
    -- ped that currently exists, which is what should be iterated.
    local allPeds = GetGamePool('CPed')
    for _, i in ipairs(allPeds) do
        if IsPedHuman(i) and not IsPedAPlayer(i) then
            local pos = GetEntityCoords(i)
            for _, offset in ipairs(SLOT_OFFSETS) do
                local wx, wy = OffsetByHeading(
                    LEADERBOARD_BASE.x, LEADERBOARD_BASE.y,
                    LEADERBOARD_BASE.w, offset.dist)
                local wz = LEADERBOARD_BASE.z
                if offset.rank == 1 then wz = wz + FIRST_PLACE_RAISE end
                local dist = #(pos - vector3(wx, wy, wz))
                if dist < 2.0 then
                    -- Check if this is one of our tracked peds
                    local isOurs = false
                    for slot = 1, 3 do
                        if peds[slot] == i then
                            isOurs = true
                            break
                        end
                    end
                    if not isOurs then
                        DeleteEntity(i)
                    end
                end
            end
        end
    end
end

local function GetOccKey(entry)
    if not entry then return nil end
    local id = entry.dbId and tostring(entry.dbId) or entry.name or "unknown"
    local model = entry.appearance and entry.appearance.model or DEFAULT_MODEL
    return id .. "|" .. tostring(model)
end

local function HashAppearance(data)
    if not data then return "nil" end
    local parts = {}
    if data.model then table.insert(parts, "m:" .. tostring(data.model)) end
    if data.components then
        for id = 0, 11 do
            local c = data.components[tostring(id)]
            if c then
                table.insert(parts, "c" .. id .. ":" .. (c.drawable or 0) .. "," .. (c.texture or 0))
            end
        end
    end
    if data.props then
        for id = 0, 7 do
            local p = data.props[tostring(id)]
            if p then
                table.insert(parts, "p" .. id .. ":" .. (p.drawable or -1) .. "," .. (p.texture or 0))
            end
        end
    end
    if data.hairColor then table.insert(parts, "hc:" .. tostring(data.hairColor)) end
    if data.hairHighlight then table.insert(parts, "hh:" .. tostring(data.hairHighlight)) end
    if data.eyeColor then table.insert(parts, "ec:" .. tostring(data.eyeColor)) end
    if data.headBlend then
        local hb = data.headBlend
        table.insert(parts, "hb:" .. (hb.shapeFirst or 0) .. "," .. (hb.shapeSecond or 0) .. "," .. (hb.skinFirst or 0) .. "," .. (hb.skinSecond or 0))
    end
    if data.faceFeatures then
        for id = 0, 19 do
            local ff = data.faceFeatures[tostring(id)]
            if ff then
                table.insert(parts, "ff" .. id .. ":" .. string.format("%.3f", ff))
            end
        end
    end
    if data.overlays then
        for id = 0, 12 do
            local ov = data.overlays[tostring(id)]
            if ov then
                table.insert(parts, "ov" .. id .. ":" .. (ov.value or 255) .. "," .. string.format("%.2f", ov.opacity or 0))
            end
        end
    end
    return table.concat(parts, "|")
end

-- ============================================================
-- REFRESH PEDS — BULLETPROOF
-- ============================================================

local refreshBusy   = false
local pendingRefresh = nil

local function RefreshPeds(data)
    -- GUARD: if a refresh is already mid-spawn (waiting on RequestModel /
    -- the post-spawn settle Wait), don't start a second one for the same
    -- slot. Net events fire as their own coroutine in FiveM, so without
    -- this lock, two 'pvp-leaderboard:update' events arriving close
    -- together (e.g. the resource-start requestRefresh and the periodic
    -- broadcast loop firing right after a restart) can both pass the
    -- "occupant changed" check before either finishes, and both CreatePed
    -- for the same slot -> duplicate ped, one of which ends up untracked
    -- and either gets nuked next cycle or wanders off as ambient AI.
    if refreshBusy then
        pendingRefresh = data
        return
    end
    refreshBusy = true

    local ok, err = pcall(DoRefreshPeds, data)
    if not ok then
        print('[PVP-LEADERBOARD] RefreshPeds error: ' .. tostring(err))
    end

    refreshBusy = false

    if pendingRefresh then
        local nextData = pendingRefresh
        pendingRefresh = nil
        RefreshPeds(nextData)
    end
end

function DoRefreshPeds(data)
    leaderData = data or {}

    -- NUCLEAR: kill any peds near our slots that aren't tracked
    NukeOrphanedPeds()

    -- DEDUP by dbId
    local usedDbIds = {}
    for slot, offset in ipairs(SLOT_OFFSETS) do
        local entry = leaderData[offset.rank]
        if entry and entry.dbId then
            if usedDbIds[entry.dbId] then
                leaderData[offset.rank] = nil
            else
                usedDbIds[entry.dbId] = true
            end
        end
    end

    for slot, offset in ipairs(SLOT_OFFSETS) do
        local entry = leaderData[offset.rank]
        local newKey = GetOccKey(entry)
        local newHash = HashAppearance(entry and entry.appearance or nil)

        if newKey ~= currentOccupants[slot] then
            -- Occupant changed
            DeletePedSlot(slot)

            if entry and entry.appearance then
                local wx, wy = OffsetByHeading(
                    LEADERBOARD_BASE.x, LEADERBOARD_BASE.y,
                    LEADERBOARD_BASE.w, offset.dist)
                local wz = LEADERBOARD_BASE.z
                if offset.rank == 1 then wz = wz + FIRST_PLACE_RAISE end

                -- Spawn ped inline so we can track it BEFORE any Wait()
                local model = entry.appearance.model or DEFAULT_MODEL
                RequestModel(model)
                local t = 0
                while not HasModelLoaded(model) and t < 100 do
                    Wait(10); t = t + 1
                end

                -- FIX ("glitch man with components"): if the player's real model
                -- (e.g. mp_f_freemode_01) doesn't stream in within the timeout above,
                -- we used to silently fall back to DEFAULT_MODEL (always the MALE
                -- ped) and then STILL apply the original appearance's component/prop
                -- data on top of it. Male and female peds use different meanings for
                -- the same component IDs, so that mismatch is exactly what produced
                -- a broken-looking male ped wearing nonsense female clothing pieces.
                local modelLoadFailed = false
                if not HasModelLoaded(model) then
                    modelLoadFailed = true
                    model = DEFAULT_MODEL
                    RequestModel(model)
                    t = 0
                    while not HasModelLoaded(model) and t < 50 do
                        Wait(10); t = t + 1
                    end
                end

                local ped = CreatePed(4, model, wx, wy, wz - 1.0, LEADERBOARD_BASE.w, false, false)

                -- TRACK IMMEDIATELY — before any yield
                peds[slot] = ped
                table.insert(allSpawnedPeds, ped)

                if modelLoadFailed then
                    -- Don't lock this in as "done" — leave currentOccupants/lastAppearanceHash
                    -- unset so the NEXT refresh cycle treats this as a changed occupant
                    -- again and retries the real model + appearance from scratch, instead
                    -- of getting stuck showing the mismatched fallback forever.
                    currentOccupants[slot] = nil
                    lastAppearanceHash[slot] = nil
                else
                    currentOccupants[slot] = newKey
                    lastAppearanceHash[slot] = newHash
                end

                if DoesEntityExist(ped) then
                    FreezeEntityPosition(ped, true)
                    SetEntityInvincible(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedCanRagdoll(ped, false)
                    SetPedCanBeTargetted(ped, false)
                    SetEntityCollision(ped, false, false)
                    NetworkSetEntityInvisibleToNetwork(ped, true)
                    SetEntityAsMissionEntity(ped, true, true)

                    Wait(500)
                    if DoesEntityExist(ped) then
                        ResetPedToBase(ped, model)
                        -- Only apply the saved appearance if we actually got the
                        -- model it was made for — never onto the fallback model.
                        if not modelLoadFailed then
                            ApplyAppearanceToPed(ped, entry.appearance)
                        end
                        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
                    end
                end

                SetModelAsNoLongerNeeded(model)
            end
        elseif entry and peds[slot] and DoesEntityExist(peds[slot]) and entry.appearance then
            -- Same occupant — check if clothes changed
            if newHash ~= lastAppearanceHash[slot] then
                ApplyAppearanceToPed(peds[slot], entry.appearance)
                lastAppearanceHash[slot] = newHash
            end
        end
    end

    initialized = true
end

-- ============================================================
-- EVENTS
-- ============================================================

RegisterNetEvent('pvp-leaderboard:update')
AddEventHandler('pvp-leaderboard:update', function(top3)
    RefreshPeds(top3)
end)

-- ============================================================
-- DRAW LOOP
-- ============================================================

CreateThread(function()
    while not initialized do Wait(500) end

    local medals = {"#1", "#2", "#3"}

    while true do
        Wait(0)

        local playerPos = GetEntityCoords(PlayerPedId())

        for slot, offset in ipairs(SLOT_OFFSETS) do
            local ped = peds[slot]
            if not ped or not DoesEntityExist(ped) then goto cont end

            local pedPos = GetEntityCoords(ped)
            local dist   = #(playerPos - pedPos)
            if dist > DRAW_DIST then goto cont end

            local alpha = 255
            if dist > DRAW_DIST * 0.6 then
                alpha = math.floor(255 * (1.0 - (dist - DRAW_DIST * 0.6) / (DRAW_DIST * 0.4)))
            end

            local rank  = offset.rank
            local entry = leaderData[rank]
            local mc    = MEDAL[rank] or THEME.white

            Draw3DText(pedPos.x, pedPos.y, pedPos.z + 2.30,
                medals[rank] or ("#" .. rank),
                0.55, mc[1], mc[2], mc[3], alpha)

            if entry then
                local kills  = entry.globalKills  or 0
                local deaths = entry.globalDeaths or 0
                local kd     = entry.kd or (deaths == 0 and kills or
                               math.floor((kills / math.max(deaths,1)) * 100) / 100)

                Draw3DText(pedPos.x, pedPos.y, pedPos.z + 2.05,
                    entry.name or "—",
                    0.45, THEME.white[1], THEME.white[2], THEME.white[3], alpha)

                Draw3DText(pedPos.x, pedPos.y, pedPos.z + 1.80,
                    ("Kills: %d  |  Deaths: %d"):format(kills, deaths),
                    0.36, THEME.slateWhite[1], THEME.slateWhite[2], THEME.slateWhite[3], alpha)

                Draw3DText(pedPos.x, pedPos.y, pedPos.z + 1.60,
                    ("K/D: %.2f"):format(kd),
                    0.38, mc[1], mc[2], mc[3], alpha)
            else
                Draw3DText(pedPos.x, pedPos.y, pedPos.z + 2.05,
                    "— Empty —", 0.40, THEME.mutedSlate[1], THEME.mutedSlate[2], THEME.mutedSlate[3], alpha)
            end

            ::cont::
        end
    end
end)

-- ============================================================
-- RESOURCE START / STOP
-- ============================================================

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    print('[PVP-LEADERBOARD] Starting…')
    Wait(4000)
    TriggerServerEvent('pvp-leaderboard:requestRefresh')
    print('[PVP-LEADERBOARD] Refresh requested from server.')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    DeleteAllPeds()
    print('[PVP-LEADERBOARD] Peds cleaned up.')
end)
