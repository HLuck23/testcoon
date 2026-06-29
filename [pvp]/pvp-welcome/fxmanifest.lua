fx_version 'cerulean'
game 'gta5'

description 'PvP Welcome - First-load welcome screen with server info and command reference. Auto-shows once per session on hub spawn, reopen any time with /welcome or /info.'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html'
}

client_scripts {
    'client.lua'
}

lua54 'yes'
