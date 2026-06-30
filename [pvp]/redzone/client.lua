-- ============================================================
-- REDZONE PVP ARENA GAMEMODE
-- Modular combat gamemode for the PvP server.
--
-- FEATURES:
--   - Helipad godmode zone: safe on platform, vulnerable off it
--   - R key respawn: manual only — press R while dead to respawn
--   - On-screen prompt when dead
--   - Boundary enforcement
--   - Periodic loadout refresh to prevent disarm bugs
--
-- Arena: Maze Bank Arena interior
-- Center:  2800.0, -3803.0, 91.03
-- Spawn:   2800.0, -3803.0, 97.0 (helipad)
-- ============================================================

local REDZONE = {
    center       = vector3(2800.0, -3803.0, 91.03),
    spawnPos     = vector3(2800.0, -3803.0, 97.0),
    spawnHeading = 0.0,

    arenaLength  = 60.0,
    arenaWidth   = 60.0,
    arenaHeight  = 15.0,
    fenceSpacing = 4.5,

    boundaryRadius     = 55.0,
    boundaryWarnRadius = 48.0,
    boundaryDamage     = 25,

    helipadGodmode = {
        halfW   = 9.0,
        halfL   = 9.0,
        offsetX = -0.3,
        offsetY = 0.1,
        minZ    = 95.5,
        maxZ    = 105.0,
    },

    -- Props
    helipad      = `prop_helipad_02`,
    fence        = `prop_fnclink_04a`,
    barrierConc  = `prop_barrier_work05`,
    barrierConc2 = `prop_barrier_work06a`,
    cratePile1   = `prop_boxpile_07d`,
    cratePile2   = `prop_cratepile_07a`,
    cratePile3   = `prop_cratepile_02a`,
    container1   = `prop_container_01a`,
    container2   = `prop_container_03a`,
    container3   = `prop_container_01b`,
    carWreck1    = `prop_rub_carwreck_2`,
    carWreck2    = `prop_rub_carwreck_3`,
    carWreck3    = `prop_wrecked_buzzard`,
    dumpster1    = `prop_dumpster_01a`,
    dumpster2    = `prop_dumpster_02a`,
    dumpster3    = `prop_dumpster_03a`,
    dumpster4    = `prop_dumpster_04a`,
    tyrePile     = `prop_tyre_spike_01`,
    rubble1      = `prop_rub_pile_01`,
    rubble2      = `prop_rub_pile_03`,
    rubble3      = `prop_rub_pile_04`,
    tree1        = `prop_tree_cypress_01`,
    tree2        = `prop_tree_maple_02`,
    tree3        = `prop_tree_eng_oak_01`,
    tree4        = `prop_tree_jacada_02`,
    bush1        = `prop_bush_lrg_01c`,
    bush2        = `prop_bush_med_03`,
    bush3        = `prop_bush_small_01`,
    bush4        = `prop_bush_ornament_01`,
    hedge1       = `prop_hedge_02`,
    rock1        = `prop_rock_1_a`,
    rock2        = `prop_rock_1_b`,
    rock3        = `prop_rock_1_c`,

    -- Runtime state
    spawnedProps   = {},
    interiorID     = nil,
    interiorLoaded = false,
    inRedzone      = false,
    isDead         = false,
    onHelipad      = false,
    isRespawning   = false,
}

local HELIPAD_CLEAR_RADIUS = 10.0

-- ============================================================
-- HELPER: Check if position is on helipad platform
-- ============================================================
local function IsOnHelipadPlatform(pos)
    local h = REDZONE.helipadGodmode

    local minX = REDZONE.center.x + h.offsetX - h.halfW
    local maxX = REDZONE.center.x + h.offsetX + h.halfW
    local minY = REDZONE.center.y + h.offsetY - h.halfL
    local maxY = REDZONE.center.y + h.offsetY + h.halfL

    local inX = pos.x >= minX and pos.x <= maxX
    local inY = pos.y >= minY and pos.y <= maxY
    local inZ = pos.z >= 95.5

    return inX and inY and inZ
end

