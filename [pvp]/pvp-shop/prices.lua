-- ============================================================
-- WEAPON PRICES
-- Mirrors the WEAPONS list in pvp-turf/html/index.html exactly
-- (same hashes/names).
--
-- BALANCE NOTE (rebalanced):
-- New players start with $15,000 (see pvp-economy CONFIG.startingMoney).
-- SMG floor is priced so a new player can afford exactly ONE SMG and
-- has too little left for the next tier up -- they have to grind
-- (turf payouts / kills) for their second one. Pistols stay cheap
-- early, rifles are the long-term grind, misc stays low-priority.
-- ============================================================

-- The Badged Eagle is the default starter sidearm. Every player
-- owns it from their first spawn and it is NOT purchasable or
-- sellable -- intentionally the worst pistol in the game so players
-- have a reason to save up for something better. Keep this hash
-- out of WEAPON_PRICES; pvp-shop/server.lua checks IsStarterWeapon()
-- before allowing buy/sell on it.
STARTER_WEAPON = "weapon_badgedeagle"

function IsStarterWeapon(hash)
    if not hash then return false end
    return hash:lower() == STARTER_WEAPON:lower()
end

WEAPON_PRICES = {
    -- PISTOLS ($1,800 - $7,400)
    weapon_glock17s      = 1800,
    weapon_glock30       = 2200,
    weapon_glock34       = 2700,
    weapon_nbk           = 3200,
    weapon_revolver357   = 3900,
    weapon_glock18dt     = 5000,
    weapon_blackiceglock = 5800,
    WEAPON_ICEDGLOCK     = 6600,
    weapon_iceglock      = 7400,

    -- SMGs ($8,500 - $19,500)
    -- weapon_cx9 is intentionally ~57% of starting cash: affordable
    -- as a first SMG, but leaves too little for the next one up.
    weapon_cx9           = 8500,
    w_sb_minismg         = 9200,
    weapon_dssmg         = 10000,
    weapon_asm1          = 10800,
    weapon_mp40type2     = 11600,
    weapon_r99           = 12400,
    weapon_p90           = 13200,
    weapon_tbsvector     = 14000,
    weapon_icevector     = 14800,
    weapon_blastxspectre = 15600,
    weapon_candymp5      = 16400,
    weapon_crimsonsnowvector = 17200,
    weapon_blackicemp7   = 18000,
    weapon_vesperhybrid  = 18500,
    WEAPON_ICEDP90       = 19000,
    weapon_spaceflightmp5 = 19500,

    -- RIFLES ($12,000 - $32,000)
    weapon_minicarbine   = 12000,
    weapon_ibak          = 14000,
    weapon_acrcqb        = 16500,
    weapon_vss           = 19000,
    weapon_retrom4a4     = 21500,
    weapon_m4hyperbeast  = 24000,
    weapon_m4a1sgyspunkred = 26500,
    WEAPON_ICEDMZA       = 28500,
    WEAPON_ICEDQP12      = 30000,
    WEAPON_ICEDFAL       = 31000,
    WEAPON_KURONAMIVANDAL = 31500,
    WEAPON_ICEDR4C       = 32000,

    -- MISC ($2,500 - $11,000)
    weapon_nailgun       = 2500,
    weapon_junker        = 4200,
    weapon_hotshotwelder = 6800,
    WEAPON_ICEDBONGSHOT  = 11000,
}

-- Helper: case-insensitive lookup since the original list mixes
-- "weapon_x" and "WEAPON_X" casing inconsistently.
function GetWeaponPrice(hash)
    if WEAPON_PRICES[hash] then return WEAPON_PRICES[hash] end
    for k, v in pairs(WEAPON_PRICES) do
        if k:lower() == hash:lower() then return v end
    end
    return nil
end
