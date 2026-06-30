-- ============================================================
-- PVP HUB SYSTEM
-- Hub spawn management, /hub command, NO weapons/combat in hub,
-- NPC "Redzone" entry point with E prompt.
--
-- Hub POS:  -2987.0027, -1426.3258, 635.5565, 169.6275
-- NPC POS:  -2987.0613, -1418.2328, 635.6580, 176.1682
-- ============================================================

local HUB = {
    spawnPos     = vector4(-2986.2432, -1448.7915, 741.2402, 265.6100), 
    npcPos       = vector4(-2975.6775, -1445.7535, 741.2396, 90.5821),
    npcModel     = `S_M_M_MovSpace_01`,
    npcName      = "Redzone",
    interactDist = 2.5,
    promptDist   = 15.0,
    npcEntity    = nil,
    inHub        = true,
}

-- ============================================================
-- SPAWN IN HUB
-- ============================================================

CreateThread(function()
    exports.spawnmanager:setAutoSpawn(false)
end)

-- Makes sure a real, existing ped is available before we touch it.
-- On a brand new player's very first spawn, this resource can start
-- before the client has finished creating the local ped at all -
-- that race is part of why first-time players fell through the floor.
local function WaitForValidPed()
    local ped = PlayerPedId()
    local timeout = GetGameTimer() + 10000
    while (ped == 0 or not DoesEntityExist(ped)) and GetGameTimer() < timeout do
        Wait(50)
        ped = PlayerPedId()
    end
    return ped
end

function SpawnInHub()
    local ped = WaitForValidPed()

    -- Mark the transition as in-flight BEFORE touching any state flags,
    -- so other resources' watchdog threads (turf's fall-net, redzone's
    -- boundary enforcement, etc.) know not to act on a stale ped
    -- position while we're still loading them in.
    exports["pvp-core"]:SetPlayerTransitioning(true)

    DoScreenFadeOut(500)
    Wait(600)

    exports["pvp-core"]:SetPlayerGameState("hub")
    HUB.inHub = true

    local x, y, z, heading = HUB.spawnPos.x, HUB.spawnPos.y, HUB.spawnPos.z, HUB.spawnPos.w

    -- Point the streaming engine at the hub before placing anyone there
    if SetFocusPosAndVel then
        SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    end
    RequestCollisionAtCoord(x, y, z)

    -- The hub is an MLO interior - make sure the interior is actually
    -- streamed in and ready, not just "requested"
    local interior = GetInteriorAtCoords(x, y, z)
    local isMLO = (interior ~= 0 and IsValidInterior(interior))
    if isMLO then
        PinInteriorInMemory(interior)
        RefreshInterior(interior)
        local intTimer = GetGameTimer()
        while not IsInteriorReady(interior) and (GetGameTimer() - intTimer) < 5000 do
            Wait(0)
        end
    end

    NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
    Wait(100)

    ped = PlayerPedId()

    -- Freeze + drop collision while the floor streams in, so the
    -- player physically cannot fall before the MLO geometry exists
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    SetEntityHeading(ped, heading)

    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(x, y, z)
        if isMLO then
            RefreshInterior(interior)
        end
        Wait(0)
    end

    -- Extra settle time so the MLO geometry fully resolves
    Wait(isMLO and 600 or 200)

    SetEntityCollision(ped, true, true)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false, true)
    SetEntityHeading(ped, heading)

    -- If we still somehow dropped during the load, snap back up and retry once
    local pos = GetEntityCoords(ped)
    if math.abs(pos.z - z) > 5.0 then
        SetEntityCoordsNoOffset(ped, x, y, z + 1.0, false, false, false, true)
        NetworkResurrectLocalPlayer(x, y, z + 1.0, heading, true, true, false)
        Wait(100)
        ped = PlayerPedId()
        SetEntityHeading(ped, heading)
    end

    FreezeEntityPosition(ped, false)
    if ClearFocus then
        ClearFocus()
    end

    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 0)

    -- Strip ALL weapons
    RemoveAllPedWeapons(ped, true)
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    -- FULL godmode in hub
    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)

    -- Block ALL combat ability
    BlockHubCombat(ped)

    -- Clean ped
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
    ClearPlayerWantedLevel(PlayerId())
    SetMaxWantedLevel(0)

    DoScreenFadeIn(500)

    exports["pvp-core"]:SetPlayerTransitioning(false)
end

-- ============================================================
-- HUB COMBAT BLOCKER
-- Aggressively prevents ALL combat actions in the hub.
-- ============================================================

