
-- TURF WARS GAMEMODE  (CLIENT)
-- Server-synchronized territorial capture mode.
--
-- FEATURES:
--   - All players share the same rotating map and timer
--   - Visible see-through globe/sphere around capture zone
--   - Smart respawns OUTSIDE the radius edge
--   - Player godmode UNTIL they enter the radius
--   - Firing disabled while outside radius
--   - NPC entry point  (E to Enter TurfWars)
--   - [F4] Weapon arsenal menu (turf-only)
--   - Modern NUI badge for turf name + timer
--   - Weapon persistence thread
--   - Slow-motion effect during last 3 seconds of each map
--   - Health gain on kill (player or NPC)
--   - Player weapon drops disabled globally
--   - Auto-leave when pvp-core state changes to "hub"
--
-- NPC STANDING:   -2978.7561, -1426.5748, 634.8070,  82.8362
-- NPC FACING:     -2987.0718, -1426.3735, 635.4677, 271.1736
-- ============================================================

-- ============================================================
-- MAPS  (must match server-side TURF_MAPS)
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

-- ============================================================
-- MANUAL SPAWN POINTS — Nuketown & Racetrack ONLY
-- Captured with pvp-debug (F7 freecam tool), each one already
-- placed facing the turf's middle/radius. Every other map keeps
-- the normal procedural ring-spawn logic in FindOutsideSpawnPoint
-- below — this list is only consulted for the two map names
-- used as keys here.
-- ============================================================
local MANUAL_SPAWNS = {
    ["Nuketown"] = {
        { x = -3221.62, y = 7037.68, z = 636.62, h = 118.32 }, -- #1
        { x = -3224.63, y = 7040.52, z = 636.62, h = 90.73 },  -- #2
        { x = -3228.62, y = 7043.76, z = 636.62, h = 75.11 },  -- #3
        { x = -3244.59, y = 7049.78, z = 636.62, h = 73.72 },  -- #4
        { x = -3241.20, y = 7055.22, z = 636.62, h = 43.86 },  -- #5
        { x = -3235.54, y = 7051.25, z = 636.62, h = 30.57 },  -- #6
        { x = -3291.24, y = 7014.87, z = 636.62, h = 237.63 }, -- #7
        { x = -3290.18, y = 7019.54, z = 636.63, h = 252.81 }, -- #8
        { x = -3289.56, y = 7029.02, z = 636.72, h = 284.43 }, -- #9
        { x = -3299.06, y = 7029.10, z = 636.62, h = 300.56 }, -- #10
        { x = -3301.44, y = 7021.01, z = 636.62, h = 241.34 }, -- #11
        { x = -3307.26, y = 7014.87, z = 636.62, h = 195.99 }, -- #12
        { x = -3306.34, y = 7030.60, z = 636.62, h = 318.82 }, -- #13
        { x = -3280.57, y = 6983.55, z = 636.62, h = 339.74 }, -- #14
        { x = -3266.49, y = 6972.16, z = 636.62, h = 5.82 },   -- #15
        { x = -3265.53, y = 6962.91, z = 636.62, h = 5.25 },   -- #16
        { x = -3259.38, y = 6963.54, z = 636.62, h = 4.18 },   -- #17
        { x = -3253.68, y = 6968.71, z = 636.62, h = 352.46 }, -- #18
        { x = -3250.36, y = 6968.03, z = 636.62, h = 353.09 }, -- #19
        { x = -3243.52, y = 6967.52, z = 636.62, h = 353.60 }, -- #20
        { x = -3240.65, y = 6969.43, z = 636.62, h = 350.38 }, -- #21
        { x = -3240.10, y = 7048.52, z = 636.62, h = 165.94 }, -- #22
        { x = -3287.19, y = 7027.71, z = 636.72, h = 244.24 }, -- #23
        { x = -3267.91, y = 6967.16, z = 636.62, h = 3.48 },   -- #24
        { x = -3263.41, y = 6967.82, z = 636.62, h = 11.80 },  -- #25
    },
    ["Racetrack"] = {
        { x = 950.79,  y = 2311.42, z = 51.82, h = 346.10 }, -- #26
        { x = 955.89,  y = 2305.63, z = 52.26, h = 333.00 }, -- #27
        { x = 960.82,  y = 2304.72, z = 51.34, h = 335.14 }, -- #28
        { x = 966.88,  y = 2301.73, z = 51.49, h = 346.23 }, -- #29
        { x = 974.68,  y = 2300.53, z = 51.34, h = 352.91 }, -- #30
        { x = 981.45,  y = 2299.93, z = 51.34, h = 357.13 }, -- #31
        { x = 989.49,  y = 2302.57, z = 51.37, h = 1.47 },   -- #32
        { x = 996.70,  y = 2302.78, z = 51.35, h = 2.54 },   -- #33
        { x = 1000.43, y = 2306.03, z = 52.06, h = 14.64 },  -- #34
        { x = 1004.15, y = 2310.54, z = 52.29, h = 30.26 },  -- #35
        { x = 1019.82, y = 2329.11, z = 51.60, h = 71.39 },  -- #36
        { x = 1021.27, y = 2335.75, z = 51.58, h = 65.09 },  -- #37
        { x = 1022.74, y = 2346.93, z = 51.53, h = 96.40 },  -- #38
        { x = 1021.88, y = 2351.02, z = 51.43, h = 98.80 },  -- #39
        { x = 1020.68, y = 2357.15, z = 51.44, h = 101.32 }, -- #40
        { x = 1017.25, y = 2364.65, z = 51.40, h = 117.76 }, -- #41
        { x = 1013.29, y = 2370.32, z = 51.40, h = 118.95 }, -- #42
        { x = 994.87,  y = 2381.27, z = 51.42, h = 168.21 }, -- #43
        { x = 989.59,  y = 2382.38, z = 51.42, h = 167.96 }, -- #44
        { x = 982.33,  y = 2383.69, z = 51.35, h = 169.41 }, -- #45
        { x = 975.83,  y = 2382.88, z = 51.34, h = 182.20 }, -- #46
        { x = 969.61,  y = 2380.84, z = 51.34, h = 192.28 }, -- #47
        { x = 963.30,  y = 2378.08, z = 51.34, h = 194.48 }, -- #48
        { x = 957.91,  y = 2373.68, z = 51.34, h = 203.68 }, -- #49
        { x = 952.79,  y = 2367.95, z = 51.43, h = 155.61 }, -- #50
        { x = 953.04,  y = 2317.46, z = 51.40, h = 306.23 }, -- #51
        { x = 947.95,  y = 2313.53, z = 51.95, h = 292.24 }, -- #52
        { x = 950.69,  y = 2306.99, z = 51.68, h = 292.37 }, -- #53
        { x = 978.20,  y = 2302.96, z = 51.34, h = 6.89 },   -- #54
    },
}

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    defaultRadius    = 50.0,
    minRadius        = 10.0,
    maxRadius        = 200.0,
    mapDuration      = 120,

    spawnOuterPad    = 5.0,
    respawnRingCount = 12,
    globeZOffset     = -20.0,

    npcStandPos  = vector4(-2975.6699, -1451.1866, 741.2396, 89.0537),
    npcFacePos   = vector4(-2975.6699, -1451.1866, 741.4396, 89.0537),
    npcModel     = `S_M_M_MovSpace_01`,  -- matches the hub's Redzone NPC look
    npcName      = "Turf Wars",
    interactDist = 2.5,
    promptDist   = 15.0,
}

