# pvp-admintools — setup

## 1. Add the resource

Drop the `pvp-admintools` folder into your resources directory alongside
your other `pvp-*` resources, then in `server.cfg` add it AFTER the
resources it depends on:

```
ensure pvp-economy
ensure pvp-shop
ensure pvp-playerlog
ensure pvp-admintools
```

## 2. Set the Discord webhook (REQUIRED for logging — without it, admin actions only print to the server console, never to chat)

Add to `server.cfg`, using your own webhook URL:

```
set turfwars_admintools_webhook "https://discord.com/api/webhooks/..."
```

Admin actions (money edits, stat resets, weapon wipes) are logged here,
**not** to in-game chat — keeps the chat window clean for everyone. The
admin who ran the command still gets a direct reply confirming it worked.

## 3. Grant yourself the permission (REQUIRED — nobody can use any command without this)

Add to `server.cfg`, using your own license identifier (the same one you'd
see in `/players` or in the pvp-playerlog Discord logs):

```
add_ace identifier.license:f75dc9b65ee456de1bb3df13352fffb69dbc1958 pvpadmin allow
```

Or, if you already have an admin group set up:

```
add_principal identifier.license:f75dc9b65ee456de1bb3df13352fffb69dbc1958 group.admin
add_ace group.admin pvpadmin allow
```

If you want to also run these from the server console (not just in-game
chat), console is usually already covered by default ACE rules, but if you
get refused there too, add:

```
add_ace group.console pvpadmin allow
```

## 4. Restart / reload

```
restart pvp-economy
restart pvp-shop
restart pvp-playerlog
ensure pvp-admintools
```

(or just restart the whole server)

## Commands

All of these work both typed in-game chat (with `/`) and directly in the
server console (without the `/`).

### `/pvplookup <name | src | license | dbId>`
Works for **online or offline** players. Shows money, K/D, turf kills/wins,
global kills/deaths, weapon count, license, last updated.

```
/pvplookup SoggyCrab8493
/pvplookup 3
/pvplookup license:f75dc9b65ee456de1bb3df13352fffb69dbc1958
/pvplookup f75dc9b65ee456de1bb3df13352fffb69dbc1958
```

### `/pvpmoney <name | src> <amount> [set]`
**Online players only.** Without `set`, the amount is ADDED to their
current balance (use a negative number to deduct). With `set`, the balance
is set to exactly that amount.

```
/pvpmoney SoggyCrab8493 5000        -- gives +$5000
/pvpmoney SoggyCrab8493 -1000       -- deducts $1000
/pvpmoney SoggyCrab8493 20000 set   -- sets balance to exactly $20000
```

### `/pvpresetstats <name | src> <kills|deaths|wins|all>`
**Online players only.** Resets the chosen global stat field(s) to 0.

```
/pvpresetstats SoggyCrab8493 kills
/pvpresetstats SoggyCrab8493 all
```

### `/pvptop <kills|deaths> [limit]`
Read-only leaderboard, default top 10.

```
/pvptop kills
/pvptop deaths 5
```

### `/pvpwipeweapons <name | src>`
**Online players only.** Wipes every weapon the player owns in
`pvp-shop`, then restores just the starter weapon (same as a fresh
join) — handy for resetting someone's loadout between turf rounds.

```
/pvpwipeweapons SoggyCrab8493
```

## Why money/stat edits require the player to be online

`pvp-economy`'s `AwardMoney` and `pvp-playerlog`'s stat-tracking both
operate on a connected player's session (`src`), which is how they resolve
identity and push live UI updates to that player's screen. There's no
"edit while offline" path in the existing resources, and per your call
this was left as-is rather than restructuring how those resources work.
`/pvplookup` is the one command that works offline, since it only reads
from pvp-playerlog's stored record by dbId, no live session needed.

## What changed in the existing resources

- **`pvp-playerlog/server.lua`**: added two new exports —
  `GetRecordByDbId(dbId)` (read a record without needing the player
  online) and `LicenseToDbId(licenseString)` (turn a pasted license into
  the same dbId pvp-economy/pvp-shop use) — plus one new event handler,
  `pvp-playerlog:adminResetField`, used internally by `/pvpresetstats`.
  Nothing existing was modified or removed.
- **`pvp-playerlog/fxmanifest.lua`**: those two new exports added to the
  `server_exports` list so other resources can actually call them.
- **`pvp-shop/server.lua`**: added one new export, `WipeOwnedWeapons(src)`,
  used by `/pvpwipeweapons`. Clears the player's owned-weapons KVP and
  re-grants the starter weapon. Nothing existing was modified or removed.
- **`pvp-shop/fxmanifest.lua`**: that new export added to `server_exports`.
- **No changes** to `pvp-economy` — `pvp-admintools` only calls its
  existing public exports.