function BlockHubCombat(ped)
    -- Ped config flags to prevent combat stances
    SetPedConfigFlag(ped, 48, true)      -- BLOCK_WEAPON_SWITCHING
    SetPedConfigFlag(ped, 122, true)     -- DISABLE_MELEE
    SetPedConfigFlag(ped, 330, true)     -- DISABLE_CLOSING

    -- Prevent getting into combat stance
    SetPedUsingActionMode(ped, false, -1, "DEFAULT_ACTION")
    SetPedCanPlayAmbientAnims(ped, false)
    SetPedCanPlayAmbientBaseAnims(ped, false)

    -- Force peaceful movement
    SetPedResetFlag(ped, 200, true)      -- Disable fist fighting pose
end

-- ============================================================
-- ANTI FALL-THROUGH WATCHDOG
-- Safety net: if the player is marked as "in hub" but ends up far
-- below the hub floor (e.g. a freak streaming hiccup), snap them
-- straight back to the hub spawn instead of letting them fall forever.
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)

        if HUB.inHub and not exports["pvp-core"]:IsPlayerTransitioning() then
            local ped = PlayerPedId()
            if ped ~= 0 and DoesEntityExist(ped) then
                local pos = GetEntityCoords(ped)
                if pos.z < (HUB.spawnPos.z - 15.0) then
                    SpawnInHub()
                end
            end
        end
    end
end)

-- ============================================================
-- SYNC HUB.inHub WITH PVP-CORE STATE
-- Keeps the local flag in sync so the combat blocker below
-- only runs when the player is actually in the hub.
-- ============================================================

AddEventHandler("pvp-core:stateChanged", function(newState)
    HUB.inHub = (newState == "hub")
end)

-- ============================================================
-- NO WEAPONS / NO COMBAT IN HUB LOOP
-- Runs every frame to block all combat inputs.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if HUB.inHub then
            local ped = PlayerPedId()

            -- Strip weapons EVERY frame
            RemoveAllPedWeapons(ped, true)
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

            -- Disable ALL attack inputs
            DisableControlAction(0, 24, true)    -- Attack (LMB)
            DisableControlAction(0, 25, true)    -- Aim (RMB)
            DisableControlAction(0, 37, true)    -- Weapon wheel (TAB)
            DisableControlAction(0, 44, true)    -- Cover (Q)
            DisableControlAction(0, 47, true)    -- Detonate
            DisableControlAction(0, 52, true)    -- Melee alternate
            DisableControlAction(0, 53, true)    -- Weapon special
            DisableControlAction(0, 54, true)    -- Throw grenade
            DisableControlAction(0, 55, true)    -- Dive
            DisableControlAction(0, 68, true)    -- Attack in vehicle
            DisableControlAction(0, 69, true)    -- Aim in vehicle
            DisableControlAction(0, 70, true)    -- Attack 2 in vehicle
            DisableControlAction(0, 91, true)    -- Stunt / attack
            DisableControlAction(0, 92, true)    -- Stunt 2
            DisableControlAction(0, 114, true)   -- Fly attack
            DisableControlAction(0, 140, true)   -- Melee attack light
            DisableControlAction(0, 141, true)   -- Melee attack heavy
            DisableControlAction(0, 142, true)   -- Melee attack alternate
            DisableControlAction(0, 143, true)   -- Melee block
            DisableControlAction(0, 257, true)   -- Attack 2
            DisableControlAction(0, 263, true)   -- Melee attack 1
            DisableControlAction(0, 264, true)   -- Melee attack 2
            DisableControlAction(0, 331, true)   -- Melee attack 3

            -- Disable aim/fist fighting stance triggers
            DisableControlAction(0, 1, true)     -- Look left/right (mouse)
            DisableControlAction(0, 2, true)     -- Look up/down (mouse)

            -- Prevent firing entirely
            DisablePlayerFiring(PlayerId(), true)

            -- Block combat animations
            BlockHubCombat(ped)

            -- Force peace every frame
            SetPedUsingActionMode(ped, false, -1, "DEFAULT_ACTION")

            -- If ped somehow enters combat stance, immediately clear it
            if IsPedInMeleeCombat(ped) or IsPedInCombat(ped) then
                ClearPedTasksImmediately(ped)
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            end

            -- Re-enable essential controls (movement, jump, sprint)
            EnableControlAction(0, 30, true)  -- Move LR
            EnableControlAction(0, 31, true)  -- Move FB
            EnableControlAction(0, 21, true)  -- Sprint
            EnableControlAction(0, 22, true)  -- Jump
            EnableControlAction(0, 0, true)   -- Look LR
            EnableControlAction(0, 1, true)   -- Look UD
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 38, true)  -- E key (interact with NPC)
        end
    end
