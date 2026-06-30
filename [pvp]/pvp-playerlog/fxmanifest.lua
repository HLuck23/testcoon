fx_version 'cerulean'
game 'gta5'
this_is_a_map 'yes'

description 'PvP Player Log - consolidated per-player record (license, username, money, weapons, kills, wins)'
version '1.0.0'

dependency 'pvp-economy'
dependency 'pvp-shop'
dependency 'pvp-hud'

server_scripts {
    'server.lua'
}

server_exports {
    'GetPlayerRecord',
    'GetRecordByDbId',
    'LicenseToDbId',
    'GetLeaderboardKills',
    'GetLeaderboardDeaths',
    'GetRecordByDiscordId',
    'SearchRecordByName'
}

lua54 'yes'
