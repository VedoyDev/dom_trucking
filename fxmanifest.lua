fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_scripts {
	'@ox_lib/init.lua',
	'shared/language.lua',
	'config.lua'
}

client_scripts {
    'client.lua',
}

server_scripts {
	'server.lua',
}

files {
    'locales/*.json',
}