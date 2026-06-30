-- ============================================================
-- REDZONE / TURFWARS / WARS ENEMIES - SOLO TESTING NPCs
-- Spawns hostile NPCs for testing Redzone, TurfWars, and Wars.
-- REMOVE THIS RESOURCE when done testing with other players.
--
-- REDZONE MODE:  Spawns on helipad, pushes down to fight.
-- TURFWARS MODE: Spawns around the turf radius ring,
--                updates dynamically if radius/map changes.
-- WARS MODE:     Spawns around the player's own spawn point
--                (wars only ever gives a single spawn vector4,
--                not a center+radius zone like turf), active
--                during BOTH waiting (picked a map, no admin
--                session yet) and the official scored session --
--                NPC kills should pay out in either state.
-- ============================================================

local ENEMIES = {
    active       = false,
    mode         = "redzone",   -- "redzone" | "turfwars" | "wars"
    maxEnemies   = 5,
    respawnDelay = 3000,
    spawnCheckInterval = 500,

    -- ---- Redzone defaults ----
    rz_spawnPos    = vector3(2800.0, -3803.0, 97.0),
    rz_arenaCenter = vector3(2800.0, -3803.0, 91.03),

    -- ---- TurfWars (set dynamically) ----
    tw_center  = nil,   -- vector3 — updated by turfwars:mapLoaded
    tw_radius  = 40.0,

    -- ---- Wars (set dynamically) ----
    w_center   = nil,   -- vector3 — set from the wars spawnPos on enter
    w_radius   = 35.0,

    -- Enemy models
    models = {
        `s_m_y_blackops_01`,
        `s_m_y_blackops_02`,
        `s_m_y_blackops_03`,
        `s_m_y_marine_03`,
    },

    weapons = {
        `w_sb_minismg`,
        `WEAPON_KURONAMIVANDAL`,
    },

    peds = {},
}

-- ============================================================
-- TURF WARS EVENTS — update center/radius live
-- ============================================================

AddEventHandler("turfwars:entered", function()
    -- TurfWars started — enemies will activate via turfwars:mapLoaded
end)

AddEventHandler("turfwars:mapLoaded", function(center, radius)
    ENEMIES.tw_center = center
    ENEMIES.tw_radius = radius
    ENEMIES.mode      = "turfwars"

    if ENEMIES.active then
        -- Map changed mid-session — respawn enemies at new locations
        StopEnemies()
        Wait(500)
        StartEnemies()
    else
        Wait(1500)
        StartEnemies()
    end
end)

AddEventHandler("turfwars:radiusChanged", function(center, radius)
    ENEMIES.tw_center = center
    ENEMIES.tw_radius = radius
    -- Enemies will naturally migrate; no hard restart needed
end)

AddEventHandler("turfwars:left", function()
    StopEnemies()
    ENEMIES.mode = "redzone"
end)