local function tooCloseToHelipad(x, y)
    return math.sqrt(x * x + y * y) < HELIPAD_CLEAR_RADIUS
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    Wait(2000)
    RequestModels()
    Wait(2000)

    LoadArenaInterior()
    Wait(500)

    SpawnHelipadMarker()
    SpawnHelipadCollisionBarrier()
    SpawnArenaFenceBox()
    SpawnCombatProps()
    SpawnDecorativeTrees()

    StartBoundaryEnforcement()
    StartInteriorKeepalive()
    StartArenaVisuals()
    StartDeathTracker()
    StartDeathHintThread()
    StartRespawnKeyHandler()
    StartHelipadGodmodeThread()
    StartLoadoutKeepalive()
end)

-- ============================================================
-- MODEL LOADING
-- ============================================================

function RequestModels()
    local models = {
        REDZONE.helipad, REDZONE.fence,
        REDZONE.barrierConc, REDZONE.barrierConc2,
        REDZONE.cratePile1, REDZONE.cratePile2, REDZONE.cratePile3,
        REDZONE.container1, REDZONE.container2, REDZONE.container3,
        REDZONE.carWreck1, REDZONE.carWreck2, REDZONE.carWreck3,
        REDZONE.dumpster1, REDZONE.dumpster2, REDZONE.dumpster3, REDZONE.dumpster4,
        REDZONE.tyrePile,
        REDZONE.rubble1, REDZONE.rubble2, REDZONE.rubble3,
        REDZONE.tree1, REDZONE.tree2, REDZONE.tree3, REDZONE.tree4,
        REDZONE.bush1, REDZONE.bush2, REDZONE.bush3, REDZONE.bush4,
        REDZONE.hedge1,
        REDZONE.rock1, REDZONE.rock2, REDZONE.rock3,
    }

    for _, model in ipairs(models) do
        if not HasModelLoaded(model) then RequestModel(model) end
    end

    local allLoaded = false
    local attempts  = 0
    while not allLoaded and attempts < 100 do
        allLoaded = true
        for _, model in ipairs(models) do
            if not HasModelLoaded(model) then allLoaded = false; break end
        end
        if not allLoaded then Wait(100); attempts = attempts + 1 end
    end
end

-- ============================================================
-- INTERIOR LOADING
-- ============================================================

function LoadArenaInterior()
    RequestIpl("xs_arena_interior")
    RequestIpl("xs_arena_interior_mod")
    RequestIpl("xs_arena_interior_mod_2")

    Wait(500)

    local interiorID = GetInteriorAtCoords(REDZONE.center.x, REDZONE.center.y, REDZONE.center.z)
    if interiorID ~= 0 then
        ActivateInteriorEntitySet(interiorID, "set_arena_floor")
        ActivateInteriorEntitySet(interiorID, "set_arena_tower")
        RefreshInterior(interiorID)
        PinInteriorInMemory(interiorID)
        REDZONE.interiorID     = interiorID
        REDZONE.interiorLoaded = true
    else
        REDZONE.interiorLoaded = false
    end
end

-- ============================================================
-- HELIPAD MARKER
-- ============================================================

function SpawnHelipadMarker()
    local obj = CreateObjectNoOffset(REDZONE.helipad, REDZONE.center.x, REDZONE.center.y, REDZONE.center.z + 2, false, false, false)
    if DoesEntityExist(obj) then
        SetEntityHeading(obj, 0.0)
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, true, true)
        SetEntityAsMissionEntity(obj, true, false)
        table.insert(REDZONE.spawnedProps, obj)
    end
end

-- ============================================================
-- INVISIBLE HELIPAD COLLISION BARRIER
-- ============================================================

function SpawnHelipadCollisionBarrier()
    local barrierModel     = `prop_barrier_work05`
    local barrierZ         = REDZONE.center.z + 1.0
    local stepSize         = 0.6
    local halfW, halfL     = 9.0, 9.0
    local offsetX, offsetY = -0.3, 0.1
    local count            = 0

    local x = -halfW
    while x <= halfW do
        local y = -halfL
        while y <= halfL do
            local worldX = REDZONE.center.x + offsetX + x
            local worldY = REDZONE.center.y + offsetY + y
            local obj = CreateObjectNoOffset(barrierModel, worldX, worldY, barrierZ, false, false, false)
            if DoesEntityExist(obj) then
                SetEntityHeading(obj, 0.0)
                FreezeEntityPosition(obj, true)
                SetEntityCollision(obj, true, true)
                SetEntityAsMissionEntity(obj, true, false)
                SetEntityVisible(obj, false, false)
                table.insert(REDZONE.spawnedProps, obj)
                count = count + 1
            end
            y = y + stepSize
        end
        x = x + stepSize
    end