-- ============================================================
-- STATE
-- ============================================================
local TURF = {
    active        = false,
    currentMap    = 1,
    radius        = CONFIG.defaultRadius,
    centerPos     = nil,
    mapHeading    = 0.0,

    inRadius      = false,
    godmode       = true,
    isDead        = false,
    isRespawning  = false,

    mapStartTime  = 0,
    serverTimeRemaining = 0,

    sphereProps   = {},
    npcEntity     = nil,
    npcInitDone   = false,
    enemiesActive = false,

    menuOpen      = false,
    equippedHash  = nil,
    equippedName  = "None",

    slomo         = false,
}

-- ============================================================
-- DISABLE WEAPON DROPS GLOBALLY
-- ============================================================
Citizen.CreateThread(function()
    local lastNpcScan = 0
    while true do
        Citizen.Wait(0)
        local ped = PlayerPedId()
        SetPedDropsWeaponsWhenDead(ped, false)

        local now = GetGameTimer()
        if now - lastNpcScan > 2000 then
            lastNpcScan = now
            local allPeds = GetGamePool("CPed")
            for _, p in ipairs(allPeds) do
                if p ~= ped then
                    SetPedDropsWeaponsWhenDead(p, false)
                end
            end
        end
    end
end)

-- ============================================================
-- HELPERS
-- ============================================================
local function GetAngleOnRing(angleDeg, cx, cy, cz, r, isMLO)
    local rad = math.rad(angleDeg)
    local wx  = cx + math.cos(rad) * r
    local wy  = cy + math.sin(rad) * r
    local wz  = cz

    -- For MLOs/interiors, trust the center Z instead of ground Z (prevents snapping to terrain below)
    if not isMLO then
        local found, groundZ = GetGroundZFor_3dCoord(wx, wy, wz + 50.0, false)
        if found then wz = groundZ + 0.5 end
    end

    return wx, wy, wz, true
end

local function IsInWater(x, y, z)
    local found, waterHeight = GetWaterHeight(x, y, z)
    if found and waterHeight >= z - 1.0 then
        return true
    end
    return false
end

local function HorizDistToCenter(pos)
    if not TURF.centerPos then return 9999 end
    local dx = pos.x - TURF.centerPos.x
    local dy = pos.y - TURF.centerPos.y
    return math.sqrt(dx*dx + dy*dy)
end

local function DistToCenter(pos)
    if not TURF.centerPos then return 9999 end
    local dx = pos.x - TURF.centerPos.x
    local dy = pos.y - TURF.centerPos.y
    local dz = pos.z - TURF.centerPos.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function HeadingToCenter(sx, sy, cx, cy)
    return GetHeadingFromVector_2d(
        cx - sx,
        cy - sy
    )
end

