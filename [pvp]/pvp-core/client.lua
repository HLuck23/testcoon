-- ============================================================
-- PVP CORE SYSTEMS
-- Core functionality for the combat server:
--   - Disable Weapon Wheel (TAB blocked)
--   - Infinite Stamina
--   - Player State Manager (HUB / REDZONE / etc.)
--   - Global Friendly Fire (PvP Enabled)
--   - Kill Feed (Player + NPC) — Arena only
--
-- State values: "hub", "redzone"
-- Export: GetPlayerGameState() / SetPlayerGameState(state)
-- ============================================================

local PlayerState = "hub"  -- default spawn in hub
local SessionKills = 0
local SessionDeaths = 0

-- True while ANY enter/leave/respawn teleport sequence (hub, redzone,
-- turf) is actively in progress for this client. Other resources'
-- watchdog/boundary/fall-through threads should check this and skip
-- their own corrective teleports while it's true, so they never fight
-- an in-progress teleport that just hasn't finished placing the player
-- yet. This is the fix for the "stuck in hub but game state says
-- turfwars" race.
local IsTransitioning = false

-- ============================================================
-- EXPORTS  — THESE MUST EXIST FOR OTHER RESOURCES TO WORK
-- ============================================================

function GetPlayerGameState()
    return PlayerState
end

function SetPlayerGameState(state)
    PlayerState = state
    TriggerEvent("pvp-core:stateChanged", state)
end

function IsPlayerTransitioning()
    return IsTransitioning
end

function SetPlayerTransitioning(value)
    IsTransitioning = value
end

exports("GetPlayerGameState", GetPlayerGameState)
exports("SetPlayerGameState", SetPlayerGameState)
exports("IsPlayerTransitioning", IsPlayerTransitioning)
exports("SetPlayerTransitioning", SetPlayerTransitioning)

-- ============================================================
-- DISABLE WEAPON WHEEL
-- Completely blocks the weapon wheel from opening.
-- Uses DisableControlAction AND closes the wheel if it opens.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- Disable TAB (SELECT_WEAPON / INPUT_SELECT_WEAPON)
        DisableControlAction(0, 37, true)   -- TAB - Weapon wheel
        DisableControlAction(0, 16, true)   -- Scroll wheel down
        DisableControlAction(0, 17, true)   -- Scroll wheel up
        DisableControlAction(0, 99, true)   -- Scroll up (weapon wheel)
        DisableControlAction(0, 100, true)  -- Scroll down (weapon wheel)
        DisableControlAction(0, 115, true)  -- Mouse wheel up
        DisableControlAction(0, 116, true)  -- Mouse wheel down
        DisableControlAction(0, 261, true)  -- Scroll wheel up
        DisableControlAction(0, 262, true)  -- Scroll wheel down

        -- If weapon wheel somehow opens, force it closed
        if IsHudComponentActive(19) then     -- HUD_WEAPON_WHEEL
            HideHudComponentThisFrame(19)
        end
        if IsHudComponentActive(2) then      -- HUD_WEAPON_WHEEL_STATS
            HideHudComponentThisFrame(2)
        end
    end
end)

-- Also hide weapon components from HUD
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        -- Hide weapon icon, ammo, crosshair name
        HideHudComponentThisFrame(2)   -- HUD_WEAPON_ICON
        HideHudComponentThisFrame(20)  -- HUD_WEAPON_STATS
    end
end)

-- ============================================================
-- INFINITE STAMINA
-- Resets stamina to max every frame so players never slow down.
-- Also disables the stamina bar from showing exhaustion.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            -- Reset stamina to maximum (never get tired)
            ResetPlayerStamina(PlayerId())

            -- Allow sprinting and jumping without drain
            StatSetInt(GetHashKey("MP0_STAMINA"), 100, true)
            StatSetInt(GetHashKey("MP1_STAMINA"), 100, true)
            StatSetInt(GetHashKey("MP2_STAMINA"), 100, true)
        end
    end