end

-- ============================================================
-- ARENA FENCE BOX (3 levels)
-- ============================================================

function SpawnArenaFenceBox()
    local halfL   = REDZONE.arenaLength / 2
    local halfW   = REDZONE.arenaWidth / 2
    local fenceZ  = REDZONE.center.z
    local spacing = REDZONE.fenceSpacing

    local function placeFence(x, y, z, heading)
        RequestCollisionAtCoord(x, y, z)
        local obj = CreateObjectNoOffset(REDZONE.fence, x, y, z, false, false, false)
        if DoesEntityExist(obj) then
            SetEntityHeading(obj, heading)
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, true, true)
            SetEntityAsMissionEntity(obj, true, false)
            table.insert(REDZONE.spawnedProps, obj)
            return true
        end
        return false
    end

    local fenceCount = 0
    local levels     = { fenceZ, fenceZ + 3.8, fenceZ + 7.6 }

    for _, z in ipairs(levels) do
        local x = REDZONE.center.x - halfL
        while x <= REDZONE.center.x + halfL + 0.1 do
            if placeFence(x, REDZONE.center.y + halfW, z, 180.0) then fenceCount = fenceCount + 1 end
            x = x + spacing
        end
        x = REDZONE.center.x - halfL
        while x <= REDZONE.center.x + halfL + 0.1 do
            if placeFence(x, REDZONE.center.y - halfW, z, 0.0) then fenceCount = fenceCount + 1 end
            x = x + spacing
        end
        local y = REDZONE.center.y - halfW
        while y <= REDZONE.center.y + halfW + 0.1 do
            if placeFence(REDZONE.center.x + halfL, y, z, 270.0) then fenceCount = fenceCount + 1 end
            y = y + spacing
        end
        y = REDZONE.center.y - halfW
        while y <= REDZONE.center.y + halfW + 0.1 do
            if placeFence(REDZONE.center.x - halfL, y, z, 90.0) then fenceCount = fenceCount + 1 end
            y = y + spacing
        end
    end
end

-- ============================================================
-- COMBAT PROPS
-- ============================================================