local function FindOutsideSpawnPoint(attempts)
    -- Manual override: Nuketown & Racetrack only ever use the
    -- hand-placed list above. Every other map name falls through
    -- to the normal procedural ring spawn untouched.
    local mapName    = TURF_MAPS[TURF.currentMap] and TURF_MAPS[TURF.currentMap].name
    local manualList = mapName and MANUAL_SPAWNS[mapName]

    if manualList and #manualList > 0 then
        local pick = manualList[math.random(1, #manualList)]
        return pick.x, pick.y, pick.z, pick.h
    end

    attempts = attempts or 50
    local cx = TURF.centerPos.x
    local cy = TURF.centerPos.y
    local cz = TURF.centerPos.z
    local r  = TURF.radius
    local spawnDist = r + CONFIG.spawnOuterPad
    local maxZDiff = 5.0

    -- Detect if this map center is inside an MLO/interior
    local interior = GetInteriorAtCoords(cx, cy, cz)
    local isMLO = (interior ~= 0 and IsValidInterior(interior))

    for attempt = 1, attempts do
        local angleDeg = math.random(0, 359)
        local wx, wy, wz, groundFound = GetAngleOnRing(angleDeg, cx, cy, cz, spawnDist, isMLO)

        if not groundFound then goto continue end
        if IsInWater(wx, wy, wz) then goto continue end

        if not isMLO and math.abs(wz - cz) > maxZDiff then goto continue end

        local dx = wx - cx
        local dy = wy - cy
        local dist2d = math.sqrt(dx*dx + dy*dy)

        if dist2d >= r then
            return wx, wy, wz, angleDeg
        end

        ::continue::
    end

    -- Fallback: systematic angles
    for attempt = 1, attempts do
        local angleDeg = (attempt * 137) % 360
        local wx, wy, wz, groundFound = GetAngleOnRing(angleDeg, cx, cy, cz, spawnDist, isMLO)

        if not groundFound then goto fallback_continue end
        if IsInWater(wx, wy, wz) then goto fallback_continue end
        if not isMLO and math.abs(wz - cz) > maxZDiff then goto fallback_continue end

        local dx = wx - cx
        local dy = wy - cy
        local dist2d = math.sqrt(dx*dx + dy*dy)

        if dist2d >= r then
            return wx, wy, wz, angleDeg
        end

        ::fallback_continue::
    end

    -- Ultimate fallback
    local angleDeg = math.random(0, 359)
    local rad = math.rad(angleDeg)
    local wx = cx + math.cos(rad) * spawnDist
    local wy = cy + math.sin(rad) * spawnDist
    local wz = cz + 0.5

    if not isMLO then
        local found, groundZ = GetGroundZFor_3dCoord(wx, wy, cz + 100.0, false)
        if found and math.abs(groundZ - cz) <= maxZDiff then
            wz = groundZ + 0.5
        end
    end

    return wx, wy, wz, angleDeg
end

local function Notify(msg, r, g, b)
    TriggerEvent("chat:addMessage", {
        color = {r or 255, g or 200, b or 50},
        args  = {"[TURF]", msg}
    })
end

-- ============================================================
-- SAFE TELEPORT / SPAWN  (MLO + COLLISION HARDENED)
-- ============================================================
local function SafeTeleportToSpawn(x, y, z, heading)
    local ped = PlayerPedId()

    -- Force streaming engine to target area
    if SetFocusPosAndVel then
        SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    end

    -- Pre-request collision
    RequestCollisionAtCoord(x, y, z)

    -- Detect & load interior / MLO
    local interior = GetInteriorAtCoords(x, y, z)
    local isMLO = (interior ~= 0 and IsValidInterior(interior))

    if isMLO then
        PinInteriorInMemory(interior)
        RefreshInterior(interior)
        local intTimer = GetGameTimer()
        while not IsInteriorReady(interior) and (GetGameTimer() - intTimer) < 5000 do
            Citizen.Wait(0)
        end
    end

    -- Pre-set coords to trigger area loading
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)

    -- Resurrect / place player
    NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
    Citizen.Wait(100)

    -- Re-acquire ped handle (can change after resurrection)
    ped = PlayerPedId()

    -- HARD FREEZE + DISABLE COLLISION while floor loads (prevents falling through)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    SetEntityHeading(ped, heading)

    -- Aggressive collision + interior loading loop
    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(x, y, z)
        if isMLO then
            RefreshInterior(interior)
        end
        Citizen.Wait(0)
    end

    -- Extra settle time for MLOs so geometry fully loads
    if isMLO then
        Citizen.Wait(600)
    else
        Citizen.Wait(200)
    end

    -- Re-enable collision now that floor should be loaded
    SetEntityCollision(ped, true, true)

    -- Final position lock before unfreeze
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    SetEntityHeading(ped, heading)

    -- Verify we didn't fall through during load
    local pos = GetEntityCoords(ped)
    if math.abs(pos.z - z) > 5.0 then
        -- Fell through during load, force back up
        SetEntityCoordsNoOffset(ped, x, y, z + 1.0, false, false, false, true)
        NetworkResurrectLocalPlayer(x, y, z + 1.0, heading, true, true, false)
        Citizen.Wait(100)
        ped = PlayerPedId()
        SetEntityHeading(ped, heading)
    end

    FreezeEntityPosition(ped, false)

    if ClearFocus then
        ClearFocus()
    end

    return x, y, z
end

-- ============================================================
-- NUI HELPERS
-- ============================================================
local function SendNUI(data)
    SendNUIMessage(data)
end

local function ShowTurfBadge(mapName, secondsLeft)
    local mins = math.floor(secondsLeft / 60)
    local secs = math.floor(secondsLeft % 60)
    SendNUI({
        type     = "showTurfBadge",
        mapName  = mapName,
        timerStr = string.format("%02d:%02d", mins, secs),
    })
end

local function HideTurfBadge()
    SendNUI({ type = "hideTurfBadge" })
end

local function UpdateBadgeTimer(secondsLeft, mapName)
    local mins = math.floor(secondsLeft / 60)
    local secs = math.floor(secondsLeft % 60)
    SendNUI({
        type        = "updateTimer",
        timerStr    = string.format("%02d:%02d", mins, secs),
        secondsLeft = secondsLeft,
        mapName     = mapName,
    })
end

-- ============================================================
-- GLOBE RENDERER
-- ============================================================
local function DrawTurfGlobe()
    if not TURF.active or not TURF.centerPos then return end
    local cx   = TURF.centerPos.x
    local cy   = TURF.centerPos.y
    local cz   = TURF.centerPos.z + CONFIG.globeZOffset
    local diam = TURF.radius * 2.0

    DrawMarker(
        1,
        cx, cy, cz,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        diam, diam, diam,
        160, 0, 255, 40,
        false, false, 2, false, nil, nil, false
    )
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if TURF.active then
            DrawTurfGlobe()
        end
    end
end)

