-- ============================================================
-- PVP WEAPONS CLIENT
-- Global Gun Rotation System — Purple NUI Edition
-- ============================================================

local InCombatMode      = false
local CurrentWeaponHash = nil
local CurrentWeaponName = "None"
local RotationEndTime   = 0

-- Uses GLOBAL GunRotationList from config.lua (shared_script)

-- ============================================================
-- NUI HELPERS
-- ============================================================

function SendGunRotNUI(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

function FormatTimer(ms)
    local s = math.max(0, math.floor(ms / 1000))
    local m = math.floor(s / 60)
    local sec = s % 60
    return string.format("%02d:%02d", m, sec)
end

-- ============================================================
-- STATE MONITOR
-- ============================================================

AddEventHandler("pvp-core:stateChanged", function(newState)
    if newState == "hub" then
        InCombatMode = false
        RemoveAllPedWeapons(PlayerPedId(), true)
        SendGunRotNUI('hideGunRot')
    elseif newState == "turfwars" then
        InCombatMode = false
        SendGunRotNUI('hideGunRot')
    elseif newState == "wars" then
        -- pvp-wars has its own loadout shop and arms players itself.
        -- This system must NEVER touch weapons or show its UI here --
        -- treating "wars" as combat mode (the old catch-all `else` did
        -- this implicitly) is what was randomly stripping the player's
        -- weapon and forcing the rotation gun + Gun Rotation badge into
        -- Wars sessions.
        InCombatMode = false
        SendGunRotNUI('hideGunRot')
    elseif newState == "redzone" then
        InCombatMode = true
        if CurrentWeaponHash then
            GiveRotationWeapon()
            SendGunRotNUI('showGunRot', {
                weaponName = CurrentWeaponName,
                timerStr   = FormatTimer(math.max(0, RotationEndTime - GetGameTimer()))
            })
        end
    else
        -- Unknown/future state: default OFF rather than silently
        -- treating it as combat mode.
        InCombatMode = false
        SendGunRotNUI('hideGunRot')
    end
end)

-- ============================================================
-- SYNC FROM SERVER
-- ============================================================

RegisterNetEvent("pvp-weapons:syncRotation")
AddEventHandler("pvp-weapons:syncRotation", function(weaponHash, weaponName, secondsRemaining)
    CurrentWeaponHash = weaponHash
    CurrentWeaponName = weaponName
    RotationEndTime   = GetGameTimer() + (secondsRemaining * 1000)

    if InCombatMode then
        GiveRotationWeapon()
        SendGunRotNUI('showGunRot', {
            weaponName = CurrentWeaponName,
            timerStr   = FormatTimer(secondsRemaining * 1000)
        })
    end
end)

-- ============================================================
-- GIVE CURRENT ROTATION WEAPON (NO FLICKER)
-- ============================================================

function GiveRotationWeapon()
    local ped = PlayerPedId()
    local hash = GetHashKey(CurrentWeaponHash)
    local selected = GetSelectedPedWeapon(ped)

    -- Already holding the correct rotation weapon? Just top off ammo, no animation.
    if selected == hash and HasPedGotWeapon(ped, hash, false) then
        SetPedAmmo(ped, hash, 999)
        return
    end

    -- Have it but holstered? Just equip it, no remove/give animation.
    if HasPedGotWeapon(ped, hash, false) then
        SetCurrentPedWeapon(ped, hash, true)
        SetPedAmmo(ped, hash, 999)
        return
    end

    -- Actually need to give the weapon. Load asset first.
    if not HasWeaponAssetLoaded(hash) then
        RequestWeaponAsset(hash, 31, 0)
        local timeout = 0
        while not HasWeaponAssetLoaded(hash) and timeout < 500 do
            Wait(0)
            timeout = timeout + 1
        end
    end

    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, hash, 999, false, true)
    SetPedAmmo(ped, hash, 999)
    SetCurrentPedWeapon(ped, hash, true)

    
end

-- ============================================================
-- NUI HUD TIMER UPDATE (1s tick)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        if InCombatMode and CurrentWeaponHash then
            local remMs = math.max(0, RotationEndTime - GetGameTimer())
            local remS  = math.floor(remMs / 1000)

            SendGunRotNUI('updateGunRot', {
                weaponName  = CurrentWeaponName,
                timerStr    = FormatTimer(remMs),
                secondsLeft = remS
            })
        end
    end
end)

-- ============================================================
-- INFINITE AMMO IN COMBAT
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        if InCombatMode then
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
-- LEGACY EVENTS
-- ============================================================

RegisterNetEvent("pvp-weapons:giveLoadout")
AddEventHandler("pvp-weapons:giveLoadout", function(mode)
    if InCombatMode and CurrentWeaponHash then
        GiveRotationWeapon()
    end
end)

AddEventHandler("playerSpawned", function()
    if InCombatMode and CurrentWeaponHash then
        GiveRotationWeapon()
    end
end)

-- ============================================================
-- INITIALIZATION & PRE-CACHE (WEAPON ASSETS ONLY)
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end


    Citizen.CreateThread(function()
        local loaded = 0
        for _, gun in ipairs(GunRotationList) do
            local hash = GetHashKey(gun.hash)

            if not HasWeaponAssetLoaded(hash) then
                RequestWeaponAsset(hash, 31, 0)
            end

            local timeout = 0
            while not HasWeaponAssetLoaded(hash) and timeout < 500 do
                Wait(0)
                timeout = timeout + 1
            end

            if HasWeaponAssetLoaded(hash) then
                loaded = loaded + 1
            else
            end
        end

    end)
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, gun in ipairs(GunRotationList) do
        local hash = GetHashKey(gun.hash)
        if HasWeaponAssetLoaded(hash) then
            RemoveWeaponAsset(hash)
        end
    end
end)