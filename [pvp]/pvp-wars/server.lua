-- ============================================================
-- PVP WARS  —  SERVER
-- 5v5 Team Deathmatch (admin-assigned teams, 2-player minimum per team)
-- Admin flow: player picks a map from the NPC (or runs /warAdmin)
--             →  admin gets a Discord ping + in-game NUI request
--             →  admin assigns players to Alpha / Bravo
--             →  admin starts the session → official match begins
--
-- ------------------------------------------------------------
-- FIXED THIS PASS
-- ------------------------------------------------------------
-- 1. Real parse error on load: `exports['pvp-shop']:GetWeaponPrice and ...`
--    — you cannot reference a colon-call as a value in Lua, the parser
--    expects `(args)` immediately after `:GetWeaponPrice` and hits the
--    `and` instead. Fixed the same way pvp-shop/pvp-economy already do
--    it elsewhere in this pack: pcall the whole call, fall back on `ok`.
-- 2. NEW "pick a map and wait" flow (SESSION.waiting below) — previously
--    there was no way for a player to actually go stand at a map before
--    an admin had already built the teams. Players can now request to
--    enter a map on their own, get teleported there immediately (armed
--    with just the starter sidearm, no team / no scoring yet), and the
--    admin-request ping now fires automatically the moment they do that
--    — `/warAdmin` still works too, this is in addition to it, not a
--    replacement.
-- 3. NEW `/warsAdminPanel` command so an admin can open the panel proactively
--    instead of only ever reacting to a player's request.
-- ============================================================

-- ============================================================
-- CONFIG
-- ============================================================

local CONFIG = {
    maxPerTeam      = 5,
    minPerTeam      = 1,   -- 1v1 minimum (2 total)
    killReward      = 500,
    headshotBonus   = 200,
    startingMoney   = 10000,

    -- Syringe item (inventory only, no buy)
    syringeItem     = "wars_syringe",
    syringeHeal     = 40,   -- health points restored
    syringeArmorHeal= 25,   -- armor points restored
    syringeStartQty = 3,    -- each player gets 3 at session start
    waitingSyringeQty = 1,  -- players get 1 to play with while just waiting
    syringePrice    = 350,  -- cost to buy ONE extra syringe from the Items shop tab
    syringeMaxOwned = 6,    -- hard cap so people can't stockpile infinitely

    -- Admin Discord webhook. Set in server.cfg:
    --   set wars_webhook "https://discord.com/api/webhooks/..."
    webhookConvar   = 'wars_webhook',

    -- ACE permission that grants admin access to /warAdmin panel
    adminAce        = 'pvpadmin',
}

-- ============================================================
-- Maps (2 for now)
-- waitSpawn = a neutral spot roughly between the two team spawn
-- clusters, used while a player is just "waiting" for a session
-- (no team yet). Computed as the midpoint of each team's slot #1
-- so it's guaranteed to sit inside the played area.
-- ============================================================

local WARS_MAPS = {
    {
        name   = "Cabins",
        desc   = "Mirdo's Cabin Area — dense cover, close range",
        waitSpawn = vector4(2574.13, 5040.37, 46.50, 107.0),
        -- Spawn sets: {alpha = {}, bravo = {}} each with up to 5 positions
        spawns = {
            alpha = {
                vector4(2547.77,  5060.34,  45.75,  200.0),
                vector4(2543.21,  5055.10,  45.75,  195.0),
                vector4(2551.30,  5065.80,  45.75,  210.0),
                vector4(2539.00,  5070.12,  45.75,  185.0),
                vector4(2556.45,  5058.77,  45.75,  220.0),
            },
            bravo = {
                vector4(2600.50,  5020.40,  45.90,  15.0),
                vector4(2606.00,  5025.70,  45.90,  20.0),
                vector4(2595.30,  5015.00,  45.90,  10.0),
                vector4(2612.10,  5030.55,  45.90,  25.0),
                vector4(2590.80,  5010.25,  45.90,   5.0),
            },
        },
    },
    {
        name   = "Airport",
        desc   = "LSIA Runways — open sightlines, long range",
        waitSpawn = vector4(-1275.85, -3044.58, 14.50, 210.0),
        spawns = {
            alpha = {
                vector4(-1336.30, -3044.58, 13.95, 300.0),
                vector4(-1342.10, -3040.20, 13.95, 295.0),
                vector4(-1330.50, -3049.75, 13.95, 305.0),
                vector4(-1348.80, -3035.60, 13.95, 290.0),
                vector4(-1325.00, -3054.90, 13.95, 310.0),
            },
            bravo = {
                vector4(-1215.40, -3044.58, 13.95, 120.0),
                vector4(-1221.20, -3040.20, 13.95, 115.0),
                vector4(-1209.60, -3049.75, 13.95, 125.0),
                vector4(-1227.80, -3035.60, 13.95, 110.0),
                vector4(-1204.00, -3054.90, 13.95, 130.0),
            },
        },
    },
}

-- ============================================================
-- SHARED WEAPON LIST (same set as pvp-shop prices)
-- ============================================================

