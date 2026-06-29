-- ============================================================
-- PVP WARS  —  CLIENT
-- Team Deathmatch with admin-managed teams, team UI overhead,
-- syringe heal item, loadout system, Wars inventory cash.
-- NPC Entry: "Wars" NPC in Hub → simple map-pick NUI
--
-- ------------------------------------------------------------
-- CHANGED THIS PASS
-- ------------------------------------------------------------
-- 1. NPC moved to the correct hub row position.
-- 2. E on the NPC now opens a SMALL map-pick panel only (map cards
--    + a one-line explainer) instead of the old full shop/admin
--    panel. Picking a map teleports you there right away — you're
--    armed with just the starter sidearm and free to roam/scrap
--    with whoever else is there while waiting for an admin to
--    actually build teams and start the scored match. All other
--    drawing (HUD badge, kill feed, team labels, prompts) stays
--    in-game/3D-text like the rest of the pack, not NUI panels.
-- 3. Loadout Shop is now its own panel, opened with [F4] (same key
--    pvp-turf already uses for its arsenal) while in Wars or just
--    waiting on a map.
-- 4. NEW full hotkey inventory, opened with [TAB] — same key most
--    RP inventories use — instead of the old "one row in a tab"
--    version buried inside the shop panel.
-- ============================================================

-- ============================================================
-- STATE
-- ============================================================

local WarsState = {
    active       = false,
    team         = nil,     -- "alpha" | "bravo"
    mapName      = nil,
    teammates    = {},
    syringeCount = 0,
    money        = 0,
    loadout      = nil,
    ownedWeapons = {},
    teamColor    = { alpha = {30, 120, 255}, bravo = {255, 60, 60} },
}

local IsInWars      = false   -- official, scored session (teams assigned, admin started it)
local IsWaitingWars  = false  -- picked a map ourselves, just hanging around, not scored yet
local NpcEntity     = nil
local IsAnimPlaying = false

-- Team overhead markers: { [netId] = { team = "alpha"|"bravo", name = "..." } }
local TeamMarkers  = {}

-- Syringe use debounce
local SyringeCooldown = false

-- Cached map list from the server, used by the map-picker NUI
local MapList = {}

-- Cached weapon name list from the server's shopData (mirrors
-- pvp-wars/server.lua's LOADOUT_WEAPONS). Used to resolve the
-- player's real currently-held weapon hash back to a name string,
-- so the shop UI's "EQUIPPED" badge can reflect actual game state
-- instead of trusting a possibly-stale server-recorded loadout.
local LOADOUT_WEAPON_NAMES = {}

-- ============================================================
-- CONFIG (must match server)
-- ============================================================

local NPC_POS       = vector4(-2975.6699, -1454.7476, 741.4398, 96.3372)
local NPC_MODEL     = `S_M_M_MovSpace_01`
local INTERACT_DIST = 2.5
local PROMPT_DIST   = 15.0

-- ============================================================
-- UTILITY
-- ============================================================

local function Notify(msg, color)
    color = color or {255, 200, 50}
    TriggerEvent('chat:addMessage', { color = color, args = {"[WARS]", msg} })
end

local function Draw3DTextWars(x, y, z, text, scale, alpha, r, g, b)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end
    SetTextScale(scale or 0.45, scale or 0.45)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(r or 255, g or 255, b or 255, alpha or 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(1)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function GetTeamColor(team)
    if team == "alpha" then return 30, 120, 255
    elseif team == "bravo" then return 255, 60, 60
    else return 186, 130, 255 end   -- neutral/waiting = the server's purple accent
end

-- ============================================================
-- HIDE DEFAULT GTA HUD WHILE IN WARS
-- pvp-hud's own version of this only runs for "redzone"/"turfwars"
-- (it correctly does NOT run for "wars" — that was the actual fix
-- for the Redzone overlay bleeding into Wars). Wars needs the same
-- clean-HUD treatment, just driven from here instead.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if IsInWars or IsWaitingWars then
            HideHudComponentThisFrame(2)   -- HUD_WEAPON_ICON
            HideHudComponentThisFrame(20)  -- HUD_WEAPON_STATS
            HideHudComponentThisFrame(6)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(8)
            HideHudComponentThisFrame(9)
        end
    end
end)

-- ============================================================
-- NPC SPAWN  (spawns alongside the turf/hub NPCs, same row)
-- ============================================================

local function SpawnWarsNPC()
    RequestModel(NPC_MODEL)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(NPC_MODEL) and GetGameTimer() < timeout do
        Citizen.Wait(50)
    end

    NpcEntity = CreatePed(4, NPC_MODEL, NPC_POS.x, NPC_POS.y, NPC_POS.z - 0.8, NPC_POS.w, false, true)

    if DoesEntityExist(NpcEntity) then
        FreezeEntityPosition(NpcEntity, true)
        SetEntityInvincible(NpcEntity, true)
        SetBlockingOfNonTemporaryEvents(NpcEntity, true)
        SetPedCanRagdoll(NpcEntity, false)
        SetPedCanBeTargetted(NpcEntity, false)
        TaskStartScenarioInPlace(NpcEntity, "WORLD_HUMAN_GUARD_STAND", 0, true)
        SetPedCombatAttributes(NpcEntity, 46, false)
        SetPedFleeAttributes(NpcEntity, 0, false)
    end

    SetModelAsNoLongerNeeded(NPC_MODEL)