-- ============================================================
-- NUI BADGE TIMER UPDATER (synced from server)
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if TURF.active and TURF_MAPS[TURF.currentMap] then
            TURF.serverTimeRemaining = math.max(0, TURF.serverTimeRemaining - 1)
            UpdateBadgeTimer(TURF.serverTimeRemaining, TURF_MAPS[TURF.currentMap].name)
        end
    end
end)

-- ============================================================
-- F4 WEAPON MENU TOGGLE
-- ============================================================
RegisterKeyMapping("turfmenu", "Turf Wars Arsenal Menu", "keyboard", "F4")

-- NEW: tracks which weapons this player owns, per pvp-shop.
-- Refreshed each time the menu opens so it's never stale for long.
local OwnedWeapons = {}
local pendingEquipName = nil

RegisterNetEvent('pvp-shop:ownedList')
AddEventHandler('pvp-shop:ownedList', function(owned)
    OwnedWeapons = owned or {}
    SendNUI({ type = "updateOwnedWeapons", owned = OwnedWeapons })
end)

RegisterCommand("turfmenu", function()
    if not TURF.active then return end
    TURF.menuOpen = not TURF.menuOpen
    if TURF.menuOpen then
        TriggerServerEvent('pvp-shop:requestOwnedList')
        TriggerServerEvent('pvp-shop:requestBalance')
    end
    SendNUI({ type = "toggleWeaponMenu" })
    SetNuiFocus(TURF.menuOpen, TURF.menuOpen)
end, false)

RegisterNUICallback("turfRequestBalance", function(_, cb)
    TriggerServerEvent('pvp-shop:requestBalance')
    cb({})
end)

RegisterNetEvent('pvp-shop:balanceResult')
AddEventHandler('pvp-shop:balanceResult', function(balance)
    SendNUI({ type = "updateBalance", balance = balance })
end)

-- pvp-economy fires this on every balance change (kill rewards, round
-- win/top-3 bonuses, shop purchases -- anything that touches money).
-- Listening directly here keeps the in-gameplay cash HUD live without
-- having to poll, even when the arsenal menu is closed.
RegisterNetEvent('pvp-economy:moneyUpdated')
AddEventHandler('pvp-economy:moneyUpdated', function(newBalance)
    if not TURF.active then return end
    SendNUI({ type = "updateBalance", balance = newBalance })
end)

RegisterNUICallback("closeMenu", function(_, cb)
    TURF.menuOpen = false
    SetNuiFocus(false, false)
    SendNUI({ type = "closeWeaponMenu" })
    cb({})
end)

-- ============================================================
-- SUPPRESS PAUSE MENU WHILE ARSENAL IS OPEN
-- Escape closes the arsenal from inside the NUI itself, but Escape
-- is also the default pause-menu bind -- without this, closing the
-- arsenal with Escape would pop FiveM's native pause menu at the
-- same time.
-- ============================================================
CreateThread(function()
    while true do
        Wait(0)
        if TURF.menuOpen then
            DisableControlAction(0, 200, true)  -- INPUT_FRONTEND_PAUSE
            DisableControlAction(0, 322, true)  -- INPUT_FRONTEND_PAUSE_ALTERNATE
        end
    end
end)

RegisterNUICallback("turfWeaponSelected", function(data, cb)
    if not TURF.active then cb({}) return end

    local hash = data.hash
    local name = data.name

    if not OwnedWeapons[hash] then
        Notify("~r~You don't own " .. name .. " yet. Buy it in the shop first.", 255, 60, 60)
        cb({})
        return
    end

    -- Ask the server to confirm before equipping. This is the real
    -- gate -- even if OwnedWeapons were somehow tampered with on this
    -- client, the server checks its own KVP-backed ownership record
    -- in pvp-shop before pvp-shop:equipApproved fires.
    pendingEquipName = name
    TriggerServerEvent('pvp-shop:requestEquip', hash)
    cb({})
end)

