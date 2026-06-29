-- ============================================================
-- PVP-DEBUG — FREECAM + MARKER PLACEMENT TOOL
-- ------------------------------------------------------------
--   F7          toggle freecam ON  /  exit freecam + open
--               the results menu
--   W A S D     fly
--   SPACE       up
--   LEFT CTRL   down
--   LEFT SHIFT  hold to fly faster
--   Mouse       look
--   E           drop a marker at the glowing indicator
--   BACKSPACE   undo the last marker
--
-- The results menu (after exiting freecam) lists every marker
-- and has Done / Clear All / Resume Freecam buttons. Done prints
-- every saved position to your F8 console as a ready-to-paste
-- Lua table, and drops a short chat confirmation too.
-- ============================================================

local active   = false   -- currently flying
local menuOpen = false   -- results menu open (NUI focused)
local freecam  = nil
local markers  = {}      -- { {x=,y=,z=,heading=}, ... }

local camHeading = 0.0
local camPitch   = 0.0

local MOVE_SPEED  = 1.2
local LOOK_SENS   = 8.0
local PLACE_DIST  = 60.0   -- how far the aim-ray probes if nothing is hit

-- ============================================================
-- KEY BINDS (shows up in FiveM's own keybind settings too)
-- ============================================================
RegisterKeyMapping('pvpdebug_toggle', 'PvP Debug: Toggle Freecam Tool', 'keyboard', 'F7')
RegisterKeyMapping('pvpdebug_place',  'PvP Debug: Place Marker',        'keyboard', 'E')
RegisterKeyMapping('pvpdebug_undo',  'PvP Debug: Undo Last Marker',    'keyboard', 'BACK')

RegisterCommand('pvpdebug_toggle', function()
    if menuOpen then return end
    if active then
        StopFreecam(true)
    else
        StartFreecam()
    end
end, false)

RegisterCommand('pvpdebug_place', function()
    if active then PlaceMarker() end
end, false)

RegisterCommand('pvpdebug_undo', function()
    if active then UndoLastMarker() end
end, false)

-- ============================================================
-- HELPERS
-- ============================================================
local function RotationToDirection(rot)
    local rx = math.rad(rot.x)
    local rz = math.rad(rot.z)
    return vector3(
        -math.sin(rz) * math.abs(math.cos(rx)),
         math.cos(rz) * math.abs(math.cos(rx)),
         math.sin(rx)
    )
end

-- Where the camera is currently aiming — used both for the
-- glowing placement indicator and for the actual saved marker.
local function RaycastFromCam(dist)
    local camPos = GetCamCoord(freecam)
    local dir     = RotationToDirection(vector3(camPitch, 0.0, camHeading))
    local dest    = camPos + (dir * dist)

    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(rayHandle)

    if hit == 1 then
        return endCoords
    end
    return dest
end

local function DisableControlsThisFrame()
    DisableControlAction(0, 1, true)    -- default look
    DisableControlAction(0, 2, true)
    DisableControlAction(0, 24, true)   -- attack
    DisableControlAction(0, 25, true)   -- aim
    DisableControlAction(0, 37, true)   -- weapon wheel
    DisableControlAction(0, 200, true)  -- frontend pause (so ESC doesn't yank you to the pause menu mid-flight)
end

-- ============================================================
-- FREECAM START / STOP
-- ============================================================
function StartFreecam()
    active = true

    local ped   = PlayerPedId()
    local start = GetEntityCoords(ped)
    local rot   = GetGameplayCamRot(2)
    camHeading  = rot.z
    camPitch    = rot.x

    freecam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(freecam, start.x, start.y, start.z + 1.6)
    SetCamRot(freecam, camPitch, 0.0, camHeading, 2)
    SetCamFov(freecam, 60.0)
    RenderScriptCams(true, true, 400, true, true)

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)

    SendNUIMessage({ type = 'showHud', count = #markers })

    Citizen.CreateThread(FreecamLoop)
end

function StopFreecam(openMenuAfter)
    active = false

    local ped = PlayerPedId()
    RenderScriptCams(false, true, 400, true, true)
    if freecam then
        DestroyCam(freecam, false)
        freecam = nil
    end

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)

    SendNUIMessage({ type = 'hideHud' })

    if openMenuAfter then
        OpenResultsMenu()
    end
end

-- ============================================================
-- MAIN LOOP — movement, look, placement indicator
-- ============================================================
function FreecamLoop()
    while active do
        Citizen.Wait(0)
        DisableControlsThisFrame()

        local speed = MOVE_SPEED
        if IsControlPressed(0, 21) then speed = speed * 4.0 end -- LSHIFT = fast

        -- mouse look
        local lookX = GetDisabledControlNormal(0, 1)
        local lookY = GetDisabledControlNormal(0, 2)
        camHeading  = camHeading - (lookX * LOOK_SENS)
        camPitch    = math.max(-89.0, math.min(89.0, camPitch - (lookY * LOOK_SENS)))

        -- movement basis (flat heading, so W/S/A/D fly relative to where you're looking)
        local forward = RotationToDirection(vector3(0.0, 0.0, camHeading))
        local right   = vector3(forward.y, -forward.x, 0.0)

        local pos = GetCamCoord(freecam)

        if IsControlPressed(0, 32) then pos = pos + (forward * speed * 0.16) end -- W
        if IsControlPressed(0, 33) then pos = pos - (forward * speed * 0.16) end -- S
        if IsControlPressed(0, 34) then pos = pos - (right   * speed * 0.16) end -- A
        if IsControlPressed(0, 35) then pos = pos + (right   * speed * 0.16) end -- D
        if IsControlPressed(0, 22) then pos = pos + vector3(0.0, 0.0,  speed * 0.16) end -- SPACE up
        if IsControlPressed(0, 36) then pos = pos + vector3(0.0, 0.0, -speed * 0.16) end -- LCTRL down

        SetCamCoord(freecam, pos.x, pos.y, pos.z)
        SetCamRot(freecam, camPitch, 0.0, camHeading, 2)

        -- ---- PLACEMENT INDICATOR ----
        -- glowing purple ring + vertical beam at whatever the camera
        -- is currently aimed at — this is the "about to place here"
        -- preview, it follows your aim every frame.
        local aim = RaycastFromCam(PLACE_DIST)
        local pulse = (math.sin(GetGameTimer() * 0.006) + 1.0) * 0.5
        local ringSize = 0.35 + pulse * 0.12

        DrawMarker(1, aim.x, aim.y, aim.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            ringSize, ringSize, 0.45, 160, 60, 255, 160, false, true, 2, false, nil, nil, false)

        DrawMarker(28, aim.x, aim.y, aim.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.4, 0.4, 0.4, 200, 140, 255, 220, false, true, 2, false, nil, nil, false)
    end
end

-- ============================================================
-- MARKER SAVE / UNDO
-- ============================================================
function PlaceMarker()
    local coords  = RaycastFromCam(PLACE_DIST)
    local heading = camHeading % 360.0

    table.insert(markers, { x = coords.x, y = coords.y, z = coords.z, heading = heading })

    SendNUIMessage({ type = 'markerCount', count = #markers })

    TriggerEvent('chat:addMessage', {
        color = { 160, 60, 255 },
        args  = { '[DEBUG]', ('Marker #%d placed at %.2f, %.2f, %.2f'):format(#markers, coords.x, coords.y, coords.z) }
    })
end

function UndoLastMarker()
    if #markers == 0 then return end
    table.remove(markers)

    SendNUIMessage({ type = 'markerCount', count = #markers })

    TriggerEvent('chat:addMessage', {
        color = { 255, 107, 107 },
        args  = { '[DEBUG]', 'Removed last marker.' }
    })
end

-- ============================================================
-- RESULTS MENU (focused NUI — Done / Clear / Resume)
-- ============================================================
function OpenResultsMenu()
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'openResults', markers = markers })
end

function CloseResultsMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeResults' })
end

function PrintMarkers()
    print('^5[PVP-DEBUG]^7 ----- Saved Spawn Points (' .. #markers .. ') -----')
    print('local SpawnPoints = {')
    for i, m in ipairs(markers) do
        print(('    { x = %.2f, y = %.2f, z = %.2f, h = %.2f }, -- #%d'):format(m.x, m.y, m.z, m.heading, i))
    end
    print('}')
    print('^5[PVP-DEBUG]^7 ----------------------------------------------')

    TriggerEvent('chat:addMessage', {
        color = { 160, 60, 255 },
        args  = { '[DEBUG]', ('Printed %d spawn points to your F8 console.'):format(#markers) }
    })
end

RegisterNUICallback('debugDone', function(_, cb)
    PrintMarkers()
    CloseResultsMenu()
    cb('ok')
end)

RegisterNUICallback('debugClear', function(_, cb)
    markers = {}
    SendNUIMessage({ type = 'openResults', markers = markers })
    cb('ok')
end)

RegisterNUICallback('debugResume', function(_, cb)
    CloseResultsMenu()
    StartFreecam()
    cb('ok')
end)

RegisterNUICallback('debugClose', function(_, cb)
    CloseResultsMenu()
    cb('ok')
end)

-- ============================================================
-- CLEANUP
-- ============================================================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if active then StopFreecam(false) end
    if menuOpen then SetNuiFocus(false, false) end
end)