end

-- ============================================================
-- NPC INTERACTION LOOP
-- Only show prompt when in hub state, and not already in/waiting on Wars
-- ============================================================

Citizen.CreateThread(function()
    -- Wait for NPC to exist
    while not NpcEntity or not DoesEntityExist(NpcEntity) do
        Citizen.Wait(500)
    end

    while true do
        Citizen.Wait(0)

        local hubState = "hub"
        local ok = pcall(function()
            hubState = exports["pvp-core"]:GetPlayerGameState()
        end)

        -- Only show when in hub and not already in/waiting on wars
        if hubState == "hub" and not IsInWars and not IsWaitingWars then
            local ped      = PlayerPedId()
            local playerPos = GetEntityCoords(ped)
            local npcCoords = GetEntityCoords(NpcEntity)
            local dist     = #(playerPos - npcCoords)

            if dist <= PROMPT_DIST then
                local alpha = 255
                if dist > PROMPT_DIST * 0.6 then
                    alpha = math.floor(255 * (1.0 - (dist - PROMPT_DIST * 0.6) / (PROMPT_DIST * 0.4)))
                end
                Draw3DTextWars(npcCoords.x, npcCoords.y, npcCoords.z + 1.3, "Wars", 0.55, alpha, 186, 130, 255)

                if dist <= INTERACT_DIST then
                    Draw3DTextWars(npcCoords.x, npcCoords.y, npcCoords.z + 1.05, "[E]  Choose a Map", 0.45, alpha, 200, 170, 255)

                    if IsControlJustPressed(0, 38) then
                        OpenMapPicker()
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- MAP PICKER  —  the ONLY thing the NPC opens. Small panel:
-- a one-line explainer + map cards. Picking one teleports you
-- there and pings the admins. Everything else (shop, inventory,
-- admin panel, HUD) lives behind its own hotkey/trigger instead
-- of being crammed into this menu.
-- ============================================================

function OpenMapPicker()
    TriggerServerEvent('pvp-wars:requestMapList')
    SendNUIMessage({ type = "openMapPicker" })
    SetNuiFocus(true, true)
end

RegisterNetEvent('pvp-wars:mapList')
AddEventHandler('pvp-wars:mapList', function(maps)
    MapList = maps or {}
    SendNUIMessage({ type = "mapList", maps = MapList })
end)

RegisterNUICallback('mapPickerDeploy', function(data, cb)
    TriggerServerEvent('pvp-wars:requestJoinMap', data.mapIndex)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMapPicker" })
    cb('ok')
end)

RegisterNUICallback('mapPickerRequestAdmin', function(data, cb)
    TriggerServerEvent('pvp-wars:adminRequest')
    cb('ok')
end)

RegisterNUICallback('mapPickerClose', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMapPicker" })
    cb('ok')
end)

-- ============================================================
-- ENTER MAP WAITING  —  server approved our map pick.
-- Teleport, arm with just the starter sidearm, show the slim
-- "waiting" HUD (no team pill yet — there's no team yet).
-- ============================================================

RegisterNetEvent('pvp-wars:enterMapWaiting')
AddEventHandler('pvp-wars:enterMapWaiting', function(data)
    IsWaitingWars       = true
    WarsState.mapName   = data.mapName
    WarsState.team      = nil
    WarsState.syringeCount = data.syringe or 0
    WarsState.money     = data.money or 0
    WarsState.loadout   = nil
    WarsState.ownedWeapons = {}

    pcall(function() exports["pvp-core"]:SetPlayerGameState("wars") end)

    TeleportToWars(data.spawnPos, nil)

    Citizen.SetTimeout(2000, function()
        ArmPlayer(nil)   -- starter sidearm only — this is casual, not the real loadout
    end)

    -- Force-close every overlay panel before showing the waiting HUD.
    -- The map picker's "open" message and this "enterWaiting" message
    -- both come from the server round trip; if the picker's close
    -- message ever races or drops, its full-screen dark/blur overlay
    -- (.overlay) is left covering the screen on arrival. Closing
    -- everything here, unconditionally, removes that possibility.
    SendNUIMessage({ type = "closeMapPicker" })
    SendNUIMessage({ type = "closeShop" })
    SendNUIMessage({ type = "closeInventory" })
    SetNuiFocus(false, false)

    SendNUIMessage({ type = "enterWaiting", mapName = data.mapName, money = WarsState.money, syringe = WarsState.syringeCount })
end)

RegisterNetEvent('pvp-wars:leaveWaitingConfirmed')
AddEventHandler('pvp-wars:leaveWaitingConfirmed', function()
    IsWaitingWars = false
    WarsState.mapName = nil
    SendNUIMessage({ type = "leaveWaiting" })
    ExecuteCommand("hub")
end)

-- ============================================================
-- LOADOUT SHOP  —  [F6].
-- REAL FIX (confirmed): pvp-turf's client.lua registers its OWN F4
-- command (RegisterCommand("turfmenu", ...)) and it is ALWAYS running,
-- in every mode, because pvp-turf is a separate resource that doesn't
-- stop just because you're not currently playing turf. So every F4
-- press while you're in Wars fires BOTH turfmenu (which checks
-- `if not TURF.active then return end` and bails) AND warsshop. The
-- toggleShop rebuild fixed the Lua-vs-DOM desync, but it didn't fix
-- the actual interference: two resources both calling SetNuiFocus off
-- the same physical keypress in the same input frame is exactly the
-- kind of race FXServer doesn't guarantee an order for, and it lines
-- up with the reported symptom (open works, close specifically
-- doesn't, only Escape/mouse-click -- which run entirely inside the
-- NUI's own input handling and never touch RegisterCommand/
-- SetNuiFocus from the Lua side at all -- still work). Moving Wars
-- off F4 entirely removes the shared key, which removes the race.
-- ============================================================

RegisterKeyMapping('warsshop', 'PvP Wars: Loadout Shop', 'keyboard', 'F6')

-- FIX: the "EQUIPPED" badge in the shop UI was driven entirely by
-- the SERVER's record of your last selected loadout (SESSION.loadouts
-- on the wars server, persisted there and handed back on every join/
-- rejoin). That record can go stale relative to what's actually in
-- your hands -- e.g. equip a gun, go to /hub (which doesn't clear
-- SESSION.loadouts[src], it's only wiped when the whole session
-- resets), come back, and the UI shows "EQUIPPED" on a gun you don't
-- currently have because the server just resent the old value before
-- ArmPlayer ever ran again. Resolving the REAL in-hand weapon here
-- and sending it to the NUI as its own value fixes that at the root --
-- the badge no longer has to trust anyone's memory of what you picked,
-- it reflects what GetSelectedPedWeapon says you're holding right now.
local function GetRealEquippedWeaponName()
    local ped = PlayerPedId()
    local hasWeapon, currentHash = GetCurrentPedWeapon(ped, true)
    if not hasWeapon then return nil end
    for _, name in ipairs(LOADOUT_WEAPON_NAMES) do
        if GetHashKey(name) == currentHash then
            return name
        end
    end
    return nil -- holding the starter sidearm, fists, or something not in the loadout list