RegisterNetEvent('pvp-shop:equipApproved')
AddEventHandler('pvp-shop:equipApproved', function(hash)
    local ped = PlayerPedId()

    RemoveAllPedWeapons(ped, true)
    Citizen.Wait(50)

    local weaponHash = GetHashKey(hash)
    GiveWeaponToPed(ped, weaponHash, 9999, false, true)
    SetPedAmmo(ped, weaponHash, 9999)
    SetCurrentPedWeapon(ped, weaponHash, true)

    TURF.equippedHash = weaponHash
    TURF.equippedName = pendingEquipName or hash

    Notify("Equipped: ~y~" .. (pendingEquipName or hash), 160, 60, 255)
    pendingEquipName = nil
end)

RegisterNetEvent('pvp-shop:equipDenied')
AddEventHandler('pvp-shop:equipDenied', function(hash)
    Notify("~r~Equip denied -- you don't own this weapon.", 255, 60, 60)
    pendingEquipName = nil
end)

RegisterNUICallback("turfWeaponPurchase", function(data, cb)
    TriggerServerEvent('pvp-shop:purchaseWeapon', data.hash)
    cb({})
end)

RegisterNetEvent('pvp-shop:purchaseResult')
AddEventHandler('pvp-shop:purchaseResult', function(success, reasonText, hash)
    if success then
        Notify("~g~Purchased! Open the menu again to equip it.", 60, 220, 100)
        TriggerServerEvent('pvp-shop:requestOwnedList')
        TriggerServerEvent('pvp-shop:requestBalance')
    else
        SendNUI({ type = "purchaseFailed", reasonText = reasonText })
        Notify("~r~Purchase failed: " .. (reasonText or "unknown"), 255, 60, 60)
    end
end)

-- ============================================================
-- WEAPON PERSISTENCE THREAD
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if TURF.active and TURF.equippedHash and not TURF.isDead then
            local ped     = PlayerPedId()
            local current = GetSelectedPedWeapon(ped)

            if current ~= TURF.equippedHash then
                if not HasPedGotWeapon(ped, TURF.equippedHash, false) then
                    GiveWeaponToPed(ped, TURF.equippedHash, 9999, false, true)
                end
                SetPedAmmo(ped, TURF.equippedHash, 9999)
                SetCurrentPedWeapon(ped, TURF.equippedHash, true)
            end
        end
    end
end)

-- ============================================================
-- INFINITE AMMO
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(250)
        if TURF.active then
            local ped    = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)
            if weapon ~= GetHashKey("WEAPON_UNARMED") then
                SetPedAmmo(ped, weapon, 9999)
            end
        end
    end
end)

-- ============================================================
-- HEALTH GAIN ON KILL
-- ============================================================
Citizen.CreateThread(function()
    local trackedPeds = {}
    while true do
        Citizen.Wait(200)
        if not TURF.active then
            trackedPeds = {}
            goto continue
        end

        local ped     = PlayerPedId()
        local allPeds = GetGamePool("CPed")

        for _, target in ipairs(allPeds) do
            if target == ped then goto nextped end

            local hp = GetEntityHealth(target)

            if hp > 0 then
                trackedPeds[target] = hp
            elseif trackedPeds[target] and trackedPeds[target] > 0 then
                trackedPeds[target] = 0

                local currentHP = GetEntityHealth(ped)
                local maxHP     = GetEntityMaxHealth(ped)
                local missingHP = maxHP - currentHP
                local reward    = 100  -- total HP reward per kill

                if missingHP > 0 then
                    -- Fill health first, overflow goes to armor
                    local hpGain = math.min(missingHP, reward)
                    SetEntityHealth(ped, currentHP + hpGain)

                    local overflow = reward - hpGain
                    if overflow > 0 then
                        local armour = GetPedArmour(ped)
                        SetPedArmour(ped, math.min(100, armour + overflow))
                    end
                else
                    -- Already full HP, dump entire reward into armor
                    local armour = GetPedArmour(ped)
                    SetPedArmour(ped, math.min(100, armour + reward))
                end
            end
            ::nextped::
        end
        ::continue::
    end
end)

-- ============================================================
-- GODMODE / INSIDE-RADIUS TRACKER
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if not TURF.active then goto continue end

        local ped    = PlayerPedId()
        local pos    = GetEntityCoords(ped)
        local dist   = DistToCenter(pos)
        local inside = dist <= TURF.radius

        if inside and TURF.godmode then
            TURF.godmode  = false
            TURF.inRadius = true
            SetPlayerInvincible(PlayerId(), false)
            SetEntityInvincible(ped, false)
            

        elseif not inside and not TURF.godmode and not TURF.isDead then
            TURF.godmode  = true
            TURF.inRadius = false
            SetPlayerInvincible(PlayerId(), true)
            SetEntityInvincible(ped, true)
            

        elseif not inside and TURF.godmode and not TURF.isDead then
            SetPlayerInvincible(PlayerId(), true)
            SetEntityInvincible(ped, true)
        end
        ::continue::
    end
end)

-- ============================================================
-- DISABLE FIRING OUTSIDE RADIUS
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if TURF.active and TURF.godmode then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 106, true)
            DisableControlAction(0, 107, true)
        end
    end
