local lastWeapon = `WEAPON_UNARMED`

-- Utility: Load animation dictionary
function LoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Wait(0)
        end
    end
end

-- Determine weapon group for draw animation
local function GetWeaponGroup(weapon)
    local group = GetWeapontypeGroup(weapon)
    if group == `GROUP_PISTOL` then
        return "pistol"
    elseif group == `GROUP_SMG` then
        return "smg"
    else
        return nil
    end
end

-- Utility: Check if player can play anim
function CanPlayDrawAnim()
    local ped = PlayerPedId()
    return not IsPedInAnyVehicle(ped, false) 
        and not IsPedFalling(ped) 
        and not IsPedSwimming(ped)
        and not IsPedClimbing(ped)
        and GetEntityHealth(ped) > 0
end

-- Play the draw animation
function PlayDrawAnimation(preset)
    local ped = PlayerPedId()

    print("Trying anim:", preset.dict, preset.anim)

    RequestAnimDict(preset.dict)

    local timeout = 0
    while not HasAnimDictLoaded(preset.dict) and timeout < 5000 do
        Wait(10)
        timeout = timeout + 10
    end

    print("Loaded:", HasAnimDictLoaded(preset.dict))

    TaskPlayAnim(
        ped,
        preset.dict,
        preset.anim,
        preset.blendIn,
        preset.blendOut,
        preset.duration,
        49,
        preset.playbackRate,
        false,
        false,
        false
    )
    print(GetWeapontypeGroup(GetHashKey("WEAPON_ICEDGLOCK")))
end

-- Weapon detection thread
CreateThread(function()
    while true do
        Wait(50)

        local ped = PlayerPedId()
        local currentWeapon = GetSelectedPedWeapon(ped)

        if currentWeapon ~= lastWeapon then

            if lastWeapon == `WEAPON_UNARMED`
            and currentWeapon ~= `WEAPON_UNARMED` then

                local group = GetWeaponGroup(currentWeapon)

                if group and CanPlayDrawAnim() then

                    local weaponToEquip = currentWeapon

                    -- Force back to unarmed
                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

                    local preset = nil
                    if group == "pistol" then
                        preset = Config.Presets[1]
                    elseif group == "smg" then
                        preset = Config.Presets[2]
                    end

                    if preset then
                        PlayDrawAnimation(preset)
                        Wait(preset.duration)
                    end

                    -- Re-equip weapon
                    SetCurrentPedWeapon(ped, weaponToEquip, true)

                    lastWeapon = weaponToEquip
                else
                    lastWeapon = currentWeapon
                end
            else
                lastWeapon = currentWeapon
            end
        end
    end
end)

-- Initialize
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        lastWeapon = GetSelectedPedWeapon(PlayerPedId())
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up any running animations
        local ped = PlayerPedId()
        for _, preset in ipairs(Config.Presets) do
            StopAnimTask(ped, preset.dict, preset.anim, 1.0)
        end
    end
end)