end

RegisterCommand('warsshop', function()
    if not IsInWars and not IsWaitingWars then return end

    TriggerServerEvent('pvp-wars:requestShopData')
    SendNUIMessage({ type = "realEquippedWeapon", weapon = GetRealEquippedWeaponName() })
    SendNUIMessage({ type = "toggleShop" })
end, false)

RegisterNUICallback('warsShopOpened', function(data, cb)
    SetNuiFocus(true, true)
    cb('ok')
end)

RegisterNUICallback('warsPurchaseWeapon', function(data, cb)
    TriggerServerEvent('pvp-wars:purchaseWeapon', data.weapon)
    cb('ok')
end)

RegisterNUICallback('warsSetLoadout', function(data, cb)
    TriggerServerEvent('pvp-wars:setLoadout', data.weapon)
    cb('ok')
end)

RegisterNUICallback('warsBuySyringe', function(data, cb)
    TriggerServerEvent('pvp-wars:buySyringe')
    cb('ok')
end)

RegisterNUICallback('warsCloseShop', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeShop" })
    cb('ok')
end)

-- ============================================================
-- FULL INVENTORY  —  [TAB], the standard RP-server inventory key.
-- Data-driven grid (syringe / cash / equipped weapon today, easy
-- to drop more items into later from the server side).
-- ============================================================

RegisterKeyMapping('warsinventory', 'PvP Wars: Inventory', 'keyboard', 'TAB')

RegisterCommand('warsinventory', function()
    if not IsInWars and not IsWaitingWars then return end
    TriggerServerEvent('pvp-wars:requestInventory')
    SendNUIMessage({ type = "realEquippedWeapon", weapon = GetRealEquippedWeaponName() })
    SendNUIMessage({ type = "openInventory" })
    SetNuiFocus(true, true)
end, false)

RegisterNetEvent('pvp-wars:inventoryData')
AddEventHandler('pvp-wars:inventoryData', function(data)
    WarsState.syringeCount = data.syringe or 0
    WarsState.money        = data.money or 0
    WarsState.loadout      = data.loadout
    LOADOUT_WEAPON_NAMES   = data.weapons or LOADOUT_WEAPON_NAMES
    SendNUIMessage({ type = "inventoryData", data = data })
    SendNUIMessage({ type = "realEquippedWeapon", weapon = GetRealEquippedWeaponName() })
end)

RegisterNUICallback('warsCloseInventory', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeInventory" })
    cb('ok')
end)

RegisterNUICallback('warsUseSyringe', function(data, cb)
    if SyringeCooldown then cb('cooldown') return end
    TriggerServerEvent('pvp-wars:useSyringe')
    cb('ok')
end)