end)

-- ============================================================
-- DEATH TRACKER
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if not TURF.active then goto continue end

        local ped  = PlayerPedId()
        local dead = IsEntityDead(ped) or GetEntityHealth(ped) <= 0

        if dead and not TURF.isDead then
            TURF.isDead  = true
            TURF.godmode = false
        elseif not dead and TURF.isDead and not TURF.isRespawning then
            TURF.isDead = false
        end
        ::continue::
    end
end)

-- ============================================================
-- DEATH HINT
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if TURF.active and TURF.isDead then
            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 60, 60, 230)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName("~r~Press ~w~[R] ~r~to Respawn")
            EndTextCommandDisplayText(0.5, 0.55)
        end
    end
end)

-- ============================================================
-- RESPAWN KEY HANDLER (R key)
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if TURF.active then
            if IsControlJustPressed(0, 45) then
                if TURF.isDead and not TURF.isRespawning then
                    TriggerServerEvent('turfwars:requestRespawn')
                elseif not TURF.isDead then
                   Wait(4) 
                end
            end
        end
    end
end)

-- ============================================================
-- SMART RESPAWN
-- ============================================================
function RespawnOutsideRadius(mapData)
    if not TURF.active or TURF.isRespawning then return end
    if not TURF.centerPos then return end
    -- Don't respawn on top of an enter/leave that's already mid-flight elsewhere
    if exports["pvp-core"]:IsPlayerTransitioning() then return end

    exports["pvp-core"]:SetPlayerTransitioning(true)
    TURF.isRespawning = true

    DoScreenFadeOut(300)
    Wait(400)

    local ped = PlayerPedId()

    local wx, wy, wz = FindOutsideSpawnPoint(50)
    local faceHeading = HeadingToCenter(wx, wy, TURF.centerPos.x, TURF.centerPos.y)

    -- Safe teleport with full MLO/collision protection
    SafeTeleportToSpawn(wx, wy, wz, faceHeading)

    ped = PlayerPedId()
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)

    if TURF.equippedHash then
        GiveWeaponToPed(ped, TURF.equippedHash, 9999, false, true)
        SetPedAmmo(ped, TURF.equippedHash, 9999)
        SetCurrentPedWeapon(ped, TURF.equippedHash, true)
    end

    TURF.godmode      = true
    TURF.inRadius     = false
    TURF.isDead       = false
    TURF.isRespawning = false

    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)

    DoScreenFadeIn(300)
    Wait(400)

    -- Snap heading and camera to face the turf center
    Wait(0)
    SetEntityHeading(ped, faceHeading)
    SetGameplayCamRelativeHeading(0.0)
    SetGameplayCamRelativePitch(0.0, 1.0)

    exports["pvp-core"]:SetPlayerTransitioning(false)
end

-- ============================================================
-- FALL-THROUGH SAFETY NET  (ALL MAPS — strict MLO-style)
-- ============================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300)
        if not TURF.active or not TURF.centerPos then goto continue end
        if TURF.isDead or TURF.isRespawning then goto continue end
        -- Another teleport (enter/leave/respawn) is already mid-flight --
        -- don't pile a second one on top of it.
        if exports["pvp-core"]:IsPlayerTransitioning() then goto continue end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then goto continue end

        local pos = GetEntityCoords(ped)
        local vel = GetEntityVelocity(ped)
        local expectedZ = TURF.centerPos.z
        local zDiff = expectedZ - pos.z

        -- All maps use strict MLO-style detection (Skate Park behavior)
        local falling = vel.z < -4.0
        local below = zDiff > 5.0

        if below and falling then
            exports["pvp-core"]:SetPlayerTransitioning(true)
            Citizen.Trace("[TURFWARS] Fall-through detected! Emergency teleport to safe spawn.\n")

            -- Find new safe spawn outside radius
            local sx, sy, sz, sHeading = FindOutsideSpawnPoint(50)

            -- Teleport safely
            SafeTeleportToSpawn(sx, sy, sz, sHeading)

            ped = PlayerPedId()
            SetEntityHealth(ped, 200)
            SetPedArmour(ped, 100)
            ClearPedBloodDamage(ped)
            ResetPedVisibleDamage(ped)
            ClearPedTasksImmediately(ped)

            if TURF.equippedHash then
                GiveWeaponToPed(ped, TURF.equippedHash, 9999, false, true)
                SetPedAmmo(ped, TURF.equippedHash, 9999)
                SetCurrentPedWeapon(ped, TURF.equippedHash, true)
            end

            -- Restore godmode (outside radius)
            TURF.godmode  = true
            TURF.inRadius = false
            SetPlayerInvincible(PlayerId(), true)
            SetEntityInvincible(ped, true)

            Notify("~r~You fell through the map! Teleported to safe spawn.", 255, 0, 0)
            exports["pvp-core"]:SetPlayerTransitioning(false)
        end

        ::continue::
    end
end)

-- ============================================================
-- ENTER / LEAVE TURF WARS
-- ============================================================
function EnterTurfWars()
    if TURF.active then
        Notify("Already in Turf Wars!", 255, 80, 80)
        return
    end
    if exports["pvp-core"]:IsPlayerTransitioning() then
        Notify("Still loading, give it a second and try again.", 255, 150, 0)
        return
    end
    TriggerServerEvent('turfwars:requestJoin')
