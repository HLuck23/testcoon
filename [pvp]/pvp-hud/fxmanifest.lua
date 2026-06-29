fx_version 'cerulean'
game 'gta5'

description 'PvP HUD - Scoreboard, Kill Feed, Match Timer, Health/Armor, Kill Streaks'
version '1.2.0'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/streaks/*',
    'html/peak.png',
    'minimap.gfx'
}

data_file 'SCALEFORM_DLC_FILE' 'minimap.gfx'

lua54 'yes'