-- ============================================================
-- ADMIN PANEL NUI CALLBACK
-- (the admin panel itself is unchanged behavior-wise — only the
-- entry points into it changed: a player's request, or the new
-- /warsAdminPanel command, both of which push pvp-wars:adminState)
-- ============================================================

RegisterNUICallback('warsAdminAction', function(data, cb)
    TriggerServerEvent('pvp-wars:adminAction', data.action, data)
    cb('ok')
end)

RegisterNUICallback('warsOpenAdminPanel', function(data, cb)
    TriggerServerEvent('pvp-wars:adminAction', 'requestState', {})
    cb('ok')
end)

-- ============================================================
-- [F9] OPEN ADMIN PANEL DIRECTLY
-- FIX: notification toast subtext used to say "CLICK TO OPEN ADMIN
-- PANEL", but admins don't have mouse/cursor access over the NUI
-- while playing normally (no SetNuiFocus until the panel is already
-- open) -- there was nothing to click. F9 does exactly what the
-- toast's onclick did: request current state, which renders the
-- panel. Server-side IsAdmin() check on 'pvp-wars:adminAction' already
-- silently no-ops this for non-admins, so no client-side permission
-- check is needed here.
-- ============================================================

RegisterKeyMapping('warsAdminPanelKey', 'PvP Wars: Open Admin Panel', 'keyboard', 'F9')

RegisterCommand('warsAdminPanelKey', function()
    TriggerServerEvent('pvp-wars:adminAction', 'requestState', {})
end, false)

RegisterNUICallback('warsCloseAdminPanel', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeAdminPanel" })
    cb('ok')
end)

-- ============================================================
-- SERVER → CLIENT EVENTS
-- ============================================================

-- Shop + owned data received — update NUI
RegisterNetEvent('pvp-wars:shopData')
AddEventHandler('pvp-wars:shopData', function(data)
    LOADOUT_WEAPON_NAMES = (data and data.weapons) or LOADOUT_WEAPON_NAMES
    SendNUIMessage({ type = "shopData", data = data })
    -- Re-send once the real weapon list has actually arrived, in case
    -- the very first send (right when F4 was pressed, before this
    -- round trip completed) used a stale/empty cached list.
    SendNUIMessage({ type = "realEquippedWeapon", weapon = GetRealEquippedWeaponName() })
end)

-- Money update
RegisterNetEvent('pvp-wars:moneyUpdated')
AddEventHandler('pvp-wars:moneyUpdated', function(amount)
    WarsState.money = amount
    SendNUIMessage({ type = "moneyUpdated", amount = amount })
end)

-- Purchase result
RegisterNetEvent('pvp-wars:purchaseResult')
AddEventHandler('pvp-wars:purchaseResult', function(success, reason, weaponHash)
    if success then
        WarsState.ownedWeapons[weaponHash] = true
    end
    SendNUIMessage({ type = "purchaseResult", success = success, reason = reason, weapon = weaponHash })
end)

-- Loadout confirmed
RegisterNetEvent('pvp-wars:loadoutConfirmed')
AddEventHandler('pvp-wars:loadoutConfirmed', function(weaponHash)
    WarsState.loadout = weaponHash
    SendNUIMessage({ type = "loadoutConfirmed", weapon = weaponHash })

    -- Actually equip it right now -- this was the missing piece.
    -- Previously this only updated WarsState.loadout and showed a
    -- notification; the gun didn't reach your hands until the
    -- 2-second weapon-persistence watchdog happened to notice (or
    -- you respawned). Mirrors what pvp-turf's equipApproved does.
    if (IsInWars or IsWaitingWars) then
        ArmPlayer(weaponHash)
    end

    Notify("Loadout set to: " .. weaponHash, {100, 255, 150})
end)

-- Admin assigned you to a team (pre-session)
RegisterNetEvent('pvp-wars:teamAssigned')
AddEventHandler('pvp-wars:teamAssigned', function(side)
    local r, g, b = GetTeamColor(side)
    Notify(("You've been assigned to Team %s. Waiting for session to start..."):format(side:upper()), {r, g, b})
    SendNUIMessage({ type = "teamAssigned", team = side })
end)

-- ============================================================
-- SESSION START  —  teleport, arm, set state
-- ============================================================

