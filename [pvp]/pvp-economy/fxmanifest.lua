fx_version 'cerulean'
game 'gta5'

description 'PvP Economy - server-authoritative money/rewards layered on top of pvp-core and pvp-turf'
version '1.0.0'

dependency 'pvp-turf'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

server_exports {
    'GetMoney',
    'AwardMoney'
}

lua54 'yes'