function SpawnCombatProps()
    local cx, cy, cz = REDZONE.center.x, REDZONE.center.y, REDZONE.center.z

    local function placeProp(model, x, y, z, heading, hasCollision)
        if tooCloseToHelipad(x, y) then return false end
        RequestCollisionAtCoord(cx + x, cy + y, cz + z)
        local obj = CreateObjectNoOffset(model, cx + x, cy + y, cz + z, false, false, false)
        if DoesEntityExist(obj) then
            SetEntityHeading(obj, heading or 0.0)
            FreezeEntityPosition(obj, true)
            if hasCollision == false then
                SetEntityCollision(obj, false, false)
            else
                SetEntityCollision(obj, true, true)
            end
            SetEntityAsMissionEntity(obj, true, false)
            table.insert(REDZONE.spawnedProps, obj)
            return true
        end
        return false
    end

    local count = 0

    if placeProp(REDZONE.container1,  0.0,  22.0, 0.0, 90.0)  then count = count + 1 end
    if placeProp(REDZONE.container2,  0.0, -22.0, 0.0, 90.0)  then count = count + 1 end

    if placeProp(REDZONE.carWreck1,  18.0,   5.0, 0.0, 30.0)  then count = count + 1 end
    if placeProp(REDZONE.carWreck2, -20.0,  -8.0, 0.0, 120.0) then count = count + 1 end
    if placeProp(REDZONE.carWreck3,  12.0, -18.0, 0.0, 60.0)  then count = count + 1 end
    if placeProp(REDZONE.carWreck1, -14.0,  18.0, 0.0, 15.0)  then count = count + 1 end

    if placeProp(REDZONE.barrierConc,   14.0,  12.0, 0.0, 0.0)  then count = count + 1 end
    if placeProp(REDZONE.barrierConc,   14.0,  14.0, 0.0, 0.0)  then count = count + 1 end
    if placeProp(REDZONE.barrierConc2, -14.0,  -8.0, 0.0, 90.0) then count = count + 1 end
    if placeProp(REDZONE.barrierConc2, -16.0,  -8.0, 0.0, 90.0) then count = count + 1 end
    if placeProp(REDZONE.barrierConc,   20.0,  18.0, 0.0, 0.0)  then count = count + 1 end
    if placeProp(REDZONE.barrierConc,   20.0,  16.0, 0.0, 90.0) then count = count + 1 end
    if placeProp(REDZONE.barrierConc2, -22.0,   0.0, 0.0, 0.0)  then count = count + 1 end
    if placeProp(REDZONE.barrierConc2, -24.0,   0.0, 0.0, 0.0)  then count = count + 1 end

    if placeProp(REDZONE.cratePile1,  -14.0,   8.0, 0.0, 0.0)   then count = count + 1 end
    if placeProp(REDZONE.cratePile2,   16.0, -12.0, 0.0, 45.0)  then count = count + 1 end
    if placeProp(REDZONE.cratePile3,   20.0,  -5.0, 0.0, 20.0)  then count = count + 1 end
    if placeProp(REDZONE.cratePile1,  -18.0,  14.0, 0.0, 75.0)  then count = count + 1 end

    if placeProp(REDZONE.dumpster1,  -12.0, -18.0, 0.0, 0.0)    then count = count + 1 end
    if placeProp(REDZONE.dumpster2,   18.0,  15.0, 0.0, 90.0)   then count = count + 1 end
    if placeProp(REDZONE.dumpster3,  -25.0, -18.0, 0.0, 45.0)   then count = count + 1 end
    if placeProp(REDZONE.dumpster4,   25.0,  18.0, 0.0, 180.0)  then count = count + 1 end

    if placeProp(REDZONE.tyrePile,    16.0,  -6.0, 0.0, 0.0)    then count = count + 1 end
    if placeProp(REDZONE.tyrePile,   -14.0,  15.0, 0.0, 45.0)   then count = count + 1 end
    if placeProp(REDZONE.tyrePile,    22.0,  12.0, 0.0, 90.0)   then count = count + 1 end
    if placeProp(REDZONE.tyrePile,   -22.0, -12.0, 0.0, 30.0)   then count = count + 1 end
    if placeProp(REDZONE.rubble1,     14.0, -20.0, 0.0, 0.0)    then count = count + 1 end
    if placeProp(REDZONE.rubble2,    -16.0,   2.0, 0.0, 0.0)    then count = count + 1 end
    if placeProp(REDZONE.rubble3,     18.0, -10.0, 0.0, 0.0)    then count = count + 1 end
end

-- ============================================================
-- DECORATIVE TREES & FOLIAGE
-- ============================================================

function SpawnDecorativeTrees()
    local cx, cy, cz = REDZONE.center.x, REDZONE.center.y, REDZONE.center.z

    local function placeProp(model, x, y, z, heading, hasCollision)
        local obj = CreateObjectNoOffset(model, cx + x, cy + y, cz + z, false, false, false)
        if DoesEntityExist(obj) then
            SetEntityHeading(obj, heading or 0.0)
            FreezeEntityPosition(obj, true)
            if hasCollision == false then
                SetEntityCollision(obj, false, false)
            else
                SetEntityCollision(obj, true, true)
            end
            SetEntityAsMissionEntity(obj, true, false)
            table.insert(REDZONE.spawnedProps, obj)
        end
    end

    for i = 0, 23 do
        local angle = (i / 24) * math.pi * 2
        local x, y  = math.cos(angle) * 38.0, math.sin(angle) * 38.0
        local model = (i % 4 == 0) and REDZONE.tree1 or (i % 4 == 1) and REDZONE.tree2 or (i % 4 == 2) and REDZONE.tree3 or REDZONE.tree4
        placeProp(model, x, y, 0.0, math.deg(angle))
    end

    for i = 0, 15 do
        local angle = (i / 16) * math.pi * 2 + (math.pi / 16)
        local x, y  = math.cos(angle) * 48.0, math.sin(angle) * 48.0
        placeProp((i % 2 == 0) and REDZONE.tree1 or REDZONE.tree3, x, y, 0.0, math.deg(angle))
    end

    for i = 0, 19 do
        local angle = (i / 20) * math.pi * 2 + 0.2
        local x, y  = math.cos(angle) * 34.0, math.sin(angle) * 34.0
        local model = (i % 4 == 0) and REDZONE.bush1 or (i % 4 == 1) and REDZONE.bush2 or (i % 4 == 2) and REDZONE.bush3 or REDZONE.bush4
        placeProp(model, x, y, 0.0, math.random() * 360)
    end

    for x = -30, 30, 8.0 do
        placeProp(REDZONE.hedge1, x,  32.0, 0.0, 0.0)
        placeProp(REDZONE.hedge1, x, -32.0, 0.0, 0.0)
    end
    for y = -30, 30, 8.0 do
        placeProp(REDZONE.hedge1,  32.0, y, 0.0, 90.0)
        placeProp(REDZONE.hedge1, -32.0, y, 0.0, 90.0)
    end

    placeProp(REDZONE.rock1,  35.0,  10.0, 0.0, 15.0)
    placeProp(REDZONE.rock2,  40.0, -15.0, 0.0, 80.0)
    placeProp(REDZONE.rock3, -38.0,  20.0, 0.0, 200.0)
    placeProp(REDZONE.rock1, -42.0,  -5.0, 0.0, 45.0)
    placeProp(REDZONE.rock2,  38.0,  30.0, 0.0, 120.0)
    placeProp(REDZONE.rock3, -35.0, -30.0, 0.0, 60.0)
