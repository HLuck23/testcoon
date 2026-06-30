local appId = 1519455012676173975

CreateThread(function()
    while true do
        SetDiscordAppId(appId)

        SetDiscordRichPresenceAsset('testimg1')
        SetDiscordRichPresenceAssetText('Smerkish PvP')

        SetDiscordRichPresenceAssetSmall('small_logo')
        SetDiscordRichPresenceAssetSmallText('Connect!')

        SetRichPresence('Next Upcoming Combat Server ')

        SetDiscordRichPresenceAction(
            0,
            'Join Server',
            'fivem://connect/52.14.112.59:40120'
        )

        SetDiscordRichPresenceAction(
            1,
            'Discord',
            'https://discord.gg/ZJ45JqRHt'
        )

        Wait(15000)
    end
end)