end

function LeaveTurfWars(notifyServer)
    if not TURF.active then return end
    exports["pvp-core"]:SetPlayerTransitioning(true)
    notifyServer = notifyServer ~= false

    if notifyServer then
        TriggerServerEvent('turfwars:requestLeave')
    end

    if TURF.menuOpen then
        TURF.menuOpen = false
        SetNuiFocus(false, false)
    end
    if TURF.slomo then
        SetTimeScale(1.0)
        TURF.slomo = false
    end
    TURF.active       = false
    TURF.inRadius     = false
    TURF.godmode      = false
    TURF.isDead       = false
    TURF.isRespawning = false
    TURF.centerPos    = nil
    TURF.equippedHash = nil

    local ped = PlayerPedId()
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
    RemoveAllPedWeapons(ped, true)
    ClearFocus()

    HideTurfBadge()
    SendNUI({ type = "clearEquipped" })

    TriggerEvent("turfwars:left")
    exports["pvp-core"]:SetPlayerGameState("hub")
   Wait(4)
    exports["pvp-core"]:SetPlayerTransitioning(false)
end

-- ============================================================
-- LOAD MAP
-- ============================================================
function LoadMap(mapData, firstEntry)
    if not mapData then return end

    local mapIndex = mapData.index
    local map = TURF_MAPS[mapIndex]
    if not map then return end

    if TURF.slomo then
        SetTimeScale(1.0)
        TURF.slomo = false
    end

    local mapRadius = mapData.radius or map.radius or CONFIG.defaultRadius
    mapRadius = math.max(CONFIG.minRadius, math.min(CONFIG.maxRadius, mapRadius))

    TURF.currentMap   = mapIndex
    TURF.centerPos    = map.center
    TURF.mapHeading   = map.heading
    TURF.radius       = mapRadius
    TURF.mapStartTime = GetGameTimer()
    TURF.godmode      = true
    TURF.inRadius     = false
    TURF.isDead       = false

    DoScreenFadeOut(firstEntry and 600 or 400)
    Wait(firstEntry and 700 or 500)

    local ped = PlayerPedId()

    local spawnX, spawnY, spawnZ = FindOutsideSpawnPoint(50)
    local spawnHeading = HeadingToCenter(spawnX, spawnY, map.center.x, map.center.y)

    -- Safe teleport with full MLO/collision protection
    SafeTeleportToSpawn(spawnX, spawnY, spawnZ, spawnHeading)

    ped = PlayerPedId()
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)

    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)

    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
    ClearPlayerWantedLevel(PlayerId())

    ShowTurfBadge(map.name, CONFIG.mapDuration)

    DoScreenFadeIn(400)
    Wait(0)

    SetGameplayCamRelativeHeading(0.0)
    SetGameplayCamRelativePitch(0.0, 1.0)

    

    TriggerEvent("turfwars:mapLoaded", map.center, TURF.radius)
end

-- ============================================================
-- SERVER EVENT HANDLERS
-- ============================================================

RegisterNetEvent('turfwars:enterConfirmed')
AddEventHandler('turfwars:enterConfirmed', function(mapData)
    -- Mark transitioning BEFORE flipping TURF.active, so the fall-through
    -- net / respawn handler / hub watchdog all see "a teleport is in
    -- flight" instead of "we are already in turf" while the player is
    -- still physically standing wherever they pressed E from.
    exports["pvp-core"]:SetPlayerTransitioning(true)

    TURF.active       = true
    TURF.isDead       = false
    TURF.isRespawning = false
    -- No weapon is auto-issued on entry. The Badged Eagle is still
    -- unlocked for everyone by default (see pvp-shop's starter weapon
    -- logic), but players choose it -- or anything else they own --
    -- from the arsenal menu themselves rather than spawning armed.
    TURF.equippedHash = nil
    TURF.equippedName = "None"
    TURF.serverTimeRemaining = CONFIG.mapDuration

    LoadMap(mapData, true)

    TriggerEvent("turfwars:entered")
    exports["pvp-core"]:SetPlayerGameState("turfwars")

    exports["pvp-core"]:SetPlayerTransitioning(false)
end)

RegisterNetEvent('turfwars:leaveConfirmed')
AddEventHandler('turfwars:leaveConfirmed', function()
    LeaveTurfWars(false)
end)

RegisterNetEvent('turfwars:mapChanged')
AddEventHandler('turfwars:mapChanged', function(mapData)
    if not TURF.active then return end
    Notify(string.format("Rotating to next map: ~y~%s", mapData.name), 255, 180, 0)
end)

RegisterNetEvent('turfwars:loadMap')
AddEventHandler('turfwars:loadMap', function(mapData)
    if not TURF.active then return end
    LoadMap(mapData, false)
    TURF.serverTimeRemaining = CONFIG.mapDuration
end)

RegisterNetEvent('turfwars:timerSync')
AddEventHandler('turfwars:timerSync', function(remaining, mapName)
    if not TURF.active then return end
    TURF.serverTimeRemaining = remaining
    UpdateBadgeTimer(remaining, mapName)
end)

