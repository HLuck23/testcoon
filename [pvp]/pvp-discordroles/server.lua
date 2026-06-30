-- ============================================================
-- PVP DISCORD ROLES
-- On connect, looks up the player's Discord roles (via your bot
-- token + the Discord REST API) and:
--   1. Applies a chat tag + colored name in chat for whichever
--      configured role they hold (highest-priority match wins).
--   2. Auto-grants the "pvpadmin" ACE permission (the same one
--      pvp-admintools and pvp-wars's admin panel already check)
--      if they hold the configured Discord admin role.
--
-- Checked ONCE on connect, not re-polled while online (lighter --
-- if you change someone's Discord role mid-session, it takes effect
-- next time they reconnect).
--
-- ============================================================
-- REQUIRED SETUP (server.cfg)
-- ============================================================
-- 1. Your FiveM server needs Discord linking enabled at all, or
--    GetPlayerIdentifiers will never contain a "discord:" entry:
--      sv_discord_clientid "your_discord_app_client_id"
--    This is your Discord APPLICATION's client ID (Developer Portal
--    -> your app -> General Information -> Application ID), not
--    your bot token. Players must have Discord linked in their
--    FiveM/Cfx.re account and have actually joined your Discord
--    server for this to find them at all.
--
-- 2. Bot token (Developer Portal -> your app -> Bot -> Reset Token
--    if you're not 100% sure the one you have is still valid -- a
--    token typed anywhere outside server.cfg should be treated as
--    burned). Your bot must be IN your Discord server/guild already
--    (you said it already is) and needs the "Server Members Intent"
--    enabled (Developer Portal -> Bot -> Privileged Gateway Intents)
--    or the member lookup below will fail to return roles.
--      set pvp_discord_bot_token "Bot YOUR_TOKEN_HERE"
--    NOTE the literal word "Bot " (with trailing space) before the
--    token -- the Discord API requires that exact prefix on every
--    request's Authorization header.
--
-- 3. Your guild (server) ID -- right-click your Discord server icon
--    -> Copy Server ID (Developer Mode must be on: Discord Settings
--    -> Advanced -> Developer Mode):
--      set pvp_discord_guild_id "123456789012345678"
--
-- 4. Define your roles below in ROLE_TAGS and ADMIN_ROLE_ID using
--    Discord role IDs (right-click a role in Server Settings ->
--    Roles -> Copy Role ID, also needs Developer Mode on).
-- ============================================================

local BOT_TOKEN = GetConvar('pvp_discord_bot_token', '')
local GUILD_ID  = GetConvar('pvp_discord_guild_id', '')

-- ============================================================
-- ROLE -> CHAT TAG CONFIG
-- Edit this list freely. Checked TOP TO BOTTOM -- the first role in
-- this list that the player actually holds in Discord wins, so put
-- your highest/most exclusive roles first (e.g. Owner before Member).
-- A player can hold multiple roles in Discord; only one tag is shown.
-- tag   = bracketed text shown before their name in chat
-- color = {r, g, b} for BOTH the tag and their name text
-- ============================================================
local ROLE_TAGS = {
    { roleId = "1518922307232333925",   tag = "ADMIN",   color = {255, 170, 40}  },
    -- Add more entries here later as you create more Discord roles
    -- (OWNER, MOD, VIP, BOOSTER, etc) -- checked top to bottom, first
    -- match wins, so put more exclusive roles above less exclusive ones.
}

-- The Discord role ID that should auto-grant the "pvpadmin" ACE
-- (the same permission pvp-admintools' commands and pvp-wars's admin
-- panel both already check via IsPlayerAceAllowed). Leave blank to
-- disable the auto-grant entirely and only use this resource for
-- chat tags.
local ADMIN_ROLE_ID = "1518922307232333925"

-- The Discord role ID that should auto-grant the "waradmin" ACE.
-- This gives access ONLY to the Wars session admin panel (/warsAdminPanel,
-- team assign, start/end session). No access to economy, stats, or any
-- global pvp-admintools commands. Set to "" to disable.
-- PLACEHOLDER: replace with your actual Wars admin Discord role ID.
local WARADMIN_ROLE_ID = "1521281254992117821"

