-- ============================================================
-- PVP WEAPONS SERVER
-- Global synchronized rotation with "no repeat until all used"
-- Expandable: add per-mode decks later
-- ============================================================

local ROTATION_INTERVAL = 60 -- seconds (1 minute)

local GunDeck       = {}
local DeckIndex     = 0
local CurrentWeaponIndex = 1
local NextRotationTime   = 0
local LastUsedIndex      = nil

math.randomseed(os.time())

-- Fisher-Yates shuffle
local function ShuffleDeck()
    GunDeck = {}
    for i = 1, #GunRotationList do
        GunDeck[i] = i
    end

    for i = #GunDeck, 2, -1 do
        local j = math.random(1, i)
        GunDeck[i], GunDeck[j] = GunDeck[j], GunDeck[i]
    end

    -- Prevent the first card of the new deck being the same as the last one played
    if LastUsedIndex and GunDeck[1] == LastUsedIndex and #GunDeck > 1 then
        local swapPos = math.random(2, #GunDeck)
        GunDeck[1], GunDeck[swapPos] = GunDeck[swapPos], GunDeck[1]
    end

    DeckIndex = 1
end

local function DrawNextWeapon()
    if not GunDeck or #GunDeck == 0 or DeckIndex > #GunDeck then
        ShuffleDeck()
    end

    CurrentWeaponIndex = GunDeck[DeckIndex]
    LastUsedIndex      = CurrentWeaponIndex
    DeckIndex          = DeckIndex + 1

    local gun = GunRotationList[CurrentWeaponIndex]
    NextRotationTime = os.time() + ROTATION_INTERVAL

    TriggerClientEvent("pvp-weapons:syncRotation", -1, gun.hash, gun.name, ROTATION_INTERVAL)
end

CreateThread(function()
    Wait(3000)
    ShuffleDeck()
    DrawNextWeapon()
end)

CreateThread(function()
    while true do
        Wait(200)
        if os.time() >= NextRotationTime then
            DrawNextWeapon()
        end
    end
end)

AddEventHandler("playerJoining", function()
    local src = source
    if NextRotationTime > 0 then
        local gun = GunRotationList[CurrentWeaponIndex]
        local remaining = math.max(0, NextRotationTime - os.time())
        TriggerClientEvent("pvp-weapons:syncRotation", src, gun.hash, gun.name, remaining)
    end
end)