-- ============================================================
-- WARS EVENTS — NEW. Wars previously had no NPC spawner hooked
-- up at all (this resource only ever reacted to turfwars:* and
-- redzone:* events), so NPC kills in Wars had nothing to kill and
-- could never pay out. Hooked into pvp-wars's own net events here
-- -- both the casual "waiting on a map" state AND the official
-- admin-started session start enemies, since money should flow
-- in either state (see pvp-wars's matching server/client fixes).
-- ============================================================

RegisterNetEvent("pvp-wars:enterMapWaiting")
AddEventHandler("pvp-wars:enterMapWaiting", function(data)
    local sp = data and data.spawnPos
    if not sp then return end
    ENEMIES.w_center = vector3(sp.x, sp.y, sp.z)
    ENEMIES.mode     = "wars"

    if ENEMIES.active then
        StopEnemies()
        Wait(500)
        StartEnemies()
    else
        Wait(1500)
        StartEnemies()
    end
end)

RegisterNetEvent("pvp-wars:sessionStart")
AddEventHandler("pvp-wars:sessionStart", function(sessionData)
    local sp = sessionData and sessionData.spawnPos
    if not sp then return end
    ENEMIES.w_center = vector3(sp.x, sp.y, sp.z)
    ENEMIES.mode     = "wars"

    if ENEMIES.active then
        -- Official session started right after waiting -- respawn
        -- around the (possibly different) team spawn point.
        StopEnemies()
        Wait(500)
        StartEnemies()
    else
        Wait(1500)
        StartEnemies()
    end
end)

RegisterNetEvent("pvp-wars:leaveWaitingConfirmed")
AddEventHandler("pvp-wars:leaveWaitingConfirmed", function()
    if ENEMIES.mode == "wars" then
        StopEnemies()
        ENEMIES.mode = "redzone"
    end
end)

RegisterNetEvent("pvp-wars:sessionEnd")
AddEventHandler("pvp-wars:sessionEnd", function()
    if ENEMIES.mode == "wars" then
        StopEnemies()
        ENEMIES.mode = "redzone"
    end
end)

RegisterNetEvent("pvp-wars:leaveConfirmed")
AddEventHandler("pvp-wars:leaveConfirmed", function()
    if ENEMIES.mode == "wars" then
        StopEnemies()
        ENEMIES.mode = "redzone"
    end
end)

-- ============================================================
-- REDZONE EVENTS
-- ============================================================

RegisterNetEvent("redzone:enter")
AddEventHandler("redzone:enter", function()
    ENEMIES.mode = "redzone"
    Wait(1500)
    StartEnemies()
end)

RegisterNetEvent("redzone:leave")
AddEventHandler("redzone:leave", function()
    if ENEMIES.mode == "redzone" then
        StopEnemies()
    end
end)

-- ============================================================
-- START ENEMIES
-- ============================================================

function StartEnemies()
    if ENEMIES.active then return end
    ENEMIES.active = true

    print("[ENEMIES] Starting enemy spawns (mode: " .. ENEMIES.mode .. ")")

    for _, model in ipairs(ENEMIES.models) do
        RequestModel(model)
    end
    Wait(500)

    for i = 1, ENEMIES.maxEnemies do
        SpawnEnemy(i)
        Wait(200)
    end

    StartDeathMonitorThread()
    StartCombatAssignmentThread()

    TriggerEvent("chat:addMessage", {
        color = {255, 80, 80},
        args  = {"[ENEMIES]", ENEMIES.maxEnemies .. " hostiles inbound!"}
    })
end

-- ============================================================
-- STOP ENEMIES
-- ============================================================

function StopEnemies()
    if not ENEMIES.active then return end
    ENEMIES.active = false

    for _, enemy in ipairs(ENEMIES.peds) do
        if enemy.blip and DoesBlipExist(enemy.blip) then RemoveBlip(enemy.blip) end
        if enemy.entity and DoesEntityExist(enemy.entity) then DeleteEntity(enemy.entity) end
    end
    ENEMIES.peds = {}
end

-- ============================================================
-- GET SPAWN POSITION
-- Redzone: on helipad
-- TurfWars: random point around the radius ring edge
--           (just INSIDE the sphere so they immediately engage)
-- Wars: same ring pattern as TurfWars, centered on the player's
--       own wars spawn point instead of a turf zone center.
-- ============================================================

function GetEnemySpawnPos(slotIndex)
    if ENEMIES.mode == "turfwars" and ENEMIES.tw_center then
        local c  = ENEMIES.tw_center
        local r  = ENEMIES.tw_radius * 0.80   -- 80% of radius, so inside the globe
        local angleDeg = ((slotIndex - 1) / ENEMIES.maxEnemies) * 360.0 + math.random(-20, 20)
        local rad      = math.rad(angleDeg)
        local wx = c.x + math.cos(rad) * r
        local wy = c.y + math.sin(rad) * r
        local wz = c.z

        -- Try to find ground
        local found, gz = GetGroundZFor_3dCoord(wx, wy, wz + 50.0, false)
        if found then wz = gz + 0.5 end

        return wx, wy, wz
    elseif ENEMIES.mode == "wars" and ENEMIES.w_center then
        local c  = ENEMIES.w_center
        local r  = ENEMIES.w_radius * 0.80
        local angleDeg = ((slotIndex - 1) / ENEMIES.maxEnemies) * 360.0 + math.random(-20, 20)
        local rad      = math.rad(angleDeg)
        local wx = c.x + math.cos(rad) * r
        local wy = c.y + math.sin(rad) * r
        local wz = c.z

        local found, gz = GetGroundZFor_3dCoord(wx, wy, wz + 50.0, false)
        if found then wz = gz + 0.5 end

        return wx, wy, wz
    else
        -- Redzone: helipad with small random offset
        local offsetX = (math.random() - 0.5) * 6.0
        local offsetY = (math.random() - 0.5) * 6.0
        return ENEMIES.rz_spawnPos.x + offsetX,
               ENEMIES.rz_spawnPos.y + offsetY,
               ENEMIES.rz_spawnPos.z
    end
end

-- ============================================================
-- SPAWN SINGLE ENEMY
-- ============================================================

function SpawnEnemy(slotIndex)
    if not ENEMIES.active then return end

    local model  = ENEMIES.models[(slotIndex % #ENEMIES.models) + 1]
    local weapon = ENEMIES.weapons[(slotIndex % #ENEMIES.weapons) + 1]

    if not HasModelLoaded(model) then
        RequestModel(model)
        Wait(100)
    end

    local spawnX, spawnY, spawnZ = GetEnemySpawnPos(slotIndex)

    local ped = CreatePed(4, model, spawnX, spawnY, spawnZ, math.random() * 360.0, true, true)

    if not DoesEntityExist(ped) then
        print("[ENEMIES] Failed to spawn enemy " .. slotIndex)
        return
    end

    SetEntityMaxHealth(ped, 200)
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)

    GiveWeaponToPed(ped, weapon, 999, false, true)
    Citizen.Wait(100)
    SetCurrentPedWeapon(ped, weapon, true)
    Citizen.Wait(100)

    SetPedCombatAttributes(ped, 0,  true)
    SetPedCombatAttributes(ped, 1,  true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 13, true)
    SetPedCombatAttributes(ped, 21, true)
    SetPedCombatAttributes(ped, 27, true)
    SetPedCombatAttributes(ped, 42, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 52, true)

    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatAbility(ped, 100)
    SetPedFiringPattern(ped, `FiringPatternFullAuto`)
    SetPedAccuracy(ped, 75)

    SetPedFleeAttributes(ped, 0, false)
    SetPedFleeAttributes(ped, 1, false)
    SetPedFleeAttributes(ped, 2, false)
    SetPedFleeAttributes(ped, 4, false)
    SetPedFleeAttributes(ped, 8, false)

    SetPedConfigFlag(ped, 281, true)
    SetPedConfigFlag(ped, 33,  false)
    SetPedAsEnemy(ped, true)
    SetPedRelationshipGroupHash(ped, `HATES_PLAYER`)

    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    SetPedCanBeTargetted(ped, true)
    FreezeEntityPosition(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)

    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, 432)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Enemy")
    EndTextCommandSetBlipName(blip)

    ENEMIES.peds[slotIndex] = {
        entity = ped,
        blip   = blip,
        dead   = false,
        slot   = slotIndex,
        weapon = weapon,
    }

    local playerPed = PlayerPedId()
    TaskCombatPed(ped, playerPed, 0, 16)

    Citizen.CreateThread(function()
        Citizen.Wait(200)
        if DoesEntityExist(ped) and ENEMIES.peds[slotIndex] and not ENEMIES.peds[slotIndex].dead then
            SetCurrentPedWeapon(ped, weapon, true)
        end
    end)

    print("[ENEMIES] Spawned enemy " .. slotIndex .. " (mode: " .. ENEMIES.mode .. ")")
end

-- ============================================================
-- DEATH MONITOR
-- ============================================================

function StartDeathMonitorThread()
    Citizen.CreateThread(function()
        while ENEMIES.active do
            Citizen.Wait(ENEMIES.spawnCheckInterval)
            if not ENEMIES.active then break end

            for i, enemy in ipairs(ENEMIES.peds) do
                if enemy.entity and DoesEntityExist(enemy.entity) then
                    local isDead = IsEntityDead(enemy.entity) or GetEntityHealth(enemy.entity) <= 0

                    if isDead and not enemy.dead then
                        enemy.dead = true
                        print("[ENEMIES] Enemy " .. i .. " died. Respawning in " .. (ENEMIES.respawnDelay/1000) .. "s...")

                        if enemy.blip and DoesBlipExist(enemy.blip) then
                            RemoveBlip(enemy.blip)
                            enemy.blip = nil
                        end

                        Citizen.Wait(ENEMIES.respawnDelay)
                        if not ENEMIES.active then break end

                        if enemy.entity and DoesEntityExist(enemy.entity) then
                            DeleteEntity(enemy.entity)
                        end
                        enemy.entity = nil
                        enemy.dead   = false

                        SpawnEnemy(i)

                    elseif not isDead then
                        enemy.dead = false
                    end
                elseif not enemy.dead then
                    enemy.dead = false
                    SpawnEnemy(i)
                end
            end
        end
    end)
end

-- ============================================================
-- COMBAT ASSIGNMENT
-- ============================================================

function StartCombatAssignmentThread()
    Citizen.CreateThread(function()
        while ENEMIES.active do
            Citizen.Wait(2000)
            if not ENEMIES.active then break end

            local playerPed = PlayerPedId()
            local playerPos = GetEntityCoords(playerPed)

            for i, enemy in ipairs(ENEMIES.peds) do
                if enemy.entity and DoesEntityExist(enemy.entity) and not enemy.dead then
                    local ped    = enemy.entity
                    local pedPos = GetEntityCoords(ped)

                    if ENEMIES.mode == "redzone" then
                        -- Legacy redzone: push off helipad
                        local dist2D = #(vector2(pedPos.x, pedPos.y) - vector2(ENEMIES.rz_spawnPos.x, ENEMIES.rz_spawnPos.y))
                        local playerBelow = playerPos.z < ENEMIES.rz_spawnPos.z - 2.0

                        if dist2D < 8.0 and playerBelow then
                            local pushX = ENEMIES.rz_spawnPos.x + (math.random()-0.5)*20.0
                            local pushY = ENEMIES.rz_spawnPos.y + (math.random()-0.5)*20.0
                            TaskGoToCoordAnyMeans(ped, pushX, pushY, ENEMIES.rz_arenaCenter.z + 0.5, 2.0, 0, false, 786603, 0.0)
                        else
                            if GetScriptTaskStatus(ped, 0x2E85A751) == 7 then
                                TaskCombatPed(ped, playerPed, 0, 16)
                                Citizen.Wait(200)
                                if DoesEntityExist(ped) and not enemy.dead then
                                    SetCurrentPedWeapon(ped, enemy.weapon, true)
                                end
                            end
                        end

                    else
                        -- TurfWars mode: just keep them targeting the player
                        if GetScriptTaskStatus(ped, 0x2E85A751) == 7 then
                            TaskCombatPed(ped, playerPed, 0, 16)
                            Citizen.Wait(200)
                            if DoesEntityExist(ped) and not enemy.dead then
                                SetCurrentPedWeapon(ped, enemy.weapon, true)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- INIT / CLEANUP
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end
    print("[ENEMIES] Enemy NPC spawner loaded.")
    print("[ENEMIES] Reacts to both Redzone AND TurfWars.")
    print("[ENEMIES] REMEMBER: Remove this resource when done testing solo!")
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    StopEnemies()
end)
