fx_version 'cerulean'
game 'gta5'

description 'PvP Admin Tools - in-game/console commands for looking up and editing player money/stats/weapons, gated by the pvpadmin ACE permission, logged to a Discord webhook'
version '1.0.0'

dependency 'pvp-economy'
dependency 'pvp-shop'
dependency 'pvp-playerlog'

server_scripts {
    'server.lua'
}

lua54 'yes'