end

-- ============================================================
-- HELIPAD GODMODE THREAD
-- ============================================================

function StartHelipadGodmodeThread()
    Citizen.CreateThread(function()
        local prevOnPad = false

        while true do
            Citizen.Wait(0)

            if not REDZONE.inRedzone then
                prevOnPad = false
                goto continue
            end

            local ped   = PlayerPedId()
            local pos   = GetEntityCoords(ped)
            local onPad = IsOnHelipadPlatform(pos)

            REDZONE.onHelipad = onPad

            if onPad and not prevOnPad then
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
            elseif not onPad and prevOnPad then
                SetPlayerInvincible(PlayerId(), false)
                SetEntityInvincible(ped, false)
            end

            if onPad then
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
                DisablePlayerFiring(PlayerId(), true)
            end

            prevOnPad = onPad

            ::continue::
        end
    end)
end

-- ============================================================
-- ENTER / LEAVE REDZONE EVENTS
-- ============================================================

AddEventHandler("redzone:enter", function()
    -- CRITICAL: mark transitioning BEFORE flipping inRedzone. The
    -- boundary-enforcement thread below checks distance from
    -- REDZONE.center every 200ms purely off REDZONE.inRedzone -- with
    -- no idea a teleport is still pending, it sees "huge distance from
    -- center" the instant inRedzone flips true (since the player is
    -- still wherever they pressed E from) and yanks them to spawnPos
    -- itself, racing this function's own fade+teleport below. That's
    -- the "tries to teleport, glitches, stuck in hub but state says
    -- redzone/turfwars" bug.
    exports["pvp-core"]:SetPlayerTransitioning(true)

    REDZONE.inRedzone    = true
    REDZONE.isDead       = false
    REDZONE.onHelipad    = false
    REDZONE.isRespawning = false

    exports["pvp-core"]:SetPlayerGameState("redzone")

    DoScreenFadeOut(500)
    Wait(600)

    local ped = PlayerPedId()

    RequestCollisionAtCoord(REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z)
    NetworkResurrectLocalPlayer(REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, REDZONE.spawnHeading, true, true)
    Wait(100)

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, false, false, false)
    SetEntityHeading(ped, REDZONE.spawnHeading)
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)

    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)

    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)

    TriggerEvent("pvp-weapons:giveLoadout", "tdm")

    DoScreenFadeIn(500)

    exports["pvp-core"]:SetPlayerTransitioning(false)
end)

AddEventHandler("redzone:leave", function()
    REDZONE.inRedzone    = false
    REDZONE.isDead       = false
    REDZONE.onHelipad    = false
    REDZONE.isRespawning = false

    local ped = PlayerPedId()
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
end)

-- ============================================================
-- RESPAWN IN ARENA
-- ============================================================