RegisterNetEvent('pvp-wars:sessionStart')
AddEventHandler('pvp-wars:sessionStart', function(sessionData)
    IsInWars            = true
    IsWaitingWars        = false
    WarsState.active    = true
    WarsState.team      = sessionData.team
    WarsState.mapName   = sessionData.mapName
    WarsState.teammates = sessionData.teammates
    WarsState.syringeCount = sessionData.syringe or 0
    WarsState.money     = sessionData.money or 0
    WarsState.loadout   = sessionData.loadout
    WarsState.ownedWeapons = sessionData.ownedWeapons or {}

    -- The NUI force-closes the shop panel on sessionStart on its own
    -- (see index.html's 'sessionStart' case). With the panel's open/
    -- closed state now owned entirely by the NUI's own classList (see
    -- the 'toggleShop' fix), there's nothing for Lua to resync here.
    SetNuiFocus(false, false)

    -- Set pvp-core state to "wars" (treated like a combat state)
    pcall(function() exports["pvp-core"]:SetPlayerGameState("wars") end)

    local sp = sessionData.spawnPos
    TeleportToWars(sp, sessionData.team)

    -- Arm player with chosen loadout
    Citizen.SetTimeout(2500, function()
        ArmPlayer(sessionData.loadout)
    end)

    -- Update NUI — close anything that might still be open (map picker,
    -- shop) and switch the HUD into full "official session" mode.
    SendNUIMessage({
        type        = "sessionStart",
        team        = sessionData.team,
        mapName     = sessionData.mapName,
        teammates   = sessionData.teammates,
        syringe     = WarsState.syringeCount,
        money       = WarsState.money,
    })
end)

-- ============================================================
-- TELEPORT TO WARS SPAWN  (team may be nil while just "waiting")
-- ============================================================

function TeleportToWars(spawnPos, team)
    pcall(function() exports["pvp-core"]:SetPlayerTransitioning(true) end)

    DoScreenFadeOut(500)
    Citizen.Wait(600)

    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, true)
    SetEntityHeading(ped, spawnPos.w)

    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(spawnPos.x, spawnPos.y, spawnPos.z)
        Citizen.Wait(0)
    end
    Citizen.Wait(300)

    NetworkResurrectLocalPlayer(spawnPos.x, spawnPos.y, spawnPos.z, spawnPos.w, true, true, false)
    Citizen.Wait(100)
    ped = PlayerPedId()
    SetEntityHeading(ped, spawnPos.w)

    -- Full health + armor
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)

    -- Clear wanted level
    ClearPlayerWantedLevel(PlayerId())
    SetMaxWantedLevel(0)

    -- Remove invincibility (combat is live, even while just waiting)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)

    DoScreenFadeIn(500)
    pcall(function() exports["pvp-core"]:SetPlayerTransitioning(false) end)

    if team then
        local r, g, b = GetTeamColor(team)
        Notify(("Deployed to %s — You are on Team %s"):format(WarsState.mapName or "?", team:upper()), {r, g, b})
    else
        Notify(("Deployed to %s — waiting for an admin to start the match."):format(WarsState.mapName or "?"), {186, 130, 255})
    end
end

-- ============================================================
-- ARM PLAYER with loadout weapon + starter sidearm
-- (primaryHash nil = starter sidearm only, used while waiting)
--
-- skipSwitch (optional): when true, gives/refills the weapons but
-- does NOT force SetCurrentPedWeapon. This is what the persistence
-- thread below uses — without it, a routine top-up was yanking
-- whatever weapon the player was actively holding right out of
-- their hands every couple seconds (looked like "weapons randomly
-- getting removed" mid-fight).
-- ============================================================

function ArmPlayer(primaryHash, skipSwitch)
    local ped = PlayerPedId()

    -- Starter sidearm — always Badged Eagle or glock17s equivalent
    GiveWeaponToPed(ped, GetHashKey("weapon_glock17s"), 120, false, false)

    -- Primary loadout
    if primaryHash and primaryHash ~= "" then
        GiveWeaponToPed(ped, GetHashKey(primaryHash), 180, false, true)
    end

    if not skipSwitch then
        SetCurrentPedWeapon(ped, primaryHash and GetHashKey(primaryHash) or GetHashKey("weapon_glock17s"), true)
    end
end

-- ============================================================
-- SYRINGE  —  Use animation + heal
-- ============================================================

function UseSyringe()
    if SyringeCooldown then
        Notify("Syringe on cooldown!", {255, 150, 0})
        return
    end
    if WarsState.syringeCount <= 0 then
        Notify("No syringes left!", {255, 80, 80})
        return
    end
    if IsAnimPlaying then return end

    -- Request approval from server first
    TriggerServerEvent('pvp-wars:useSyringe')
end

-- Server approved syringe use
RegisterNetEvent('pvp-wars:syringeResult')
AddEventHandler('pvp-wars:syringeResult', function(approved, remaining)
    if not approved then
        Notify("No syringes left!", {255, 80, 80})
        return
    end

    WarsState.syringeCount = remaining
    SyringeCooldown = true

    -- Play injection animation
    Citizen.CreateThread(function()
        IsAnimPlaying = true
        local ped = PlayerPedId()

        local animDict = "mp_suicide"
        local animName = "pill"

        RequestAnimDict(animDict)
        local animTimeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(animDict) and GetGameTimer() < animTimeout do
            Citizen.Wait(50)
        end

        if HasAnimDictLoaded(animDict) then
            TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 2500, 49, 0, false, false, false)
            Citizen.Wait(1800)
        end

        -- Apply heal
        local currentHealth = GetEntityHealth(ped)
        local maxHealth     = 200
        local healAmt       = 40
        SetEntityHealth(ped, math.min(currentHealth + healAmt, maxHealth))

        -- Apply armor
        local currentArmor = GetPedArmour(ped)
        SetPedArmour(ped, math.min(currentArmor + 25, 100))

        Notify(("Syringe used! +%d HP, +25 Armor | Remaining: %d"):format(healAmt, remaining), {100, 255, 150})
        SendNUIMessage({ type = "syringeUpdate", count = remaining })

        RemoveAnimDict(animDict)
        IsAnimPlaying  = false

        -- 8 second cooldown
        Citizen.Wait(8000)
        SyringeCooldown = false
    end)
end)

