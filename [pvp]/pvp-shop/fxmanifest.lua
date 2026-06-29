fx_version 'cerulean'
game 'gta5'

description 'PvP Shop - server-authoritative weapon unlocks, priced for meaningful grind'
version '1.0.0'

-- NOTE: this resource is server-only. The buy/equip UI lives inside
-- pvp-turf's existing arsenal menu (html/index.html) since that's
-- where the weapon list already was -- pvp-shop just supplies the
-- server-side price/ownership authority behind it.

dependency 'pvp-economy'

server_scripts {
    'prices.lua',
    'server.lua'
}

server_exports {
    'IsWeaponOwned',
    'GetOwnedWeapons',
    'WipeOwnedWeapons'
}

lua54 'yes'