function RespawnInArena()
    if not REDZONE.inRedzone  then return end
    if REDZONE.isRespawning   then return end
    if exports["pvp-core"]:IsPlayerTransitioning() then return end

    exports["pvp-core"]:SetPlayerTransitioning(true)
    REDZONE.isRespawning = true

    DoScreenFadeOut(300)
    Wait(400)

    local ped = PlayerPedId()

    NetworkResurrectLocalPlayer(REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, REDZONE.spawnHeading, true, true)
    Wait(100)

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, false, false, false)
    SetEntityHeading(ped, REDZONE.spawnHeading)
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)

    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)

    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)

    TriggerEvent("pvp-weapons:giveLoadout", "tdm")

    REDZONE.isDead       = false
    REDZONE.onHelipad    = false
    REDZONE.isRespawning = false

    DoScreenFadeIn(300)
    exports["pvp-core"]:SetPlayerTransitioning(false)
end

-- ============================================================
-- R KEY RESPAWN - ONLY WHEN DEAD
-- ============================================================

function StartRespawnKeyHandler()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            if REDZONE.inRedzone then
                if IsControlJustPressed(0, 45) then
                    if REDZONE.isDead and not REDZONE.isRespawning then
                        RespawnInArena()
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- DEATH TRACKER
-- ============================================================

function StartDeathTracker()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(500)

            if REDZONE.inRedzone then
                local ped    = PlayerPedId()
                local isDead = IsEntityDead(ped) or GetEntityHealth(ped) <= 0

                if isDead and not REDZONE.isDead then
                    REDZONE.isDead = true
                elseif not isDead and REDZONE.isDead and not REDZONE.isRespawning then
                    REDZONE.isDead = false
                end
            else
                REDZONE.isDead = false
            end
        end
    end)
end

-- ============================================================
-- DEATH HINT - On-screen "Press R to Respawn" while dead
-- ============================================================

function StartDeathHintThread()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            if REDZONE.inRedzone and REDZONE.isDead then
                SetTextFont(4)
                SetTextScale(0.5, 0.5)
                SetTextColour(255, 50, 50, 220)
                SetTextCentre(true)
                SetTextOutline()
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName("~r~Press ~w~[R] ~r~to Respawn")
                EndTextCommandDisplayText(0.5, 0.55)
            end
        end
    end)
end

-- ============================================================
-- BOUNDARY ENFORCEMENT
-- ============================================================

function StartBoundaryEnforcement()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(200)

            if not REDZONE.inRedzone then goto continue end
            if exports["pvp-core"]:IsPlayerTransitioning() then goto continue end

            local ped = PlayerPedId()
            if not DoesEntityExist(ped) then goto continue end

            local pos  = GetEntityCoords(ped)
            local dist = #(pos - REDZONE.center)

            if dist > REDZONE.boundaryWarnRadius and dist <= REDZONE.boundaryRadius then
                DrawBoundaryWarning(dist)
            end

            if dist > REDZONE.boundaryRadius then
                SetEntityCoords(ped, REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, false, false, false, false)
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
            end

            if pos.z < REDZONE.center.z - 15.0 then
                SetEntityCoords(ped, REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, false, false, false, false)
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
            end

            if pos.z > REDZONE.center.z + 50.0 then
                SetEntityCoords(ped, REDZONE.spawnPos.x, REDZONE.spawnPos.y, REDZONE.spawnPos.z, false, false, false, false)
                SetPlayerInvincible(PlayerId(), true)
                SetEntityInvincible(ped, true)
            end

            ::continue::
        end
    end)
end

function DrawBoundaryWarning(dist)
    local intensity = (dist - REDZONE.boundaryWarnRadius) / (REDZONE.boundaryRadius - REDZONE.boundaryWarnRadius)
    local alpha     = math.floor(intensity * 200)

    DrawRect(0.5, 0.02, 1.0, 0.06, 255, 0, 0, alpha)
    DrawRect(0.5, 0.98, 1.0, 0.06, 255, 0, 0, alpha)
    DrawRect(0.02, 0.5, 0.06, 1.0, 255, 0, 0, alpha)
    DrawRect(0.98, 0.5, 0.06, 1.0, 255, 0, 0, alpha)

    local pulse = math.abs(math.sin(GetGameTimer() * 0.005)) * 50
    DrawRect(0.5, 0.5, 1.0, 1.0, 255, 0, 0, math.floor(pulse * intensity))

    SetTextFont(4); SetTextScale(0.6, 0.6); SetTextColour(255, 0, 0, 200 + alpha)
    SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName("~r~RETURN TO THE REDZONE")
    EndTextCommandDisplayText(0.5, 0.42)

    SetTextFont(4); SetTextScale(0.35, 0.35); SetTextColour(255, 100, 100, 200)
    SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName("Leaving the combat zone will result in elimination")
    EndTextCommandDisplayText(0.5, 0.48)

    local ped   = PlayerPedId()
    local pos   = GetEntityCoords(ped)
    local angle = math.atan2(REDZONE.center.y - pos.y, REDZONE.center.x - pos.x)
    local arrowX = 0.5 + math.cos(angle) * 0.08
    local arrowY = 0.5 + math.sin(angle) * 0.14
    DrawSprite("mprankbadge", "globe_bg", arrowX, arrowY, 0.025, 0.025, math.deg(angle) + 90, 255, 255, 255, 200)
