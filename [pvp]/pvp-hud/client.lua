-- ============================================================
-- PVP HUD CLIENT
-- ============================================================

local ShowHUD = false
local ScoreboardOpen = false
local StreaksEnabled = true
local InWars = false  -- Wars doesn't use this resource's scoreboard

function SendNUI(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- ============================================================
-- STREAK TOGGLE COMMAND
-- ============================================================

RegisterCommand('streaks', function()
    StreaksEnabled = not StreaksEnabled
    local status = StreaksEnabled and 'ENABLED' or 'DISABLED'
    TriggerEvent('chat:addMessage', {
        color = {160, 60, 255},
        multiline = false,
        args = {'[PvP HUD]', 'Kill streak medals ' .. status}
    })
end, false)

-- ============================================================
-- STREAK MEDAL RECEIVER
-- ============================================================

RegisterNetEvent('pvp-hud:showStreak')
AddEventHandler('pvp-hud:showStreak', function(data)
    if not StreaksEnabled then return end
    SendNUI('showStreak', data)
end)

-- Initialize
AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    Wait(1000)
    SendNUI('setSource', { source = GetPlayerServerId(PlayerId()) })

    ShowHUD = false
    ScoreboardOpen = false
    SendNUI('hideMatchInfo', {})
    SendNUI('hideCountdown', {})
    SendNUI('hideMatchEnd', {})
    SendNUI('hideScoreboard', {})
    SendNUI('hideLobby', {})
    SendNUI('hideHealthArmor', {})
    SendNUI('hideAmmoHud', {})
end)

-- ============================================================
-- PVP-CORE STATE CHANGE HANDLER
-- ============================================================

AddEventHandler("pvp-core:stateChanged", function(newState)
    if newState == "hub" then
        ShowHUD = false
        InWars = false
        ScoreboardOpen = false
        TriggerServerEvent('pvp-hud:resetMyStats')
        SendNUI('updateScoreboard', { players = {} })
        SendNUI('hideMatchInfo', {})
        SendNUI('hideCountdown', {})
        SendNUI('hideMatchEnd', {})
        SendNUI('hideScoreboard', {})
        SendNUI('hideLobby', {})
        SendNUI('hideHealthArmor', {})
        SendNUI('hideAmmoHud', {})
    elseif newState == "redzone" or newState == "turfwars" then
        ShowHUD = true
        InWars = false
        SendNUI('hideCountdown', {})
        SendNUI('hideMatchEnd', {})
        SendNUI('hideLobby', {})
        SendNUI('showHealthArmor', {})
    elseif newState == "wars" then
        -- pvp-wars has its own overlay for team pill, kill feed, and shop
        -- panels -- but it DOES want health/armor bar and ammo HUD from this
        -- resource. ShowHUD = true enables those two threads. The scoreboard/
        -- match-info/countdown/lobby widgets don't belong here; hide them.
        ShowHUD = true
        InWars = true
        ScoreboardOpen = false
        SendNUI('updateScoreboard', { players = {} })
        SendNUI('hideMatchInfo', {})
        SendNUI('hideCountdown', {})
        SendNUI('hideMatchEnd', {})
        SendNUI('hideScoreboard', {})
        SendNUI('hideLobby', {})
        SendNUI('showHealthArmor', {})
    end
end)

-- ============================================================
-- OPTIONAL MATCH EVENTS (triggered by gamemode logic)
-- ============================================================

RegisterNetEvent("pvp-core:countdownStart")
AddEventHandler("pvp-core:countdownStart", function(data)
    ShowHUD = true
    SendNUI('hideMatchEnd', {})
    SendNUI('showCountdown', { mode = data.mode, timer = data.timer })
    SendNUI('showMatchInfo', { mode = data.mode, winScore = 30 })
end)

RegisterNetEvent("pvp-core:countdownTick")
AddEventHandler("pvp-core:countdownTick", function(time)
    SendNUI('countdownTick', { time = time })
end)

RegisterNetEvent("pvp-core:matchStart")
AddEventHandler("pvp-core:matchStart", function(match)
    ShowHUD = true
    SendNUI('hideCountdown', {})
    SendNUI('hideLobby', {})
    SendNUI('hideMatchEnd', {})
    SendNUI('showMatchInfo', { mode = match.mode, winScore = 30 })
end)

RegisterNetEvent("pvp-core:matchEnd")
AddEventHandler("pvp-core:matchEnd", function(data)
    SendNUI('showMatchEnd', { winnerName = data.winnerName, scores = data.scores })
    SendNUI('hideMatchInfo', {})
end)

