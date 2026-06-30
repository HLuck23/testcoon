fx_version 'cerulean'
game 'gta5'

description 'PvP Wars - 5v5 Team Deathmatch with Admin-Managed Teams, Loadouts, Syringe Heals, and Inventory Cash'
version '1.0.0'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

server_exports {
    'IsPlayerInWars',
    'GetWarTeam',
    'GetWarsMoney'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/*.png'
}

lua54 'yes'