end)

-- ============================================================
-- GLOBAL FRIENDLY FIRE (PvP ENABLED)
-- Enables damage between all players globally.
-- ============================================================

RegisterNetEvent("pvp-core:enableFriendlyFire")
AddEventHandler("pvp-core:enableFriendlyFire", function()
    local ped = PlayerPedId()
    SetCanAttackFriendly(ped, true, false)
    NetworkSetFriendlyFireOption(true)
end)

-- Backup loop to ensure PvP stays active after respawns / session changes
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            -- Allow attacking "friendly" peds (other players)
            SetCanAttackFriendly(ped, true, false)

            -- Enable the global friendly-fire network flag
            NetworkSetFriendlyFireOption(true)
        end
    end
end)

-- ============================================================
-- HEADSHOT INSTANT KILL (EATING BUG FIX)
-- Forces immediate death on headshot to prevent desync survival.
-- DEFERRED by 1 frame to avoid event pool overflow.
-- Bone 31086 = SKEL_Head
-- ============================================================

local HeadshotFixActive = false

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if HeadshotFixActive then return end

    local victim = data[1]
    local attacker = data[2]

    -- Only process our own player ped
    if victim ~= PlayerPedId() then return end

    -- Must be a ped
    if not IsEntityAPed(victim) then return end

    -- Only apply to PvP damage (attacker is another player)
    if not IsEntityAPed(attacker) or not IsPedAPlayer(attacker) then return end

    -- Check last damaged bone
    local hasBone, bone = GetPedLastDamageBone(victim)
    if hasBone and bone == 31086 then
        HeadshotFixActive = true

        -- Defer to next frame so we don't blow up the event pool
        Citizen.CreateThread(function()
            Citizen.Wait(0)

            if DoesEntityExist(victim) and not IsEntityDead(victim) then
                local health = GetEntityHealth(victim)
                local armour = GetPedArmour(victim)
                -- Overwhelming damage to guarantee kill attribution
                ApplyDamageToPed(victim, health + armour + 200, false)
            end

            -- Cooldown so we never double-fire
            Citizen.Wait(500)
            HeadshotFixActive = false
        end)
    end
end)

-- ============================================================
-- STATE CHANGE HANDLER
-- Broadcasts state to other resources via NUI + session stats.
-- ============================================================

AddEventHandler("pvp-core:stateChanged", function(newState)
    SendNUIMessage({
        type = "setGameState",
        state = newState
    })
    SendSessionStats()
end)

-- ============================================================
-- SUICIDE COMMAND (/death)
-- ============================================================

RegisterCommand("death", function(source, args, rawCommand)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not IsEntityDead(ped) then
        SetEntityHealth(ped, 0)
    end
end, false)

-- ============================================================
-- HIT MARKERS (APEX STYLE FLOATING DAMAGE)
-- Toggle with /hitmark
-- Shows floating damage numbers when you hit ANY ped (players + NPCs).
-- Red = body shot | Gold = headshot
-- ============================================================

local HitMarkersEnabled = false
local ActiveHitMarkers = {}
local PedHealthCache = {}

-- Toggle command
RegisterCommand("hitmark", function()
    HitMarkersEnabled = not HitMarkersEnabled
end, false)

-- Cache health for ALL peds (players + NPCs) so we can calculate damage
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50)
        if HitMarkersEnabled then
            local peds = GetGamePool('CPed')
            for _, ped in ipairs(peds) do
                if DoesEntityExist(ped) and ped ~= PlayerPedId() then
                    PedHealthCache[ped] = GetEntityHealth(ped)
                end
            end
        end
    end
end)