RegisterNetEvent("pvp-core:scoreUpdate")
AddEventHandler("pvp-core:scoreUpdate", function(data)
    if not ShowHUD then return end
    SendNUI('updateScore', { scores = data.scores })
    SendNUI('updateScoreboard', { players = data.players })
    SendNUI('updateTimer', { time = data.timer })
end)

RegisterNetEvent("pvp-core:killFeed")
AddEventHandler("pvp-core:killFeed", function(data)
    SendNUI('killFeed', data)
end)

RegisterNetEvent("pvp-core:matchState")
AddEventHandler("pvp-core:matchState", function(state)
    if state.phase == "waiting" then
        SendNUI('showLobby', { players = 0, minPlayers = 1 })
    end
end)

-- ============================================================
-- HEALTH & ARMOR BAR - Redzone/Turf Wars only (same ShowHUD flag
-- as the rest of this resource's UI). This used to run completely
-- unconditionally and never hid itself -- that's what was showing
-- this bar in Wars (and Hub) on top of/alongside their own HUDs.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        if not ShowHUD then goto continue end

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local health = GetEntityHealth(ped)
            local armor = GetPedArmour(ped)
            local maxHealth = GetEntityMaxHealth(ped)

            local displayHp = health - 100
            if displayHp < 0 then displayHp = 0 end
            local displayMaxHp = maxHealth - 100
            if displayMaxHp <= 0 then displayMaxHp = 100 end

            SendNUI('updateHealthArmor', {
                health = displayHp,
                armor = armor,
                maxHealth = displayMaxHp,
                maxArmor = 100
            })
        end

        ::continue::
    end
end)

-- ============================================================
-- WEAPON / AMMO HUD - ALWAYS RUNS (only visible when a gun is out)
-- ============================================================

-- Self-contained name table so this resource doesn't need an export
-- from pvp-weapons. Covers stock GTA weapons + the server's custom
-- arsenal skins (kept in sync with pvp-weapons/config.lua's
-- GunRotationList so the name shown here matches the shop).
local WeaponDisplayNames = {
    [GetHashKey("WEAPON_KNIFE")] = "Knife",
    [GetHashKey("WEAPON_PISTOL")] = "Pistol",
    [GetHashKey("WEAPON_COMBATPISTOL")] = "Combat Pistol",
    [GetHashKey("WEAPON_HEAVYPISTOL")] = "Heavy Pistol",
    [GetHashKey("WEAPON_APPISTOL")] = "AP Pistol",
    [GetHashKey("WEAPON_ASSAULTRIFLE")] = "Assault Rifle",
    [GetHashKey("WEAPON_SPECIALCARBINE")] = "Special Carbine",
    [GetHashKey("WEAPON_BULLPUPRIFLE")] = "Bullpup Rifle",
    [GetHashKey("WEAPON_PUMPSHOTGUN")] = "Pump Shotgun",
    [GetHashKey("WEAPON_ASSAULTSHOTGUN")] = "Assault Shotgun",
    [GetHashKey("WEAPON_SNIPERRIFLE")] = "Sniper Rifle",
    [GetHashKey("WEAPON_HEAVYSNIPER")] = "Heavy Sniper",
    [GetHashKey("WEAPON_MARKSMANRIFLE")] = "Marksman Rifle",
    [GetHashKey("WEAPON_COMBATMG")] = "Combat MG",
    [GetHashKey("WEAPON_MG")] = "MG",
    [GetHashKey("WEAPON_SMG")] = "SMG",
    [GetHashKey("WEAPON_MICROSMG")] = "Micro SMG",
    [GetHashKey("w_sb_minismg")] = "Mini SMG",

    -- Server arsenal skins
    [GetHashKey("weapon_iceglock")] = "Ice Glock",
    [GetHashKey("weapon_badgedeagle")] = "Badged Eagle",
    [GetHashKey("weapon_blackiceglock")] = "Black Ice Glock",
    [GetHashKey("weapon_glock18dt")] = "Glock 18DT",
    [GetHashKey("weapon_nbk")] = "NBK",
    [GetHashKey("weapon_revolver357")] = "Revolver 357",
    [GetHashKey("weapon_hotshotwelder")] = "Hotshot Welder",
    [GetHashKey("weapon_ibak")] = "IBAK",
    [GetHashKey("weapon_m4a1sgyspunkred")] = "M4A1 Gyspunk Red",
    [GetHashKey("weapon_m4hyperbeast")] = "M4 Hyperbeast",
    [GetHashKey("weapon_retrom4a4")] = "Retro M4A4",
    [GetHashKey("weapon_junker")] = "Junker",
    [GetHashKey("weapon_crimsonsnowvector")] = "Crimson Snow Vector",
    [GetHashKey("weapon_blackicemp7")] = "Black Ice MP7",
    [GetHashKey("weapon_p90")] = "P90",
    [GetHashKey("weapon_spaceflightmp5")] = "Spaceflight MP5",
    [GetHashKey("weapon_acrcqb")] = "ACR CQB",
    [GetHashKey("weapon_asm1")] = "ASM1",
    [GetHashKey("weapon_blastxspectre")] = "BlastX Spectre",
    [GetHashKey("weapon_candymp5")] = "Candy MP5",
    [GetHashKey("weapon_coldhunterthompson")] = "Cold Hunter Thompson",
    [GetHashKey("weapon_cx9")] = "CX-9",
    [GetHashKey("weapon_dssmg")] = "DS SMG",
    [GetHashKey("weapon_icevector")] = "Ice Vector",
    [GetHashKey("weapon_minicarbine")] = "Mini Carbine",
    [GetHashKey("weapon_mp40type2")] = "MP40 Type 2",
    [GetHashKey("weapon_r99")] = "R-99",
    [GetHashKey("weapon_tbsvector")] = "TBS Vector",
    [GetHashKey("weapon_vesperhybrid")] = "Vesper Hybrid",
    [GetHashKey("weapon_vss")] = "VSS",
    [GetHashKey("weapon_nailgun")] = "Nailgun",
    [GetHashKey("weapon_glock17s")] = "Glock 17S",
    [GetHashKey("weapon_glock30")] = "Glock 30",
    [GetHashKey("weapon_glock34")] = "Glock 34",
    [GetHashKey("WEAPON_ICEDBONGSHOT")] = "Iced Bong Shot",
    [GetHashKey("WEAPON_ICEDFAL")] = "Iced FAL",
    [GetHashKey("WEAPON_ICEDGLOCK")] = "Iced Glock",
    [GetHashKey("WEAPON_ICEDMZA")] = "Iced MZA",
    [GetHashKey("WEAPON_ICEDP90")] = "Iced P90",
    [GetHashKey("WEAPON_ICEDQP12")] = "Iced QP12",
    [GetHashKey("WEAPON_ICEDR4C")] = "Iced R4-C",
    [GetHashKey("WEAPON_KURONAMIVANDAL")] = "Kuronami Vandal",
}