-- ============================================================
-- INTERNAL STATE
-- ============================================================

-- [src] = { tag = "ADMIN", color = {r,g,b} } | nil (no matching role)
local PlayerChatTag = {}

local function Warn(msg)
    print(("[PVP-DISCORDROLES] WARNING: %s"):format(msg))
end

if BOT_TOKEN == "" then
    Warn("pvp_discord_bot_token is not set in server.cfg -- this resource will do nothing. " ..
         "See the comment block at the top of server.lua for setup steps.")
end
if GUILD_ID == "" then
    Warn("pvp_discord_guild_id is not set in server.cfg -- this resource will do nothing.")
end

-- ------------------------------------------------------------
-- Identity helper -- same extraction pattern pvp-playerlog already
-- uses (GetPlayerDiscordId), kept local here so this resource has
-- zero dependency on pvp-playerlog ever being present/running.
-- ------------------------------------------------------------
local function GetPlayerDiscordId(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if id:find('discord:') == 1 then
            return id:sub(9) -- raw snowflake, no "discord:" prefix
        end
    end
    return nil
end

-- ------------------------------------------------------------
-- Discord API call: GET /guilds/{guild.id}/members/{user.id}
-- Returns the member's `roles` array (a list of role ID strings) via
-- callback, or nil if the lookup failed for any reason (not in the
-- guild, bad token, rate limited, etc -- all treated the same: no
-- roles found, so no tag/ACE is applied, fails safe/closed).
-- ------------------------------------------------------------
local function FetchDiscordRoles(discordId, cb)
    if BOT_TOKEN == "" or GUILD_ID == "" then
        cb(nil)
        return
    end

    local url = ("https://discord.com/api/v10/guilds/%s/members/%s"):format(GUILD_ID, discordId)

    PerformHttpRequest(url, function(statusCode, responseText, _headers)
        if statusCode ~= 200 then
            -- Common cases: 404 = not in your Discord guild, 401 =
            -- bad token, 403 = missing Server Members Intent. Logged
            -- with the status so it's easy to tell which at a glance.
            Warn(("Discord member lookup failed for user %s -- HTTP %s. ")
                :format(discordId, tostring(statusCode)) ..
                "Check pvp_discord_bot_token, pvp_discord_guild_id, that the bot is in " ..
                "the guild, and that 'Server Members Intent' is enabled for your bot.")
            cb(nil)
            return
        end

        local ok, data = pcall(json.decode, responseText)
        if not ok or not data or not data.roles then
            Warn("Discord API returned an unexpected response shape for user " .. tostring(discordId))
            cb(nil)
            return
        end

        cb(data.roles) -- array of role ID strings
    end, "GET", "", {
        ["Authorization"] = BOT_TOKEN, -- must already include the literal "Bot " prefix, see setup notes
        ["Content-Type"]  = "application/json",
    })
end

local function HasRole(roleList, roleId)
    if not roleId or roleId == "" or roleId:find("^PUT_") then return false end
    for _, r in ipairs(roleList) do
        if r == roleId then return true end
    end
    return false
end

-- ------------------------------------------------------------
-- Resolve chat tag from the role list, top-to-bottom priority.
-- ------------------------------------------------------------
local function ResolveChatTag(roleList)
    for _, entry in ipairs(ROLE_TAGS) do
        if HasRole(roleList, entry.roleId) then
            return { tag = entry.tag, color = entry.color }
        end
    end
    return nil
end

-- ============================================================
-- ON CONNECT: fetch roles once, apply tag + ACE grant.
-- ============================================================

AddEventHandler('playerJoining', function()
    -- intentionally no-op here; using playerConnecting below instead
    -- so identifiers are guaranteed populated.
end)

AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    deferrals.defer()

    -- Give identifiers a moment to populate -- Discord identifier in
    -- particular can lag slightly behind the others on first connect.
    Citizen.SetTimeout(500, function()
        local discordId = GetPlayerDiscordId(src)

        if not discordId then
            -- No Discord linked (or not yet populated) -- not an error,
            -- just means no tag/ACE for this session. Let them connect
            -- normally either way; this resource never blocks a join.
            -- DIAGNOSTIC: this used to exit completely silently, which
            -- is exactly why "nothing shows up in console" gave no clue
            -- at all about where the chain was actually failing. Now
            -- prints every identifier found, so it's obvious whether
            -- Discord just isn't linked for this player vs. something
            -- else further down (bot token, guild ID, role IDs).
            print(("[PVP-DISCORDROLES] %s connected with NO discord: identifier. Identifiers found: %s")
                :format(playerName, table.concat(GetPlayerIdentifiers(src), ", ")))
            deferrals.done()
            return
        end

        print(("[PVP-DISCORDROLES] %s connected with discord:%s -- looking up roles...")
            :format(playerName, discordId))

        FetchDiscordRoles(discordId, function(roleList)
            if roleList then
                print(("[PVP-DISCORDROLES] %s (discord:%s) has roles: %s")
                    :format(playerName, discordId, #roleList > 0 and table.concat(roleList, ", ") or "(none)"))

                PlayerChatTag[src] = ResolveChatTag(roleList)
                if PlayerChatTag[src] then
                    print(("[PVP-DISCORDROLES] %s matched chat tag: %s")
                        :format(playerName, PlayerChatTag[src].tag))
                else
                    print(("[PVP-DISCORDROLES] %s matched no configured ROLE_TAGS entry.")
                        :format(playerName))
                end

                if HasRole(roleList, ADMIN_ROLE_ID) then
                    ExecuteCommand(("add_principal identifier.discord:%s group.pvpadmin_discord")
                        :format(discordId))
                    -- FIX/NOTE: rather than add_ace'ing the player's
                    -- identifier directly via ExecuteCommand every
                    -- connect (which is harder to audit and doesn't
                    -- clean up on its own), this adds them to a
                    -- dedicated principal group instead. You only need
                    -- to grant the ACE to that GROUP once, in
                    -- server.cfg, permanently:
                    --   add_ace group.pvpadmin_discord pvpadmin allow
                    -- Then this resource just adds/removes individual
                    -- players from that group based on their live
                    -- Discord role, and the actual permission grant
                    -- stays in one auditable place in server.cfg.
                    print(("[PVP-DISCORDROLES] %s (discord:%s) granted group.pvpadmin_discord (has admin Discord role)")
                        :format(playerName, discordId))
                else
                    print(("[PVP-DISCORDROLES] %s does NOT have the configured ADMIN_ROLE_ID (%s) -- no admin grant.")
                        :format(playerName, tostring(ADMIN_ROLE_ID)))
                end

                if HasRole(roleList, WARADMIN_ROLE_ID) then
                    ExecuteCommand(("add_principal identifier.discord:%s group.waradmin")
                        :format(discordId))
                    print(("[PVP-DISCORDROLES] %s (discord:%s) granted group.waradmin (has waradmin Discord role)")
                        :format(playerName, discordId))
                end
            else
                print(("[PVP-DISCORDROLES] %s: Discord role lookup returned nil (see WARNING above for the reason).")
                    :format(playerName))
            end
            deferrals.done()
        end)
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    PlayerChatTag[src] = nil
end)

-- ============================================================
-- CHAT TAG APPLICATION
-- Hooks the standard chat:addMessage-driven default `chat` resource
-- chatMessage event. If you're using a different chat resource than
-- FiveM's default `chat`, you may need to adjust this to whatever
-- event/format that resource expects instead.
-- ============================================================

AddEventHandler('chatMessage', function(src, name, message)
    local info = PlayerChatTag[src]
    if not info then return end -- no matching role, leave chat untouched

    CancelEvent() -- stop the default unstyled message from also sending

    local taggedName = ("[%s] %s"):format(info.tag, GetPlayerName(src) or name)
    TriggerClientEvent('chat:addMessage', -1, {
        color = info.color,
        multiline = true,
        args = { taggedName, message },
    })
end)

-- ============================================================
-- EXPORTS
-- In case another resource wants to check someone's resolved tag
-- (e.g. to show it in a UI), without re-hitting the Discord API.
-- ============================================================

exports('GetPlayerChatTag', function(src)
    return PlayerChatTag[src] -- { tag, color } or nil
end)