local LOADOUT_WEAPONS = {
    -- Pistols (nail gun moved here)
    "weapon_glock17s", "weapon_glock30", "weapon_glock34", "weapon_nbk",
    "weapon_revolver357", "weapon_glock18dt", "weapon_blackiceglock",
    "WEAPON_ICEDGLOCK", "weapon_iceglock", "weapon_nailgun",
    -- SMGs (junker / hotshotwelder / icedbongshot moved here from misc)
    "weapon_cx9", "w_sb_minismg", "weapon_dssmg", "weapon_asm1",
    "weapon_mp40type2", "weapon_r99", "weapon_p90", "weapon_tbsvector",
    "weapon_icevector", "weapon_blastxspectre", "weapon_candymp5",
    "weapon_crimsonsnowvector", "weapon_blackicemp7", "weapon_vesperhybrid",
    "WEAPON_ICEDP90", "weapon_spaceflightmp5",
    "weapon_junker", "weapon_hotshotwelder", "WEAPON_ICEDBONGSHOT",
    -- Rifles
    "weapon_minicarbine", "weapon_ibak", "weapon_acrcqb", "weapon_vss",
    "weapon_retrom4a4", "weapon_m4hyperbeast", "weapon_m4a1sgyspunkred",
    "WEAPON_ICEDMZA", "WEAPON_ICEDQP12", "WEAPON_ICEDFAL",
    "WEAPON_KURONAMIVANDAL", "WEAPON_ICEDR4C",
}

-- ============================================================
-- ECONOMY  —  SEPARATE from turf wars
-- KVP key: warsmoney:<dbId>
-- ============================================================

local KVP_MONEY  = 'warsmoney:%s'
local KVP_OWNED  = 'warsowned:%s'        -- owned loadout weapons
local KVP_INV    = 'warsinv:%s'           -- inventory items (syringe counts)
local MoneyCache = {}
local OwnedCache = {}
local InvCache   = {}

local function GetPlayerDbId(src)
    for _, resName in ipairs({'player-data', 'cfx-server-data.player-data'}) do
        local ok, dbId = pcall(function() return exports[resName].getPlayerId(src) end)
        if ok and dbId then return tonumber(dbId) end
    end
    local ok, dbId = pcall(function() return exports['cfx.re/playerData.v1alpha1'].getPlayerId(src) end)
    if ok and dbId then return tonumber(dbId) end
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if id:find('license:') == 1 then
            local hash = 0
            for i = 1, #id do
                hash = ((hash << 5) - hash) + id:byte(i)
                hash = hash & 0xFFFFFFFF
            end
            return hash
        end
    end
    return nil
end

