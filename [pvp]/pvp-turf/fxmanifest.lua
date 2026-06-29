fx_version 'cerulean'
game 'gta5'

description 'PvP Turf Wars - Server-synced territory capture with globe zone, map rotation, smart respawns, NUI Arsenal'
version '3.1.0'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

server_exports {
    'IsPlayerInTurf',
    'IsTurfActive',
    'GetTurfPlayerCount'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/*.png'
}

lua54 'yes'