local WEAPON_UNARMED = GetHashKey("WEAPON_UNARMED")
local GROUP_MELEE = GetHashKey("GROUP_MELEE")
local AmmoHudVisible = false

-- ── WHY THIS DOESN'T WATCH FOR A "RELOAD" KEYPRESS ──
-- Earlier version reset the displayed clip only when the player
-- pressed Reload. That was the wrong model for this server: ammo here
-- genuinely auto-refills on its own (pvp-weapons/pvp-turf/redzone all
-- run threads that call SetPedAmmo(ped, weapon, 9999) periodically),
-- so the player never has to press Reload at all -- which is exactly
-- why watching for that keypress broke (missed it during auto-spray,
-- falsely caught it mid-animation, etc). There's no reliable way to
-- detect "reload genuinely finished" as a discrete event here.
-- So instead: just mirror GetAmmoInClip directly, every single frame
-- (Wait(0)). At that polling rate we catch real per-shot depletion as
-- it happens (long before the next 200-250ms external refill), AND we
-- correctly reflect every real refill the instant it happens -- manual
-- or automatic, it doesn't matter, because we're not trying to
-- classify *why* it changed, just showing what it actually is right now.
--
-- Max clip still isn't read from a native (GetMaxAmmoInClip returned
-- nothing for these custom weapon hashes -- that's why it was showing
-- "1", its safety fallback). It's learned empirically instead: the
-- highest value ever observed for the current weapon is the real max.
local TrackedWeapon = nil
local DisplayClip = 0
local DisplayMaxClip = 1

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- This HUD belongs to Redzone/Turf Wars only (same flag every
        -- other piece of this resource's UI already respects). Wars has
        -- its own purpose-built overlay and must never see this ammo/
        -- weapon-name display -- this check was missing entirely, which
        -- is exactly what was bleeding this UI into Wars (and Hub).
        if not ShowHUD then
            if AmmoHudVisible then
                AmmoHudVisible = false
                SendNUI('hideAmmoHud', {})
            end
            TrackedWeapon = nil
            goto continue
        end

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local weapon = GetSelectedPedWeapon(ped)
            local group = GetWeapontypeGroup(weapon)

            -- "Gun out" = anything that isn't fists or a melee weapon
            if weapon == 0 or weapon == WEAPON_UNARMED or group == GROUP_MELEE then
                if AmmoHudVisible then
                    AmmoHudVisible = false
                    SendNUI('hideAmmoHud', {})
                end
                TrackedWeapon = nil
            else
                local changed = false
                local _, nativeAmmo = GetAmmoInClip(ped, weapon)
                nativeAmmo = nativeAmmo or 0

                if weapon ~= TrackedWeapon then
                    -- Just pulled this weapon out (or switched to it) --
                    -- start fresh from whatever it's actually carrying.
                    TrackedWeapon = weapon
                    DisplayMaxClip = math.max(nativeAmmo, 1)
                    DisplayClip = nativeAmmo
                    changed = true
                else
                    if nativeAmmo > DisplayMaxClip then
                        -- Seen a higher true cap than learned so far --
                        -- raise the ceiling (it never lowers mid-session).
                        DisplayMaxClip = nativeAmmo
                    end
                    if nativeAmmo ~= DisplayClip then
                        DisplayClip = nativeAmmo
                        changed = true
                    end
                end

                if not AmmoHudVisible then
                    AmmoHudVisible = true
                    changed = true
                end

                if changed then
                    SendNUI('updateAmmoHud', {
                        weaponName = WeaponDisplayNames[weapon] or "Weapon",
                        ammo = DisplayClip,
                        maxAmmo = DisplayMaxClip
                    })
                end
            end
        end

        ::continue::
    end
end)

