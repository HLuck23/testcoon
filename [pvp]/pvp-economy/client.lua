-- ============================================================
-- PVP ECONOMY  —  CLIENT
-- This resource was previously server-only. The only thing this
-- client side needs to do is announce "I'm here" so the server can
-- proactively push the player's real money balance right away --
-- fixes money showing as unsynced / stuck at 0 until a shop UI
-- happened to be opened (nothing was requesting it before that).
-- ============================================================

AddEventHandler("onClientResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerServerEvent('pvp-economy:clientReady')
end)

-- Also re-announce on respawn, in case the very first announcement
-- raced the player's identifiers not being ready yet server-side.
AddEventHandler("playerSpawned", function()
    TriggerServerEvent('pvp-economy:clientReady')
end)