-- Detect damage dealt and spawn markers
AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if not HitMarkersEnabled then return end

    local victim = data[1]
    local attacker = data[2]

    -- Only show for our own damage
    if attacker ~= PlayerPedId() then return end
    if not IsEntityAPed(victim) then return end
    if victim == PlayerPedId() then return end -- ignore self-damage

    -- Calculate damage dealt
    local currentHealth = GetEntityHealth(victim)
    local previousHealth = PedHealthCache[victim] or currentHealth
    local damage = previousHealth - currentHealth
    if damage < 0 then damage = 0 end

    -- Get hit position (head bone for display anchor)
    local boneIndex = GetPedBoneIndex(victim, 31086) -- SKEL_Head
    local displayPos = GetWorldPositionOfEntityBone(victim, boneIndex)
    if not displayPos or #(displayPos - GetEntityCoords(victim)) > 2.0 then
        displayPos = GetEntityCoords(victim) + vector3(0.0, 0.0, 0.5)
    end

    -- Check if headshot
    local hasBone, bone = GetPedLastDamageBone(victim)
    local isHeadshot = (hasBone and bone == 31086)

    -- Add to active markers
    table.insert(ActiveHitMarkers, {
        pos = displayPos,
        damage = damage,
        isHeadshot = isHeadshot,
        time = GetGameTimer(),
        life = 1200, -- ms
        drift = vector3(
            (math.random() - 0.5) * 0.25,
            (math.random() - 0.5) * 0.25,
            0.0
        )
    })
end)

-- Render floating damage numbers
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if HitMarkersEnabled then
            local now = GetGameTimer()
            local camCoords = GetGameplayCamCoords()

            for i = #ActiveHitMarkers, 1, -1 do
                local marker = ActiveHitMarkers[i]
                local elapsed = now - marker.time
                local progress = elapsed / marker.life

                if progress >= 1.0 then
                    table.remove(ActiveHitMarkers, i)
                else
                    -- Float upward and drift slightly
                    local zOffset = 0.3 + (progress * 0.8)
                    local displayPos = marker.pos + vector3(0.0, 0.0, zOffset) + (marker.drift * progress)

                    -- Fade out
                    local alpha = math.floor(255 * (1.0 - progress))

                    -- Apex colors: red body, gold headshot
                    local r, g, b = 255, 60, 60
                    if marker.isHeadshot then
                        r, g, b = 255, 215, 0
                    end

                    -- Scale based on distance (closer = bigger)
                    local dist = #(camCoords - displayPos)
                    local scale = math.max(0.25, 0.55 - (dist * 0.008))

                    -- Draw 3D text
                    DrawApexDamageText(
                        tostring(math.floor(marker.damage)),
                        displayPos.x, displayPos.y, displayPos.z,
                        scale, r, g, b, alpha
                    )
                end
            end
        end
    end
end)

function DrawApexDamageText(text, x, y, z, scale, r, g, b, a)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(scale, scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(r, g, b, a)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 255)
        SetTextDropShadow()
        SetTextOutline()
        SetTextCentre(1)
        SetTextEntry("STRING")
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

-- ============================================================
-- KILL FEED SYSTEM
-- Tracks fatal damage dealt by local player to players & NPCs.
-- Only active when PlayerState ~= "hub".
-- FIX: Removed 50ms wait. NPCs despawned instantly never registered.
-- FIX (real bug found): this used to also exclude PlayerState == "wars",
-- so wars kills never reached pvp-core:sendKillFeed at all -- meaning
-- they never reached pvp-playerlog's global kill counter/webhook, the
-- bottom-left session HUD's kill count, or the kill feed broadcast
-- that lives downstream of pvp-core:internalKillRecorded. The DEATH
-- tracking block right below this one was never given the same "wars"
-- exclusion (it only ever excluded "hub") -- that asymmetry is exactly
-- why deaths kept showing up correctly while kills silently didn't.
-- pvp-wars's own internal economy/leaderboard system is untouched by
-- this and still pays/tracks wars kills independently; pvp-economy
-- (the turf/global money pot) already has its own separate fix to
-- ignore wars kills specifically, so re-enabling this doesn't bring
-- back the double-money bug.
-- ============================================================