-- ============================================================
-- SYRINGE PURCHASE RESULT  (from the Items tab in the Loadout Shop)
-- ============================================================

RegisterNetEvent('pvp-wars:syringePurchaseResult')
AddEventHandler('pvp-wars:syringePurchaseResult', function(success, reason, newCount)
    if success then
        WarsState.syringeCount = newCount
        SendNUIMessage({ type = "syringePurchaseResult", success = true, count = newCount })
        SendNUIMessage({ type = "syringeUpdate", count = newCount })
    else
        SendNUIMessage({ type = "syringePurchaseResult", success = false, reason = reason })
        local msg = (reason == "max owned") and "You're already carrying the max number of syringes."
            or "Not enough cash for a syringe."
        Notify(msg, {255, 150, 0})
    end
end)

-- ============================================================
-- KEYBIND: G = Use Syringe (quick-use, separate from opening
-- the full inventory with TAB)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if IsInWars or IsWaitingWars then
            if IsControlJustPressed(0, 47) then   -- G key = INPUT_DETONATE in GTA
                UseSyringe()
            end
        end
    end
end)

-- ============================================================
-- TEAM OVERHEAD MARKERS
-- Draws a colored "[ALPHA]" or "[BRAVO]" above each teammate
-- ============================================================

RegisterNetEvent('pvp-wars:rosterSync')
AddEventHandler('pvp-wars:rosterSync', function(alphaList, bravoList)
    TeamMarkers = {}
    for _, p in ipairs(alphaList) do
        TeamMarkers[p.id] = { team = "alpha", name = p.name }
    end
    for _, p in ipairs(bravoList) do
        TeamMarkers[p.id] = { team = "bravo", name = p.name }
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if IsInWars then
            local myPed    = PlayerPedId()
            local myPos    = GetEntityCoords(myPed)
            local myTeam   = WarsState.team
            local myName   = GetPlayerName(PlayerId())

            local players = GetActivePlayers()
            for _, playerId in ipairs(players) do
                if playerId ~= PlayerId() then
                    local targetPed = GetPlayerPed(playerId)
                    if DoesEntityExist(targetPed) and not IsEntityDead(targetPed) then
                        local targetPos  = GetEntityCoords(targetPed)
                        local dist       = #(myPos - targetPos)
                        local serverSrc  = GetPlayerServerId(playerId)
                        local markerInfo = TeamMarkers[serverSrc]

                        if markerInfo and dist < 60.0 then
                            local team       = markerInfo.team
                            local r, g, b    = GetTeamColor(team)
                            local label      = (team == myTeam) and ("[" .. team:upper() .. "]  " .. markerInfo.name)
                                               or ("[" .. team:upper() .. "]  " .. markerInfo.name)

                            -- Teammates: full brightness. Enemies: slightly dimmer (red visible)
                            local a = (team == myTeam) and 230 or 200
                            if team ~= myTeam then r, g, b = 255, 60, 60 end

                            local fadeStart = 40.0
                            if dist > fadeStart then
                                a = math.floor(a * (1.0 - (dist - fadeStart) / (60.0 - fadeStart)))
                            end

                            Draw3DTextWars(
                                targetPos.x, targetPos.y, targetPos.z + 1.05,
                                label, 0.40, a, r, g, b
                            )
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- KILL FEED  (broadcast from server)
-- ============================================================

RegisterNetEvent('pvp-wars:addKillFeed')
AddEventHandler('pvp-wars:addKillFeed', function(killerName, victimName, isHeadshot)
    SendNUIMessage({
        type       = "warsKillFeed",
        killer     = killerName,
        victim     = victimName,
        headshot   = isHeadshot,
    })
end)

RegisterNetEvent('pvp-wars:leaderboardUpdate')
AddEventHandler('pvp-wars:leaderboardUpdate', function(rows)
    SendNUIMessage({ type = "leaderboardUpdate", rows = rows })
end)

-- ============================================================
-- DEATH  —  Request respawn from server (official session only;
-- while just "waiting" there's no respawn pipeline — get back up
-- the normal hub-style way, you're not in a scored match yet)
-- ============================================================

local WarsDeathReported = false

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if not IsInWars then return end

    local victim = data[1]
    local ped    = PlayerPedId()

    if victim ~= ped then return end
    if WarsDeathReported then return end

    local isFatal = (data[5] == 1)
        or (DoesEntityExist(victim) and (IsEntityDead(victim) or GetEntityHealth(victim) <= 0))

    if not isFatal then return end

    WarsDeathReported = true

    Citizen.SetTimeout(3000, function()
        WarsDeathReported = false
        -- Request server-authoritative respawn
        TriggerServerEvent('pvp-wars:requestRespawn')
        Notify("Respawning...", {255, 180, 50})
    end)
end)

-- ============================================================
-- KILL REPORT  (we killed someone)
-- ============================================================

local RecentKillVictims = {}

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    -- Stays broad here (waiting OR official) -- this just lets the
    -- event handler run far enough to figure out isNpc below. The
    -- actual "should this pay" decision is scoped per-kill-type a
    -- few lines down, and enforced again server-side regardless.
    if not IsInWars and not IsWaitingWars then return end

    local victim   = data[1]
    local attacker = data[2]
    local ped      = PlayerPedId()

    if attacker ~= ped then return end
    if victim == ped then return end
    if RecentKillVictims[victim] then return end

    local isFatal = (data[5] == 1)
        or (DoesEntityExist(victim) and (IsEntityDead(victim) or GetEntityHealth(victim) <= 0))
        or (not DoesEntityExist(victim))  -- entity deleted = likely fatal

    if not isFatal then return end

    local isNpc = not IsPedAPlayer(victim)

    -- FIX (scoped correctly): only NPC kills should be reportable while
    -- just "waiting" on a map. Player-vs-player kills during waiting
    -- aren't a scored match (no teams), so don't even bother sending
    -- the report for those -- server would reject it anyway now, but
    -- no reason to make the round trip.
    if not isNpc and not IsInWars then return end

    RecentKillVictims[victim] = true
    Citizen.SetTimeout(5000, function() RecentKillVictims[victim] = nil end)

    local victimName = "Unknown"
    if isNpc then
        victimName = "NPC"
    elseif DoesEntityExist(victim) then
        local victimPlayerId = NetworkGetPlayerIndexFromPed(victim)
        if victimPlayerId then victimName = GetPlayerName(victimPlayerId) or "Unknown" end
    end

    local hasBone, bone = GetPedLastDamageBone(victim)
    local isHeadshot = (hasBone and bone == 31086)

    -- TEMP DIAGNOSTIC: confirms the client-side detector actually
    -- reaches the point of sending the report. Safe to remove once
    -- confirmed from these logs (check F8 console).
    print(("[WARS DEBUG CLIENT] Sending killReport: victim=%s isNpc=%s headshot=%s IsInWars=%s IsWaitingWars=%s")
        :format(victimName, tostring(isNpc), tostring(isHeadshot), tostring(IsInWars), tostring(IsWaitingWars)))

    TriggerServerEvent('pvp-wars:killReport', victimName, isHeadshot, isNpc)
end)