-- ============================================================
-- SCOREBOARD TOGGLE (Z KEY)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        if ShowHUD and not InWars then
            if IsControlPressed(0, 20) then
                if not ScoreboardOpen then
                    ScoreboardOpen = true
                    TriggerServerEvent('pvp-hud:requestScoreboard')
                    SendNUI('showScoreboard', {})
                end
            else
                if ScoreboardOpen then
                    ScoreboardOpen = false
                    SendNUI('hideScoreboard', {})
                end
            end
        end
    end
end)

-- ============================================================
-- SCOREBOARD LIVE REFRESH
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if ShowHUD and ScoreboardOpen then
            TriggerServerEvent('pvp-hud:requestScoreboard')
        end
    end
end)

-- Receive scoreboard data from server
RegisterNetEvent('pvp-hud:updateScoreboard')
AddEventHandler('pvp-hud:updateScoreboard', function(players)
    SendNUI('updateScoreboard', { players = players })
end)

-- ============================================================
-- KILL / DEATH TRACKING (PvP modes only)
-- ============================================================

local RecentKillVictims = {}

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end

    local victim   = data[1]
    local attacker = data[2]
    local ped      = PlayerPedId()

    -- Kill tracking (we dealt the fatal blow) -- only in PvP modes
    if attacker == ped and victim ~= ped then
        if not RecentKillVictims[victim] then
            local isFatal = false
            if data[5] == 1 then
                isFatal = true
            elseif DoesEntityExist(victim) then
                isFatal = IsEntityDead(victim) or (GetEntityHealth(victim) <= 0)
            else
                isFatal = true
            end

            if isFatal then
                RecentKillVictims[victim] = true
                Citizen.SetTimeout(5000, function()
                    RecentKillVictims[victim] = nil
                end)
                if ShowHUD then
                    local isNpc = not (DoesEntityExist(victim) and IsPedAPlayer(victim))
                    TriggerServerEvent('pvp-hud:reportKill', isNpc)
                end
            end
        end
    end

    -- Death tracking (we died) -- only in PvP modes
    if victim == ped then
        local isFatal = false
        if data[5] == 1 then
            isFatal = true
        elseif DoesEntityExist(victim) then
            isFatal = IsEntityDead(victim) or (GetEntityHealth(victim) <= 0)
        end

        if isFatal then
            if ShowHUD then
                TriggerServerEvent('pvp-hud:reportDeath')
            end
        end
    end
end)

-- ============================================================
-- HIDE DEFAULT GTA HUD COMPONENTS (when ShowHUD)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if ShowHUD then
            HideHudComponentThisFrame(2)
            HideHudComponentThisFrame(20)
            HideHudComponentThisFrame(6)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(8)
            HideHudComponentThisFrame(9)
        end
    end
end)