local RecentKillVictims = {}

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if PlayerState == "hub" then return end

    local victim   = data[1]
    local attacker = data[2]
    local ped      = PlayerPedId()

    if attacker ~= ped then return end
    if victim == ped then return end
    if RecentKillVictims[victim] then return end

    -- Determine fatal immediately (before entity is deleted by other scripts)
    local isFatal = false
    if data[5] == 1 then
        isFatal = true
    elseif DoesEntityExist(victim) then
        isFatal = IsEntityDead(victim) or (GetEntityHealth(victim) <= 0)
    else
        -- Entity was deleted instantly — assume it was a kill since event fired
        isFatal = true
    end

    if not isFatal then return end

    -- Cache immediately so we don't double-fire
    RecentKillVictims[victim] = true
    Citizen.SetTimeout(5000, function()
        RecentKillVictims[victim] = nil
    end)

    -- Gather info while entity still exists (if possible)
    local victimName = "NPC"
    if DoesEntityExist(victim) and IsPedAPlayer(victim) then
        local playerId = NetworkGetPlayerIndexFromPed(victim)
        if playerId and playerId >= 0 then
            victimName = GetPlayerName(playerId)
        end
    end

    local isHeadshot = false
    if DoesEntityExist(victim) then
        local hasBone, bone = GetPedLastDamageBone(victim)
        isHeadshot = (hasBone and bone == 31086)
    end

    local weaponHash = GetSelectedPedWeapon(ped)
    local group = GetWeapontypeGroup(weaponHash)
    local category = "misc"

    if group == GetHashKey("GROUP_PISTOL") then
        category = "pistols"
    elseif group == GetHashKey("GROUP_SMG") then
        category = "smg"
    elseif group == GetHashKey("GROUP_RIFLE") or group == GetHashKey("GROUP_SNIPER") or group == GetHashKey("GROUP_MG") then
        category = "rifles"
    elseif group == GetHashKey("GROUP_SHOTGUN") then
        category = "misc"
    end

    -- Send killfeed entry to the server for broadcast
    TriggerServerEvent('pvp-core:sendKillFeed', victimName, category, isHeadshot)
end)

-- ============================================================
-- DEATH TRACKING (mirrors the kill block above)
-- pvp-core previously only ever reported KILLS to the server --
-- there was no equivalent death report at all, which is why
-- globalDeaths had only one (separately-gated, pvp-hud/ShowHUD)
-- path feeding it. This uses the SAME PlayerState gate that's
-- already proven reliable via the kill-feed webhook.
-- ============================================================

local RecentSelfDeathReported = false

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if PlayerState == "hub" then return end

    local victim = data[1]
    local ped    = PlayerPedId()

    if victim ~= ped then return end
    if RecentSelfDeathReported then return end

    local isFatal = false
    if data[5] == 1 then
        isFatal = true
    elseif DoesEntityExist(victim) then
        isFatal = IsEntityDead(victim) or (GetEntityHealth(victim) <= 0)
    end

    if not isFatal then return end

    -- Debounce: a single death can generate several damage events in the
    -- same instant (multiple bullets/pellets) -- only report the first.
    RecentSelfDeathReported = true
    Citizen.SetTimeout(2000, function()
        RecentSelfDeathReported = false
    end)

    TriggerServerEvent('pvp-core:sendDeathReport')
end)

-- ============================================================
-- RECEIVE KILL FEED BROADCAST
-- ============================================================

RegisterNetEvent('pvp-core:addKillFeed')
AddEventHandler('pvp-core:addKillFeed', function(killerName, victimName, weaponCategory, isHeadshot)
    SendNUIMessage({
        type = "addKillFeed",
        killer = killerName,
        victim = victimName,
        category = weaponCategory,
        headshot = isHeadshot
    })

    -- Count our own kills for session stats
    local myName = GetPlayerName(PlayerId())
    if killerName == myName then
        SessionKills = SessionKills + 1
        SendSessionStats()
    end
end)