end)

-- ============================================================
-- NPC SPAWN
-- ============================================================

function SpawnHubNPC()
    local model = HUB.npcModel

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end

    local npc = CreatePed(4, model, HUB.npcPos.x, HUB.npcPos.y, HUB.npcPos.z - 0.8, HUB.npcPos.w, false, true)

    if DoesEntityExist(npc) then
        FreezeEntityPosition(npc, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        SetPedCanRagdoll(npc, false)
        SetPedCanBeTargetted(npc, false)
        SetPedCanBeKnockedOffVehicle(npc, false)
        TaskStartScenarioInPlace(npc, "WORLD_HUMAN_GUARD_STAND", 0, true)
        SetPedCombatAttributes(npc, 46, false)
        SetPedFleeAttributes(npc, 0, false)

        HUB.npcEntity = npc
    end

    SetModelAsNoLongerNeeded(model)
end

-- ============================================================
-- NPC INTERACTION
-- ============================================================

Citizen.CreateThread(function()
    while not HUB.npcEntity or not DoesEntityExist(HUB.npcEntity) do
        Citizen.Wait(500)
    end

    while true do
        Citizen.Wait(0)

        if HUB.inHub and HUB.npcEntity and DoesEntityExist(HUB.npcEntity) then
            local ped = PlayerPedId()
            local playerPos = GetEntityCoords(ped)
            local npcPos = GetEntityCoords(HUB.npcEntity)
            local dist = #(playerPos - npcPos)

            if dist <= HUB.promptDist then
                local alpha = 255
                if dist > HUB.promptDist * 0.6 then
                    alpha = math.floor(255 * (1.0 - (dist - HUB.promptDist * 0.6) / (HUB.promptDist * 0.4)))
                end

                -- NPC Name: white, larger — matches Turf/Wars NPC style
                Draw3DText(npcPos.x, npcPos.y, npcPos.z + 1.25, HUB.npcName, 0.55, alpha, 248, 250, 252)

                if dist <= HUB.interactDist then
                    -- Prompt: purple accent — matches Turf/Wars NPC style
                    Draw3DText(npcPos.x, npcPos.y, npcPos.z + 1.05, "[E]  Enter Redzone", 0.45, alpha, 160, 60, 255)

                    if IsControlJustPressed(0, 38) then
                        EnterRedzone()
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- ENTER REDZONE
-- ============================================================

function EnterRedzone()
    if exports["pvp-core"]:IsPlayerTransitioning() then return end

    HUB.inHub = false
    TriggerEvent("redzone:enter")

    TriggerEvent("chat:addMessage", {
        color = {255, 50, 50},
        args = {"[REDZONE]", "Entering Redzone... Good luck, soldier."}
    })
end

-- ============================================================
-- /HUB COMMAND
-- ============================================================

RegisterCommand("hub", function()
    -- REMOVED: the "already in hub" block check so players can always re-teleport

    if exports["pvp-core"]:IsPlayerTransitioning() then
        TriggerEvent("chat:addMessage", {
            color = {255, 150, 0},
            args = {"[HUB]", "Still loading, give it a second and try again."}
        })
        return
    end

    local currentState = exports["pvp-core"]:GetPlayerGameState()
    if currentState ~= "hub" then
        TriggerEvent("redzone:leave")
        TriggerEvent("turfwars:left")   -- also exits Turf Wars if active
        TriggerEvent("wars:left")       -- also exits PvP Wars if active
    end

    SpawnInHub()

    TriggerEvent("chat:addMessage", {
        color = {0, 255, 100},
        args = {"[HUB]", "Returned to Hub."}
    })
end, false)

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

    -- Wait until the local ped genuinely exists before doing anything.
    -- A brand new player's very first ped can take longer to come into
    -- existence than a flat Wait(2000) - that gap is what caused new
    -- players specifically to fall through the hub floor.
    WaitForValidPed()

    SpawnHubNPC()
    Wait(500)
    SpawnInHub()
end)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end

    if HUB.npcEntity and DoesEntityExist(HUB.npcEntity) then
        DeleteEntity(HUB.npcEntity)
        HUB.npcEntity = nil
    end
end)