end

-- ============================================================
-- INTERIOR KEEPALIVE
-- ============================================================

function StartInteriorKeepalive()
    Citizen.CreateThread(function()
        while true do
            Wait(5000)
            if REDZONE.interiorLoaded and REDZONE.interiorID then
                local ped  = PlayerPedId()
                local pos  = GetEntityCoords(ped)
                local dist = #(pos - REDZONE.center)
                if dist < REDZONE.boundaryRadius then
                    PinInteriorInMemory(REDZONE.interiorID)
                end
            end
        end
    end)
end

-- ============================================================
-- ARENA VISUALS
-- ============================================================

function StartArenaVisuals()
    Citizen.CreateThread(function()
        Wait(2000)
        while true do
            Citizen.Wait(0)
            if not REDZONE.inRedzone then goto continue end

            local pulse = 2.0 + math.abs(math.sin(GetGameTimer() * 0.003)) * 3.0
            DrawLightWithRangeAndShadow(REDZONE.center.x, REDZONE.center.y, REDZONE.center.z + 2.0, 255, 0, 0, 15.0, pulse)

            local halfL   = REDZONE.arenaLength / 2
            local halfW   = REDZONE.arenaWidth / 2
            local corners = {
                { x = halfL,  y = halfW  },
                { x = -halfL, y = halfW  },
                { x = halfL,  y = -halfW },
                { x = -halfL, y = -halfW },
            }
            for _, c in ipairs(corners) do
                DrawLightWithRangeAndShadow(REDZONE.center.x + c.x, REDZONE.center.y + c.y, REDZONE.center.z + 10.0, 0, 100, 255, 20.0, 1.5)
            end

            local blink = (math.sin(GetGameTimer() * 0.002) > 0) and 1.0 or 0.0
            if blink > 0 then
                for i = 0, 3 do
                    local angle = (i / 4) * math.pi * 2
                    local x     = math.cos(angle) * (halfL + 2.0)
                    local y     = math.sin(angle) * (halfW + 2.0)
                    DrawLightWithRangeAndShadow(REDZONE.center.x + x, REDZONE.center.y + y, REDZONE.center.z + 12.0, 255, 0, 0, 8.0, 2.0)
                end
            end

            ::continue::
        end
    end)
end

-- ============================================================
-- LOADOUT KEEPALIVE
-- ============================================================

function StartLoadoutKeepalive()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(2000)

            if REDZONE.inRedzone and not REDZONE.isDead then
                TriggerEvent("pvp-weapons:giveLoadout", "tdm")
            end
        end
    end)
end

-- ============================================================
-- INFINITE AMMO IN REDZONE
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        if REDZONE.inRedzone then
            local ped    = PlayerPedId()
            local weapon = GetSelectedPedWeapon(ped)

            if weapon ~= `WEAPON_UNARMED` then
                local _, maxAmmo = GetMaxAmmo(ped, weapon)
                SetPedAmmo(ped, weapon, maxAmmo)
            end
        end
    end
end)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end

    for _, obj in ipairs(REDZONE.spawnedProps) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    REDZONE.spawnedProps = {}

    if REDZONE.interiorLoaded and REDZONE.interiorID then
        UnpinInterior(REDZONE.interiorID)
    end

    RemoveIpl("xs_arena_interior")
    RemoveIpl("xs_arena_interior_mod")
    RemoveIpl("xs_arena_interior_mod_2")
end)