-- Money
local function LoadMoney(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return CONFIG.startingMoney end
    local saved = GetResourceKvpString(KVP_MONEY:format(dbId))
    if saved then return tonumber(saved) or CONFIG.startingMoney end
    SetResourceKvp(KVP_MONEY:format(dbId), tostring(CONFIG.startingMoney))
    return CONFIG.startingMoney
end
local function SaveMoney(src, amount)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    SetResourceKvp(KVP_MONEY:format(dbId), tostring(amount))
end
local function GetMoney(src)
    if not MoneyCache[src] then MoneyCache[src] = LoadMoney(src) end
    return MoneyCache[src]
end
local function AwardMoney(src, amount, reason)
    MoneyCache[src] = math.max(0, GetMoney(src) + amount)
    SaveMoney(src, MoneyCache[src])
    TriggerClientEvent('pvp-wars:moneyUpdated', src, MoneyCache[src])
    -- NOTE: routine console print removed (was firing on every single
    -- purchase/kill-reward/syringe-use -- the requested spam). Purchases
    -- and kill rewards already get logged to Discord separately below;
    -- add a print back here only if you want failures specifically.
end

-- Owned weapons (wars-specific loadout shop)
local function LoadOwned(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return {} end
    local saved = GetResourceKvpString(KVP_OWNED:format(dbId))
    if saved then
        local ok, t = pcall(json.decode, saved)
        if ok and type(t) == 'table' then return t end
    end
    return {}
end
local function SaveOwned(src, owned)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    SetResourceKvp(KVP_OWNED:format(dbId), json.encode(owned))
end
local function GetOwned(src)
    if not OwnedCache[src] then OwnedCache[src] = LoadOwned(src) end
    return OwnedCache[src]
end

-- Inventory (syringe counts etc.)
local function LoadInv(src)
    local dbId = GetPlayerDbId(src)
    if not dbId then return {} end
    local saved = GetResourceKvpString(KVP_INV:format(dbId))
    if saved then
        local ok, t = pcall(json.decode, saved)
        if ok and type(t) == 'table' then return t end
    end
    return {}
end
local function SaveInv(src, inv)
    local dbId = GetPlayerDbId(src)
    if not dbId then return end
    SetResourceKvp(KVP_INV:format(dbId), json.encode(inv))
end
local function GetInv(src)
    if not InvCache[src] then InvCache[src] = LoadInv(src) end
    return InvCache[src]
end

-- ============================================================
-- WEBHOOK
-- ============================================================

local function DiscordWebhook(message)
    local url = GetConvar(CONFIG.webhookConvar, '')
    if url == '' then return end
    PerformHttpRequest(url, function(code)
        if code ~= 200 and code ~= 204 then
            print("[WARS] Webhook failed: " .. tostring(code))
        end
    end, 'POST', json.encode({ content = message }), { ['Content-Type'] = 'application/json' })
end

-- ============================================================
-- SESSION STATE
-- ============================================================

local SESSION = {
    active   = false,
    map      = nil,          -- index into WARS_MAPS
    teams    = {             -- [src] = "alpha" | "bravo"
        alpha = {},          -- { [src] = true }
        bravo = {},
    },
    players  = {},           -- [src] = "alpha" | "bravo"   (official, scored match)
    loadouts = {},           -- [src] = weaponHash  (chosen primary)
    pending  = {},           -- [src] = true  (admin-added but not yet started)
    waiting  = {},           -- [src] = mapIndex  (picked a map themselves, no team/score yet)
    kills    = {},           -- [src] = { player=n, npc=n }  session kill counts, reset each session
}

local function IsPlayerInWars(src)
    return SESSION.players[src] ~= nil
end

local function IsPlayerWaiting(src)
    return SESSION.waiting[src] ~= nil
end

local function GetTeamList(side)
    local list = {}
    for src, _ in pairs(SESSION.teams[side]) do
        if GetPlayerName(src) then
            table.insert(list, { id = src, name = GetPlayerName(src) })
        end
    end
    return list
end

local function CountTeam(side)
    local n = 0
    for src, _ in pairs(SESSION.teams[side]) do
        if GetPlayerName(src) then n = n + 1 end
    end
    return n
end

local function BroadcastToSession(event, ...)
    for src, _ in pairs(SESSION.players) do
        TriggerClientEvent(event, src, ...)
    end
end

-- FIX: kill feed and leaderboard updates were only ever sent to
-- SESSION.players (the official, admin-started, teams-assigned
-- session). A player who's just "waiting" on a picked map (in
-- SESSION.waiting instead) was invisible to BroadcastToSession, so
-- their own kill feed messages and session stats/leaderboard never
-- reached their own screen, even though SESSION.kills[src] was
-- incrementing correctly server-side the whole time. This variant
-- reaches both pools, for use specifically by kill feed / leaderboard
-- broadcasts so waiting players actually see their own activity.
local function BroadcastToSessionAndWaiting(event, ...)
    local sent = {}
    for src, _ in pairs(SESSION.players) do
        TriggerClientEvent(event, src, ...)
        sent[src] = true
    end
    for src, _ in pairs(SESSION.waiting) do
        if not sent[src] then
            TriggerClientEvent(event, src, ...)
        end
    end
end

local function NotifyPlayer(src, msg, color)
    color = color or {255, 200, 50}
    TriggerClientEvent('chat:addMessage', src, { color = color, args = {"[WARS]", msg} })
end

-- ============================================================
-- ADMIN HELPER
-- ============================================================

local function IsAdmin(src)
    return IsPlayerAceAllowed(src, CONFIG.adminAce)
end

-- Finds all online admins
local function GetOnlineAdmins()
    local admins = {}
    for _, pid in ipairs(GetPlayers()) do
        local pidNum = tonumber(pid)
        if IsAdmin(pidNum) then
            table.insert(admins, pidNum)
        end
    end
    return admins
end

-- ============================================================
-- ADMIN REQUEST  —  shared by /warAdmin AND by a player picking
-- a map from the NPC (see pvp-wars:requestJoinMap below). Pulled
-- out into its own function so both triggers ping the exact same
-- way instead of duplicating the notify/Discord logic.
-- ============================================================

local function RequestAdminHelp(src, reasonText)
    local name = GetPlayerName(src) or "Unknown"
    reasonText = reasonText or "is requesting a Wars session"

    local admins = GetOnlineAdmins()
    if #admins == 0 then
        NotifyPlayer(src, "No admins are currently online. Try again later or ask in Discord.", {255, 100, 50})
        return
    end

    for _, adminId in ipairs(admins) do
        TriggerClientEvent('pvp-wars:adminRequest', adminId, src, name, reasonText)
        NotifyPlayer(adminId, ("~y~%s~w~ %s. Open the Wars Admin panel."):format(name, reasonText), {255, 220, 50})
    end

    local adminNames = {}
    for _, adminId in ipairs(admins) do
        table.insert(adminNames, GetPlayerName(adminId) or "Admin")
    end
    DiscordWebhook(("🎯 **Wars Request** — **%s** (id:%d) %s.\n Admins online: %s"):format(
        name, src, reasonText, table.concat(adminNames, ", ")))

    NotifyPlayer(src, "Admins notified! A Wars admin will set up your session shortly.", {100, 220, 255})
end

-- ============================================================
-- /warAdmin  —  player manually requests admin intervention
-- ============================================================

RegisterCommand('warAdmin', function(source, args, rawCommand)
    RequestAdminHelp(source, "is requesting a Wars session")
end, false)

-- Net event for admin request button in UI
RegisterNetEvent('pvp-wars:adminRequest')
AddEventHandler('pvp-wars:adminRequest', function()
    RequestAdminHelp(source, "is requesting a Wars session")
end)

-- ============================================================
-- /warsAdminPanel  —  admin opens the panel themselves, without
-- needing to wait for a player request first.
-- ============================================================

RegisterCommand('warsAdminPanel', function(source, args, rawCommand)
    local src = source
    if not IsAdmin(src) then
        NotifyPlayer(src, "You don't have permission to use this command (missing 'pvpadmin' ACE).", {255, 80, 80})
        return
    end
    -- Reuse the exact same state builder as the 'requestState' admin action
    TriggerEvent('pvp-wars:internalSendAdminState', src)
end, false)

-- ============================================================
-- PICK A MAP  —  player chooses a map from the NPC's simple
-- map-select NUI. Teleports them there immediately (armed with
-- just the starter sidearm, no team yet, no kill payouts — this
-- is casual "hang out and scrap while we wait" only) and pings
-- the admins exactly like /warAdmin does.
-- ============================================================

RegisterNetEvent('pvp-wars:requestJoinMap')
AddEventHandler('pvp-wars:requestJoinMap', function(mapIndex)
    local src = source
    mapIndex = tonumber(mapIndex)

    if IsPlayerInWars(src) then
        NotifyPlayer(src, "You're already in an active Wars session.", {255, 150, 0})
        return
    end
    if not mapIndex or not WARS_MAPS[mapIndex] then
        NotifyPlayer(src, "Invalid map.", {255, 80, 80})
        return
    end
    if SESSION.active then
        NotifyPlayer(src, "A Wars session is already running — wait for it to end.", {255, 150, 0})
        return
    end

    local mapData = WARS_MAPS[mapIndex]
    SESSION.waiting[src] = mapIndex

    -- Auto-suggest this map to the admin panel if nothing's been set yet
    -- (admin can still change it later from the panel before starting).
    if not SESSION.map then
        SESSION.map = mapIndex
    end

    -- Give a single syringe to play with while waiting (separate pool from
    -- the 3-per-session grant at official start, see CONFIG.waitingSyringeQty).
    local inv = GetInv(src)
    inv[CONFIG.syringeItem] = math.max(inv[CONFIG.syringeItem] or 0, CONFIG.waitingSyringeQty)
    InvCache[src] = inv
    SaveInv(src, inv)

    TriggerClientEvent('pvp-wars:enterMapWaiting', src, {
        map      = mapIndex,
        mapName  = mapData.name,
        spawnPos = { x = mapData.waitSpawn.x, y = mapData.waitSpawn.y, z = mapData.waitSpawn.z, w = mapData.waitSpawn.w },
        syringe  = inv[CONFIG.syringeItem],
        money    = GetMoney(src),
    })

    RequestAdminHelp(src, ("entered the %s map and is waiting for a Wars session"):format(mapData.name))
end)

-- Public (non-admin) map list, used by the NPC's map-picker NUI so it
-- never has to hardcode map names/descriptions on the client side.
RegisterNetEvent('pvp-wars:requestMapList')
AddEventHandler('pvp-wars:requestMapList', function()
    local src = source
    local maps = {}
    for i, m in ipairs(WARS_MAPS) do
        table.insert(maps, { index = i, name = m.name, desc = m.desc })
    end
    TriggerClientEvent('pvp-wars:mapList', src, maps)
end)

-- Leaving the *waiting* area (not an official session) — separate from
-- pvp-wars:requestLeave below, which is for players already inside
-- SESSION.players.
RegisterNetEvent('pvp-wars:requestLeaveWaiting')
AddEventHandler('pvp-wars:requestLeaveWaiting', function()
    local src = source
    SESSION.waiting[src] = nil
    TriggerClientEvent('pvp-wars:leaveWaitingConfirmed', src)
end)

-- ============================================================
-- ADMIN NUI EVENTS
-- All changes come from the admin panel NUI (pvp-wars:adminAction)
-- ============================================================

local function BuildAdminState()
    local onlinePlayers = {}
    for _, pid in ipairs(GetPlayers()) do
        local pidNum = tonumber(pid)
        table.insert(onlinePlayers, { id = pidNum, name = GetPlayerName(pidNum) or "?" })
    end

    local alphaList = GetTeamList("alpha")
    local bravoList = GetTeamList("bravo")
    local maps = {}
    for i, m in ipairs(WARS_MAPS) do
        table.insert(maps, { index = i, name = m.name, desc = m.desc })
    end

    -- Surface who's just "waiting" on a map too, so the admin can see at
    -- a glance who showed up before building teams.
    local waitingList = {}
    for src, mapIdx in pairs(SESSION.waiting) do
        if GetPlayerName(src) then
            table.insert(waitingList, { id = src, name = GetPlayerName(src), mapName = WARS_MAPS[mapIdx] and WARS_MAPS[mapIdx].name or "?" })
        end
    end

    return {
        active      = SESSION.active,
        map         = SESSION.map,
        maps        = maps,
        alpha       = alphaList,
        bravo       = bravoList,
        allPlayers  = onlinePlayers,
        waiting     = waitingList,
    }
end

-- Shared by 'requestState' admin action and /warsAdminPanel
AddEventHandler('pvp-wars:internalSendAdminState', function(src)
    TriggerClientEvent('pvp-wars:adminState', src, BuildAdminState())
end)

RegisterNetEvent('pvp-wars:adminAction')
AddEventHandler('pvp-wars:adminAction', function(action, data)
    local src = source
    if not IsAdmin(src) then return end

    -- ── ADD PLAYER TO TEAM ──────────────────────────────────
    if action == 'assignTeam' then
        local targetId = tonumber(data.playerId)
        local side     = data.team  -- "alpha" or "bravo"

        if not targetId or not GetPlayerName(targetId) then
            TriggerClientEvent('pvp-wars:adminFeedback', src, "Player not found.", false)
            return
        end
        if side ~= "alpha" and side ~= "bravo" then
            TriggerClientEvent('pvp-wars:adminFeedback', src, "Invalid team. Must be alpha or bravo.", false)
            return
        end

        -- Remove from existing team first
        SESSION.teams.alpha[targetId] = nil
        SESSION.teams.bravo[targetId] = nil

        if CountTeam(side) >= CONFIG.maxPerTeam then
            TriggerClientEvent('pvp-wars:adminFeedback', src,
                ("Team %s is full (%d/%d)."):format(side:upper(), CONFIG.maxPerTeam, CONFIG.maxPerTeam), false)
            return
        end

        SESSION.teams[side][targetId] = true
        SESSION.pending[targetId] = true
        -- They're getting a real team now — clear them out of the casual
        -- "waiting" list so the admin panel doesn't show them in both.
        SESSION.waiting[targetId] = nil

        NotifyPlayer(targetId,
            ("You have been assigned to Team ~%s~ for the upcoming War. Stand by for admin to start!"):format(
                side == "alpha" and "b" or "r"), {100, 220, 255})
        TriggerClientEvent('pvp-wars:adminFeedback', src,
            ("%s assigned to %s."):format(GetPlayerName(targetId), side:upper()), true)
        TriggerClientEvent('pvp-wars:teamAssigned', targetId, side)

    -- ── REMOVE PLAYER FROM TEAMS ────────────────────────────
    elseif action == 'removePlayer' then
        local targetId = tonumber(data.playerId)
        if not targetId then return end
        SESSION.teams.alpha[targetId] = nil
        SESSION.teams.bravo[targetId] = nil
        SESSION.pending[targetId]     = nil
        TriggerClientEvent('pvp-wars:adminFeedback', src, "Player removed from teams.", true)

    -- ── SET MAP ─────────────────────────────────────────────
    elseif action == 'setMap' then
        local mapIndex = tonumber(data.mapIndex)
        if not mapIndex or not WARS_MAPS[mapIndex] then
            TriggerClientEvent('pvp-wars:adminFeedback', src, "Invalid map index.", false)
            return
        end
        SESSION.map = mapIndex
        TriggerClientEvent('pvp-wars:adminFeedback', src, ("Map set to %s."):format(WARS_MAPS[mapIndex].name), true)

    -- ── START SESSION ───────────────────────────────────────
    elseif action == 'startSession' then
        if SESSION.active then
            TriggerClientEvent('pvp-wars:adminFeedback', src, "A session is already active.", false)
            return
        end
        if not SESSION.map then
            TriggerClientEvent('pvp-wars:adminFeedback', src, "No map selected.", false)
            return
        end
        if CountTeam("alpha") < CONFIG.minPerTeam or CountTeam("bravo") < CONFIG.minPerTeam then
            TriggerClientEvent('pvp-wars:adminFeedback', src,
                ("Need at least %d player(s) on each team."):format(CONFIG.minPerTeam), false)
            return
        end

        SESSION.active = true
        local mapData  = WARS_MAPS[SESSION.map]

        -- Build player lookup and give each player syringes + push session start
        for side, teamTable in pairs(SESSION.teams) do
            for playerId, _ in pairs(teamTable) do
                if GetPlayerName(playerId) then
                    SESSION.players[playerId] = side
                    SESSION.waiting[playerId] = nil   -- now in the official match

                    -- Grant starting syringes
                    local inv = GetInv(playerId)
                    inv[CONFIG.syringeItem] = (inv[CONFIG.syringeItem] or 0) + CONFIG.syringeStartQty
                    InvCache[playerId] = inv
                    SaveInv(playerId, inv)

                    -- Build teammate list (same side, excluding self)
                    local teammates = {}
                    for tmId, _ in pairs(teamTable) do
                        if tmId ~= playerId and GetPlayerName(tmId) then
                            table.insert(teammates, { id = tmId, name = GetPlayerName(tmId) })
                        end
                    end

                    -- Pick spawn position (slot within team list)
                    local slotIndex = 0
                    local si = 0
                    for tmId, _ in pairs(teamTable) do
                        si = si + 1
                        if tmId == playerId then slotIndex = si end
                    end
                    slotIndex = math.max(1, math.min(slotIndex, #mapData.spawns[side]))
                    local spawnPos = mapData.spawns[side][slotIndex]

                    TriggerClientEvent('pvp-wars:sessionStart', playerId, {
                        map       = SESSION.map,
                        mapName   = mapData.name,
                        team      = side,
                        spawnPos  = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z, w = spawnPos.w },
                        teammates = teammates,
                        syringe   = inv[CONFIG.syringeItem] or 0,
                        money     = GetMoney(playerId),
                        loadout   = SESSION.loadouts[playerId],
                        ownedWeapons = GetOwned(playerId),
                    })
                end
            end
        end

        -- Notify all players in session of both team rosters
        local alphaRoster = GetTeamList("alpha")
        local bravoRoster = GetTeamList("bravo")
        BroadcastToSession('pvp-wars:rosterSync', alphaRoster, bravoRoster)

        NotifyPlayer(src, ("Wars session started on %s!"):format(mapData.name), {100, 255, 100})
        DiscordWebhook(("⚔️ **Wars Session Started** — Map: **%s** | Alpha: %d | Bravo: %d"):format(
            mapData.name, CountTeam("alpha"), CountTeam("bravo")))

    -- ── END SESSION ─────────────────────────────────────────
    elseif action == 'endSession' then
        EndSession("Admin ended session")

    -- ── SYNC ADMIN PANEL STATE ──────────────────────────────
    elseif action == 'requestState' then
        TriggerClientEvent('pvp-wars:adminState', src, BuildAdminState())
    end
end)

-- ============================================================
-- END SESSION
-- ============================================================

function EndSession(reason)
    if not SESSION.active then return end
    SESSION.active = false

    BroadcastToSession('pvp-wars:sessionEnd', reason or "Session ended")

    -- Clear session state
    SESSION.players  = {}
    SESSION.teams    = { alpha = {}, bravo = {} }
    SESSION.pending  = {}
    SESSION.map      = nil
    SESSION.loadouts = {}
    SESSION.waiting  = {}
    SESSION.kills    = {}

    print("[WARS] Session ended: " .. tostring(reason))
    DiscordWebhook("🏁 **Wars Session Ended** — " .. tostring(reason))
end

-- ============================================================
-- KILL FEED HANDLER  (receives from client, validates, rewards)
-- ============================================================

local RecentVictimKills = {}

-- Helper: build leaderboard sorted by total kills and push to all session
-- players AND anyone just waiting on a map (so their own kills/stats show
-- up on their own screen even before an admin starts the official match).
local function BroadcastLeaderboard()
    local rows = {}
    local seen = {}
    for src, _ in pairs(SESSION.players) do
        local name = GetPlayerName(src) or "?"
        local k = SESSION.kills[src] or { player = 0, npc = 0 }
        rows[#rows + 1] = {
            name   = name,
            player = k.player,
            npc    = k.npc,
            total  = k.player + k.npc,
        }
        seen[src] = true
    end
    for src, _ in pairs(SESSION.waiting) do
        if not seen[src] then
            local name = GetPlayerName(src) or "?"
            local k = SESSION.kills[src] or { player = 0, npc = 0 }
            rows[#rows + 1] = {
                name   = name,
                player = k.player,
                npc    = k.npc,
                total  = k.player + k.npc,
            }
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    BroadcastToSessionAndWaiting('pvp-wars:leaderboardUpdate', rows)
end

RegisterNetEvent('pvp-wars:killReport')
AddEventHandler('pvp-wars:killReport', function(victimName, isHeadshot, isNpc)
    local src = source

    -- TEMP DIAGNOSTIC: prints to server console so we can see exactly
    -- which gate (if any) is rejecting NPC kill reports during testing.
    -- Safe to remove once the real cause is confirmed from these logs.
    print(("[WARS DEBUG] killReport received: src=%s victim=%s headshot=%s isNpc=%s | InWars=%s Waiting=%s")
        :format(tostring(src), tostring(victimName), tostring(isHeadshot), tostring(isNpc),
                tostring(IsPlayerInWars(src)), tostring(IsPlayerWaiting(src))))

    -- FIX (scoped correctly this time): NPC kills should pay out
    -- whether you're just "waiting" on a map or in the official
    -- admin-started session -- that's the only thing that was asked
    -- for. Player-vs-player kills must NOT pay during waiting (no
    -- teams exist yet, it's not a scored match) -- that part stays
    -- restricted to an official session only, same as it always was.
    if isNpc then
        if not IsPlayerInWars(src) and not IsPlayerWaiting(src) then
            print("[WARS DEBUG] REJECTED: isNpc but not InWars and not Waiting")
            return
        end
    else
        if not IsPlayerInWars(src) then
            print("[WARS DEBUG] REJECTED: player kill but not InWars")
            return   -- only scored in an official session
        end
    end

    print("[WARS DEBUG] PASSED gate, proceeding to reward/broadcast")

    local killerName = GetPlayerName(src) or "?"
    local now        = GetGameTimer()

    if isNpc then
        -- NPC kill: no cooldown/team check needed, just reward and track
        local reward = CONFIG.killReward + (isHeadshot and CONFIG.headshotBonus or 0)
        AwardMoney(src, reward, "wars npc kill")
        if not SESSION.kills[src] then SESSION.kills[src] = { player = 0, npc = 0 } end
        SESSION.kills[src].npc = SESSION.kills[src].npc + 1
        BroadcastLeaderboard()
        BroadcastToSessionAndWaiting('pvp-wars:addKillFeed', killerName, "NPC", false)
        return
    end

    -- Player kill: victim lookup, cooldown, friendly-fire check
    local victimId = nil
    for _, pid in ipairs(GetPlayers()) do
        if GetPlayerName(tonumber(pid)) == victimName then
            victimId = tonumber(pid)
            break
        end
    end
    if victimId then
        if RecentVictimKills[victimId] and (now - RecentVictimKills[victimId]) < 3000 then return end
        RecentVictimKills[victimId] = now

        -- Friendly fire check: same team = no reward
        if SESSION.players[src] and SESSION.players[victimId] and
            SESSION.players[src] == SESSION.players[victimId] then
            return  -- don't reward team kills
        end
    end

    -- Reward
    local reward = CONFIG.killReward + (isHeadshot and CONFIG.headshotBonus or 0)
    AwardMoney(src, reward, isHeadshot and "wars kill+headshot" or "wars kill")

    -- Track kill for leaderboard
    if not SESSION.kills[src] then SESSION.kills[src] = { player = 0, npc = 0 } end
    SESSION.kills[src].player = SESSION.kills[src].player + 1

    -- Broadcast kill feed and leaderboard
    BroadcastToSession('pvp-wars:addKillFeed', killerName, victimName, isHeadshot)
    BroadcastLeaderboard()
    TriggerEvent('pvp-wars:internalKill', src, killerName, victimName, isHeadshot)

    DiscordWebhook(("⚔️ %s → %s | headshot: %s | reward: $%d"):format(
        killerName, victimName, tostring(isHeadshot), reward))
end)

-- ============================================================
-- SYRINGE USE  (client requests, server validates and deducts)
-- ============================================================

RegisterNetEvent('pvp-wars:useSyringe')
AddEventHandler('pvp-wars:useSyringe', function()
    local src = source
    if not IsPlayerInWars(src) and not IsPlayerWaiting(src) then return end

    local inv = GetInv(src)
    local qty = inv[CONFIG.syringeItem] or 0
    if qty <= 0 then
        TriggerClientEvent('pvp-wars:syringeResult', src, false, 0)
        return
    end

    inv[CONFIG.syringeItem] = qty - 1
    InvCache[src] = inv
    SaveInv(src, inv)

    -- Tell client: approved + remaining count
    TriggerClientEvent('pvp-wars:syringeResult', src, true, inv[CONFIG.syringeItem])
end)

-- ============================================================
-- SYRINGE PURCHASE  (Items tab in the Loadout Shop)
-- ============================================================

RegisterNetEvent('pvp-wars:buySyringe')
AddEventHandler('pvp-wars:buySyringe', function()
    local src = source
    if not IsPlayerInWars(src) and not IsPlayerWaiting(src) then return end

    local inv = GetInv(src)
    local qty = inv[CONFIG.syringeItem] or 0

    if qty >= CONFIG.syringeMaxOwned then
        TriggerClientEvent('pvp-wars:syringePurchaseResult', src, false, "max owned", qty)
        return
    end

    local balance = GetMoney(src)
    if balance < CONFIG.syringePrice then
        TriggerClientEvent('pvp-wars:syringePurchaseResult', src, false, "insufficient funds", qty)
        return
    end

    AwardMoney(src, -CONFIG.syringePrice, "wars shop: syringe")
    inv[CONFIG.syringeItem] = qty + 1
    InvCache[src] = inv
    SaveInv(src, inv)

    TriggerClientEvent('pvp-wars:syringePurchaseResult', src, true, "purchased", inv[CONFIG.syringeItem])
    DiscordWebhook(("💉 [WARS SHOP] %s (id:%d) bought a syringe for $%d (now has %d)"):format(
        GetPlayerName(src) or "?", src, CONFIG.syringePrice, inv[CONFIG.syringeItem]))
end)

-- ============================================================
-- LOADOUT SHOP  (wars-specific currency, wars-specific ownership)
-- ============================================================

RegisterNetEvent('pvp-wars:purchaseWeapon')
AddEventHandler('pvp-wars:purchaseWeapon', function(weaponHash)
    local src = source
    if not weaponHash or type(weaponHash) ~= 'string' then return end

    -- Use pvp-shop prices if available, otherwise flat 5000.
    -- FIX: the old code tried to check `exports[...]:GetWeaponPrice and ...`
    -- as if a colon-call could be referenced without calling it — that's
    -- what threw the "function arguments expected near 'and'" parse error
    -- on load. pcall the *whole* attempted call instead and just fall
    -- back to 5000 whenever it fails for any reason (resource not
    -- running, export renamed, etc.) — same pattern pvp-shop/pvp-economy
    -- already use everywhere else in this pack.
    local price = 5000
    local ok, p = pcall(function()
        return exports['pvp-shop']:GetWeaponPrice(weaponHash)
    end)
    if ok and p then price = p end

    local owned = GetOwned(src)
    if owned[weaponHash] then
        TriggerClientEvent('pvp-wars:purchaseResult', src, false, "already owned", weaponHash)
        return
    end

    local balance = GetMoney(src)
    if balance < price then
        TriggerClientEvent('pvp-wars:purchaseResult', src, false, "insufficient funds", weaponHash)
        return
    end

    AwardMoney(src, -price, ("wars shop: %s"):format(weaponHash))
    owned[weaponHash] = true
    OwnedCache[src] = owned
    SaveOwned(src, owned)

    TriggerClientEvent('pvp-wars:purchaseResult', src, true, "purchased", weaponHash)
    DiscordWebhook(("🔫 [WARS SHOP] %s (id:%d) bought %s for $%d"):format(
        GetPlayerName(src) or "?", src, weaponHash, price))
end)

RegisterNetEvent('pvp-wars:setLoadout')
AddEventHandler('pvp-wars:setLoadout', function(weaponHash)
    local src = source
    if not weaponHash then return end
    local owned = GetOwned(src)
    if not owned[weaponHash] then
        TriggerClientEvent('chat:addMessage', src, { color={255,80,80}, args={"[WARS]", "You don't own that weapon."} })
        return
    end
    SESSION.loadouts[src] = weaponHash
    TriggerClientEvent('pvp-wars:loadoutConfirmed', src, weaponHash)
end)

RegisterNetEvent('pvp-wars:requestShopData')
AddEventHandler('pvp-wars:requestShopData', function()
    local src = source
    local inv = GetInv(src)
    TriggerClientEvent('pvp-wars:shopData', src, {
        weapons       = LOADOUT_WEAPONS,
        owned         = GetOwned(src),
        money         = GetMoney(src),
        loadout       = SESSION.loadouts[src],
        syringeCount  = inv[CONFIG.syringeItem] or 0,
        syringePrice  = CONFIG.syringePrice,
        syringeMax    = CONFIG.syringeMaxOwned,
    })
end)

-- ============================================================
-- BALANCE REQUEST (from client HUD)
-- ============================================================

RegisterNetEvent('pvp-wars:requestBalance')
AddEventHandler('pvp-wars:requestBalance', function()
    local src = source
    TriggerClientEvent('pvp-wars:moneyUpdated', src, GetMoney(src))
end)

-- ============================================================
-- INVENTORY DATA  (used by the hotkey inventory panel)
-- ============================================================

RegisterNetEvent('pvp-wars:requestInventory')
AddEventHandler('pvp-wars:requestInventory', function()
    local src = source
    local inv = GetInv(src)
    TriggerClientEvent('pvp-wars:inventoryData', src, {
        syringe = inv[CONFIG.syringeItem] or 0,
        money   = GetMoney(src),
        loadout = SESSION.loadouts[src],
        -- FIX: included so the client can resolve the player's real
        -- in-hand weapon hash back to a name string even if the
        -- inventory (TAB) is opened before the shop (F4) ever is in
        -- this session -- without this, LOADOUT_WEAPON_NAMES on the
        -- client could still be empty and the "real equipped" lookup
        -- would silently fail to match anything.
        weapons = LOADOUT_WEAPONS,
    })
end)

-- ============================================================
-- LEAVE / DISCONNECT
-- ============================================================

RegisterNetEvent('pvp-wars:requestLeave')
AddEventHandler('pvp-wars:requestLeave', function()
    local src = source
    SESSION.players[src] = nil
    SESSION.teams.alpha[src] = nil
    SESSION.teams.bravo[src] = nil
    SESSION.waiting[src] = nil
    TriggerClientEvent('pvp-wars:leaveConfirmed', src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    SESSION.players[src]     = nil
    SESSION.teams.alpha[src] = nil
    SESSION.teams.bravo[src] = nil
    SESSION.pending[src]     = nil
    SESSION.waiting[src]     = nil
    MoneyCache[src]           = nil
    OwnedCache[src]           = nil
    InvCache[src]             = nil
    RecentVictimKills[src]    = nil
end)

-- ============================================================
-- RESPAWN REQUEST
-- ============================================================

RegisterNetEvent('pvp-wars:requestRespawn')
AddEventHandler('pvp-wars:requestRespawn', function()
    local src  = source
    local side = SESSION.players[src]
    if not side or not SESSION.map then return end

    local mapData = WARS_MAPS[SESSION.map]
    local teamTable = SESSION.teams[side]
    local slotIndex = 0
    local si = 0
    for tmId, _ in pairs(teamTable) do
        si = si + 1
        if tmId == src then slotIndex = si end
    end
    slotIndex = math.max(1, math.min(slotIndex, #mapData.spawns[side]))
    local spawnPos = mapData.spawns[side][slotIndex]

    -- Replenish 1 syringe on respawn (optional design choice — remove if unwanted)
    local inv = GetInv(src)
    inv[CONFIG.syringeItem] = math.min((inv[CONFIG.syringeItem] or 0) + 1, CONFIG.syringeStartQty)
    InvCache[src] = inv
    SaveInv(src, inv)

    TriggerClientEvent('pvp-wars:respawnApproved', src, {
        x = spawnPos.x, y = spawnPos.y, z = spawnPos.z, w = spawnPos.w
    }, inv[CONFIG.syringeItem])
end)

-- ============================================================
-- SERVER EXPORTS
-- ============================================================

exports('IsPlayerInWars', function(src)
    return IsPlayerInWars(src)
end)

exports('GetWarTeam', function(src)
    return SESSION.players[src]
end)

exports('GetWarsMoney', function(src)
    return GetMoney(src)
end)

-- ============================================================
-- STARTUP
-- ============================================================

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    print("[WARS] pvp-wars started. Admin ACE: " .. CONFIG.adminAce)
end)