RegisterNetEvent('turfwars:slomoStart')
AddEventHandler('turfwars:slomoStart', function()
    if not TURF.active then return end
    TURF.slomo = true
    SetTimeScale(0.5)
    
end)

RegisterNetEvent('turfwars:radiusChanged')
AddEventHandler('turfwars:radiusChanged', function(newRadius)
    if not TURF.active then return end
    TURF.radius = newRadius
    Notify(string.format("Turf radius updated to ~y~%.0fm", newRadius), 100, 200, 255)
end)

RegisterNetEvent('turfwars:respawnApproved')
AddEventHandler('turfwars:respawnApproved', function(mapData)
    RespawnOutsideRadius(mapData)
end)

RegisterNetEvent('turfwars:notify')
AddEventHandler('turfwars:notify', function(msg)
    Notify(msg)
end)

-- ============================================================
-- PVP-CORE STATE LISTENER  (FIX: auto-leave when /hub is used)
-- ============================================================
AddEventHandler("pvp-core:stateChanged", function(newState)
    -- Leave turf on ANY state change away from turf itself (hub, redzone,
    -- or anything added later) -- not just "hub". Previously this only
    -- fired on "hub", so going Turf -> Redzone directly never told the
    -- server to clear TURF.players[src], leaving the economy gate
    -- (pvp-economy's IsPlayerInTurf check) stuck "true" for that player.
    if newState ~= "turfwars" and TURF.active then
        LeaveTurfWars(true)
    end
end)

-- ============================================================
-- HUB INTEGRATION  (external resources can trigger this)
-- ============================================================
AddEventHandler("turfwars:left", function()
    if TURF.active then
        LeaveTurfWars(true)
    end
end)

-- ============================================================
-- NPC SPAWN
-- ============================================================
function SpawnTurfNPC()
    local model = CONFIG.npcModel

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local sp  = CONFIG.npcStandPos
    local npc = CreatePed(4, model, sp.x, sp.y, sp.z - 0.8, sp.w, false, true)

    if DoesEntityExist(npc) then
        SetEntityHeading(npc, sp.w)
        FreezeEntityPosition(npc, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        SetPedCanRagdoll(npc, false)
        SetPedCanBeTargetted(npc, false)
        SetPedCanBeKnockedOffVehicle(npc, false)
        SetPedCanPlayAmbientAnims(npc, false)
        SetPedCanPlayAmbientBaseAnims(npc, false)
        TaskStartScenarioInPlace(npc, "WORLD_HUMAN_GUARD_STAND", 0, true)
        SetPedCombatAttributes(npc, 46, false)
        SetPedFleeAttributes(npc, 0, false)

        TURF.npcEntity   = npc
        TURF.npcInitDone = true
        print("[TURFWARS] NPC spawned at standing position")
    else
        print("[TURFWARS] ERROR: NPC failed to spawn")
    end

    SetModelAsNoLongerNeeded(model)
end

-- ============================================================
-- NPC INTERACTION THREAD
-- ============================================================
Citizen.CreateThread(function()
    while not TURF.npcEntity or not DoesEntityExist(TURF.npcEntity) do
        Citizen.Wait(500)
    end

    while true do
        Citizen.Wait(0)

        if not TURF.active then
            local ped       = PlayerPedId()
            local playerPos = GetEntityCoords(ped)
            local npcPos    = GetEntityCoords(TURF.npcEntity)
            local dist      = #(playerPos - npcPos)

            if dist <= CONFIG.promptDist then
                local alpha = 255
                if dist > CONFIG.promptDist * 0.6 then
                    alpha = math.floor(255 * (1.0 - (dist - CONFIG.promptDist * 0.6) / (CONFIG.promptDist * 0.4)))
                end

                Draw3DText(npcPos.x, npcPos.y, npcPos.z + 1.25, CONFIG.npcName, 0.55, alpha, 248, 250, 252)

                if dist <= CONFIG.interactDist then
                    Draw3DText(npcPos.x, npcPos.y, npcPos.z + 1.05, "[E]  Enter TurfWars", 0.45, alpha, 160, 60, 255)

                    if IsControlJustPressed(0, 38) then
                        EnterTurfWars()
                    end
                else
                    Draw3DText(npcPos.x, npcPos.y, npcPos.z + 0.95, "", 0.3, math.floor(alpha * 0.6))
                end
            end
        end
    end
end)

-- ============================================================
-- 3D TEXT HELPER
-- ============================================================
function Draw3DText(x, y, z, text, scale, alpha, r, g, b)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
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
    DrawText(_x, _y)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    print("[TURFWARS] Client loaded. Waiting for server sync...")
    Wait(2500)
    SpawnTurfNPC()
    print("[TURFWARS] NPC spawned. Approach and press E to enter.")
    print("[TURFWARS] Commands: /endturf  /turfradius <n>  /leaveturfwars")
    print("[TURFWARS] In-game: [F4] to open Arsenal weapon menu")
end)

-- ============================================================
-- CLEANUP
-- ============================================================
AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end

    if TURF.active then LeaveTurfWars(false) end

    if TURF.npcEntity and DoesEntityExist(TURF.npcEntity) then
        DeleteEntity(TURF.npcEntity)
        TURF.npcEntity = nil
    end

    SetNuiFocus(false, false)
    print("[TURFWARS] Client cleaned up.")
end)