-- ============================================================
-- RESPAWN APPROVED
-- ============================================================

RegisterNetEvent('pvp-wars:respawnApproved')
AddEventHandler('pvp-wars:respawnApproved', function(spawnPos, syringeCount)
    WarsState.syringeCount = syringeCount or WarsState.syringeCount
    TeleportToWars(spawnPos, WarsState.team)
    Citizen.SetTimeout(1000, function()
        ArmPlayer(WarsState.loadout)
    end)
    SendNUIMessage({ type = "syringeUpdate", count = WarsState.syringeCount })
end)

-- ============================================================
-- SESSION END
-- ============================================================

RegisterNetEvent('pvp-wars:sessionEnd')
AddEventHandler('pvp-wars:sessionEnd', function(reason)
    IsInWars            = false
    IsWaitingWars        = false
    WarsState.active    = false
    WarsState.team      = nil
    WarsState.teammates = {}
    TeamMarkers         = {}

    SendNUIMessage({ type = "sessionEnd", reason = reason })
    SetNuiFocus(false, false)

    -- Return to hub
    Citizen.SetTimeout(1500, function()
        TriggerEvent("hub:returnToHub")  -- fires pvp-hub's /hub logic
        -- Fallback: if hub event doesn't exist, use command
        ExecuteCommand("hub")
    end)

    Notify(("Wars ended: %s"):format(reason or ""), {200, 200, 200})
end)

RegisterNetEvent('pvp-wars:leaveConfirmed')
AddEventHandler('pvp-wars:leaveConfirmed', function()
    IsInWars = false
    IsWaitingWars = false
    WarsState = {
        active = false, team = nil, mapName = nil, teammates = {},
        syringeCount = 0, money = 0, loadout = nil, ownedWeapons = {},
        teamColor = { alpha = {30, 120, 255}, bravo = {255, 60, 60} },
    }
    TeamMarkers = {}
    SendNUIMessage({ type = "sessionEnd" })
    ExecuteCommand("hub")
end)

-- ============================================================
-- LOCAL "LEFT WARS" EVENT  —  same pattern as redzone:leave /
-- turfwars:left. Fires INSTANTLY, client-side, no server round
-- trip required. This is what /hub calls so leaving Wars via
-- /hub works exactly as reliably as leaving Redzone/Turf via
-- /hub always has. Also tells the server so session/ownership
-- bookkeeping (team rosters, SESSION.loadouts, etc.) stays correct,
-- but does NOT wait on that round trip to reset local state.
-- ============================================================

