# pvp-discordroles — setup

## 1. Enable Discord linking on your server
In `server.cfg`:
```
sv_discord_clientid "YOUR_DISCORD_APPLICATION_ID"
```
This is your Discord **application's** Client ID (Discord Developer Portal →
your app → General Information → "Application ID"). Not the bot token.

Without this, FiveM will never give you a `discord:` identifier for anyone,
and this whole resource will silently do nothing (it fails safe, never blocks
anyone from joining).

Players also need Discord **linked to their FiveM/Cfx.re account**
(cfx.re/account → Connections) and must have actually joined your Discord
server — if either is missing, they just won't get a tag/admin grant that
session.

## 2. Bot token
Discord Developer Portal → your app → Bot → Reset Token (do this if you've
ever typed/pasted the token anywhere outside server.cfg — treat any exposed
token as burned). Then in `server.cfg`:
```
set pvp_discord_bot_token "Bot YOUR_TOKEN_HERE"
```
Note the literal word `Bot ` (with the trailing space) before the token —
Discord's API requires that exact prefix.

Your bot also needs the **Server Members Intent** turned on:
Developer Portal → your app → Bot → Privileged Gateway Intents → toggle on
"Server Members Intent". Without it, the role lookup returns nothing.

## 3. Guild (server) ID
Discord → User Settings → Advanced → enable Developer Mode.
Then right-click your Discord server's icon → Copy Server ID.
```
set pvp_discord_guild_id "123456789012345678"
```

## 4. Role IDs
With Developer Mode on: Server Settings → Roles → right-click a role →
Copy Role ID.

Open `server.lua` and replace the placeholder strings in `ROLE_TAGS` and
`ADMIN_ROLE_ID` with your real role IDs. `ROLE_TAGS` is checked top to
bottom — the first one a player actually holds wins, so put your most
exclusive roles first.

## 5. Grant the ACE to the auto-managed group (one-time, in server.cfg)
```
add_ace group.pvpadmin_discord pvpadmin allow
```
This resource adds/removes individual players from `group.pvpadmin_discord`
based on whether they currently hold your configured Discord admin role —
the actual permission grant stays in this one line in server.cfg, so it's
easy to find and audit later. `pvpadmin` is the same permission
`pvp-admintools` and `pvp-wars`'s admin panel already check.

## 6. Start order
Make sure this resource starts (in server.cfg) — order relative to
pvp-wars/pvp-admintools doesn't matter, it doesn't depend on them.
```
ensure pvp-discordroles
```

## Notes
- Roles are checked **once on connect**, not re-polled while someone is
  online. If you change someone's Discord role while they're already
  connected, it takes effect the next time they reconnect.
- If you're using a chat resource other than FiveM's default `chat`, the
  `chatMessage` hook in server.lua may need adjusting to whatever event/
  format your chat resource expects instead.
- Nothing here blocks anyone from joining — if Discord lookup fails for
  any reason (no link, bot misconfigured, API error, rate limit), the
  player just connects with no tag and no admin grant, same as before
  this resource existed.