-- ============================================================
-- BLOCK MELEE WITH WEAPONS (Disable Pistol Slap / Rifle Butt)
-- Prevents the forced melee animation when holding firearms.
-- ONLY blocks melee keys (R, Q) — shooting and aiming still work.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local weapon = GetSelectedPedWeapon(ped)

            -- Only block if player is holding a weapon (not unarmed)
            if weapon ~= GetHashKey("WEAPON_UNARMED") then
                -- Block ONLY melee attack inputs — DO NOT block INPUT_ATTACK (24) or INPUT_AIM (25)
                DisableControlAction(0, 140, true)  -- INPUT_MELEE_ATTACK_LIGHT (R key melee)
                DisableControlAction(0, 141, true)  -- INPUT_MELEE_ATTACK_HEAVY (Q key melee)
                DisableControlAction(0, 142, true)  -- INPUT_MELEE_ATTACK_ALTERNATE (mouse melee)
                DisableControlAction(0, 263, true)  -- INPUT_MELEE_ATTACK1 (R)
                DisableControlAction(0, 264, true)  -- INPUT_MELEE_ATTACK2 (Q)
            end
        end
    end
end)

-- ============================================================
-- PERMANENT DAYTIME (Global Time Lock)
-- Forces the game clock to stay at 12:00 midday permanently.
-- Also locks weather to EXTRASUNNY for clear visibility.
-- ============================================================

Citizen.CreateThread(function()
    -- Initial setup
    NetworkOverrideClockTime(12, 0, 0)
    SetWeatherTypeNow("EXTRASUNNY")
    SetWeatherTypePersist("EXTRASUNNY")
    SetWeatherTypeNowPersist("EXTRASUNNY")
    SetOverrideWeather("EXTRASUNNY")

    while true do
        Citizen.Wait(1000)

        -- Lock time to 12:00:00 permanently
        NetworkOverrideClockTime(12, 0, 0)

        -- Ensure weather stays sunny (no rain, fog, or night darkness)
        ClearWeatherTypePersist()
        SetWeatherTypeNow("EXTRASUNNY")
        SetWeatherTypePersist("EXTRASUNNY")
        SetWeatherTypeNowPersist("EXTRASUNNY")
        SetOverrideWeather("EXTRASUNNY")

        -- Disable random weather changes
        SetRandomWeatherType()
    end
end)

-- ============================================================
-- HIDE MINIMAP
-- Completely disables the minimap/radar from displaying.
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        DisplayRadar(false)
    end
end)

-- ============================================================
-- INITIALIZATION
-- Start player in hub state.
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end

    -- Enable PvP immediately on resource start
    local ped = PlayerPedId()
    SetCanAttackFriendly(ped, true, false)
    NetworkSetFriendlyFireOption(true)

    -- Ensure minimap is disabled on start
    DisplayRadar(false)

    -- Sync initial state to NUI (hub = kill feed hidden)
    SendNUIMessage({
        type = "setGameState",
        state = PlayerState
    })

    SendSessionStats()
end)


-- ============================================================
-- SESSION STATS TRACKER
-- Counts local player kills & deaths, and polls player count.
-- ============================================================

-- Death tracker
Citizen.CreateThread(function()
    local wasDead = false
    while true do
        Citizen.Wait(500)
        local ped = PlayerPedId()
        local isDead = IsEntityDead(ped) or (GetEntityHealth(ped) <= 0)
        if isDead and not wasDead then
            SessionDeaths = SessionDeaths + 1
            SendSessionStats()
        end
        wasDead = isDead
    end
end)

-- Send stats to NUI
function SendSessionStats()
    local playerCount = #GetActivePlayers()
    SendNUIMessage({
        type = "updateSessionStats",
        playerCount = playerCount,
        kills = SessionKills,
        deaths = SessionDeaths
    })
end

-- Poll player count every 5 seconds (others may join/leave)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        SendSessionStats()
    end
end)