AddEventHandler("wars:left", function()
    if not IsInWars and not IsWaitingWars then return end

    -- Let the server know so it can clean up team rosters / session
    -- data for this player, but don't block local cleanup on it.
    if IsInWars then
        TriggerServerEvent('pvp-wars:requestLeave')
    elseif IsWaitingWars then
        TriggerServerEvent('pvp-wars:requestLeaveWaiting')
    end

    IsInWars     = false
    IsWaitingWars = false
    WarsState = {
        active = false, team = nil, mapName = nil, teammates = {},
        syringeCount = 0, money = 0, loadout = nil, ownedWeapons = {},
        teamColor = { alpha = {30, 120, 255}, bravo = {255, 60, 60} },
    }
    TeamMarkers = {}

    SendNUIMessage({ type = "sessionEnd" })
    SetNuiFocus(false, false)
end)

-- ============================================================
-- ADMIN PANEL EVENTS
-- ============================================================

-- Admin gets notified of a player's request (manual /warAdmin OR
-- automatic, from picking a map)
RegisterNetEvent('pvp-wars:adminRequest')
AddEventHandler('pvp-wars:adminRequest', function(requesterId, requesterName, reasonText)
    SendNUIMessage({
        type          = "adminNotification",
        requesterName = requesterName,
        requesterId   = requesterId,
        reasonText    = reasonText,
    })
    Notify(("~y~%s~w~ (id:%d) %s!"):format(requesterName, requesterId, reasonText or "wants a Wars session"), {255, 220, 50})
end)

-- Admin receives current session state
RegisterNetEvent('pvp-wars:adminState')
AddEventHandler('pvp-wars:adminState', function(stateData)
    SendNUIMessage({ type = "adminState", data = stateData })
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "openAdminPanel" })
end)

-- Admin feedback (success/error from server actions)
RegisterNetEvent('pvp-wars:adminFeedback')
AddEventHandler('pvp-wars:adminFeedback', function(msg, success)
    local color = success and {100, 255, 150} or {255, 80, 80}
    Notify(msg, color)
    SendNUIMessage({ type = "adminFeedback", message = msg, success = success })
end)

-- ============================================================
-- WEAPON PERSISTENCE THREAD
-- Keep player armed with loadout during wars (prevents losing weapons on death frame)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if IsInWars and WarsState.loadout then
            local ped = PlayerPedId()
            if not IsEntityDead(ped) and not HasPedGotWeapon(ped, GetHashKey(WarsState.loadout), false) then
                -- skipSwitch = true: re-supply the missing loadout weapon
                -- WITHOUT yanking whatever weapon the player currently has
                -- out of their hands. This is what was causing weapons to
                -- randomly seem to "get removed" mid-fight.
                ArmPlayer(WarsState.loadout, true)
            end
        end
    end
end)

-- ============================================================
-- /warAdmin COMMAND
-- FIX: this used to also be registered here on the client with
-- RegisterCommand('warAdmin', ...), firing TriggerServerEvent('warAdmin')
-- -- but nothing on the server was ever listening for a net event
-- called 'warAdmin' (the server only has RegisterCommand('warAdmin', ...),
-- which is a totally different system from TriggerServerEvent/
-- RegisterNetEvent). Worse, registering the SAME command name
-- ('warAdmin') on the client meant typing /warAdmin got intercepted
-- by THIS dead client command before it ever reached the server's
-- real one -- so the server-side RequestAdminHelp() that actually
-- pings admins never ran from chat at all. It only worked from
-- entry-UI's "ping admin" button because that takes a completely
-- different path (TriggerServerEvent('pvp-wars:adminRequest'), which
-- IS a real, listened-for net event on the server -- see below).
-- Removing this client command lets /warAdmin fall through to the
-- server's own RegisterCommand('warAdmin', ...), which already pings
-- admins correctly via RequestAdminHelp(). No client-side command
-- needed at all for this one.
-- ============================================================

-- ============================================================
-- /warsleave COMMAND  — leaves either an official session or
-- just the casual "waiting on a map" state, whichever applies.
-- ============================================================

RegisterCommand('warsleave', function()
    if IsInWars then
        TriggerServerEvent('pvp-wars:requestLeave')
    elseif IsWaitingWars then
        TriggerServerEvent('pvp-wars:requestLeaveWaiting')
    else
        Notify("You are not in Wars.", {255, 150, 0})
    end
end, false)

-- ============================================================
-- INITIALIZATION
-- ============================================================

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Citizen.SetTimeout(2000, SpawnWarsNPC)

    -- Reset NUI focus and force every overlay closed on (re)start, so a
    -- panel that was left open from before a resource restart can never
    -- carry over as a stuck full-screen overlay.
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMapPicker" })
    SendNUIMessage({ type = "closeShop" })
    SendNUIMessage({ type = "closeInventory" })
    SendNUIMessage({ type = "closeAdminPanel" })
end)
